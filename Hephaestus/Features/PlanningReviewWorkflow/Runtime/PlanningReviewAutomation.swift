import Foundation

typealias PlanningReviewMessagePersistenceHandler = ([WorkflowMessage]) async throws -> Void

protocol PlanningReviewAutomating {
    var reviewCycleCount: Int { get }
    var startedTimeline: String { get }

    func runCycle(
        cycle: Int,
        project: WorkflowProject,
        currentPlanMessage: WorkflowMessage,
        run: inout PlanningReviewPrototypeAutomationRun,
        persistMessages: PlanningReviewMessagePersistenceHandler,
        progress: WorkflowProgressHandler?
    ) async

    func finish(_ run: PlanningReviewPrototypeAutomationRun) -> ProcessResult
}

struct PlanningReviewPrototypeAutomation {
    static let reviewers = ["Reviewer A", "Reviewer B"]
    let reviewCycleCount = 2
    let agentStep: CodexAgentStep

    init(agentStep: CodexAgentStep) {
        self.agentStep = agentStep
    }

    var startedTimeline: String {
        """
        Planning Review Workflow started.
        Interactive planning phase submitted a plan artifact.
        Automated review cycles started.
        """
    }
}

extension PlanningReviewPrototypeAutomation: PlanningReviewAutomating {
    func runCycle(
        cycle: Int,
        project: WorkflowProject,
        currentPlanMessage: WorkflowMessage,
        run: inout PlanningReviewPrototypeAutomationRun,
        persistMessages: PlanningReviewMessagePersistenceHandler,
        progress: WorkflowProgressHandler?
    ) async {
        let reviewerRecords = await runReviewerCycle(
            cycle: cycle,
            project: project,
            currentPlanMessage: currentPlanMessage,
            planPath: run.planPath
        )
        run.records.append(contentsOf: reviewerRecords.records)
        guard let consolidatedMessage = await applyReviewerCycleResult(
            reviewerRecords,
            cycle: cycle,
            run: &run,
            persistMessages: persistMessages,
            progress: progress
        ) else { return }
        let responseRecord = await runPlannerResponse(
            cycle: cycle,
            project: project,
            currentPlanMessage: currentPlanMessage,
            reviewMessage: consolidatedMessage
        )
        run.records.append(responseRecord.record)
        await applyPlannerResponseResult(
            responseRecord,
            previousPlanMessage: currentPlanMessage,
            cycle: cycle,
            run: &run,
            persistMessages: persistMessages,
            progress: progress
        )
    }

    func finish(_ run: PlanningReviewPrototypeAutomationRun) -> ProcessResult {
        var finishedRun = run
        if let terminalFailure = finishedRun.terminalFailure {
            return failureResult(&finishedRun, reason: terminalFailure)
        }
        if let failedRecord = finishedRun.records.first(where: { isTerminalFailedRecord($0) }) {
            return failureResult(&finishedRun, reason: "Failed at \(failedRecord.title).")
        }
        return userReviewResult(&finishedRun)
    }

    private func runReviewerCycle(
        cycle: Int,
        project: WorkflowProject,
        currentPlanMessage: WorkflowMessage,
        planPath: String
    ) async -> PlanningReviewCycleResult {
        async let reviewerA = runReviewer(
            name: Self.reviewers[0],
            cycle: cycle,
            project: project,
            currentPlanMessage: currentPlanMessage,
            planPath: planPath
        )
        async let reviewerB = runReviewer(
            name: Self.reviewers[1],
            cycle: cycle,
            project: project,
            currentPlanMessage: currentPlanMessage,
            planPath: planPath
        )
        let results = await [reviewerA, reviewerB]
        let reviewerMessages = reviewMessages(
            from: results,
            cycle: cycle,
            currentPlanMessage: currentPlanMessage
        )
        guard !reviewerMessages.isEmpty else {
            return PlanningReviewCycleResult(
                records: reviewRecords(from: results, cycle: cycle),
                workflowMessages: [],
                consolidatedMessage: nil
            )
        }
        let consolidatedMessage = consolidatedReviewMessage(
            cycle: cycle,
            currentPlanMessage: currentPlanMessage,
            reviewerRuns: results,
            reviewerMessages: reviewerMessages
        )
        return PlanningReviewCycleResult(
            records: reviewRecords(from: results, cycle: cycle),
            workflowMessages: reviewerMessages + [consolidatedMessage],
            consolidatedMessage: consolidatedMessage
        )
    }

    private func runPlannerResponse(
        cycle: Int,
        project: WorkflowProject,
        currentPlanMessage: WorkflowMessage,
        reviewMessage: WorkflowMessage
    ) async -> (record: WorkflowStepRecord, message: WorkflowMessage) {
        let prompt = plannerResponsePrompt(
            project: project,
            currentPlanMessage: currentPlanMessage,
            reviewMessage: reviewMessage
        )
        let result = await agentStep.run(
            CodexAgentInvocation(
                name: "Planner Response Cycle \(cycle)",
                project: project,
                prompt: prompt,
                timeoutSeconds: 180,
                sandboxMode: "read-only"
            ))
        let record = WorkflowStepRecord(
            id: "planning-review-planner-response-\(cycle)",
            title: "Planner response cycle \(cycle)",
            status: result.exitCode == 0 ? .succeeded : .failed,
            summary: result.exitCode == 0
                ? "Planner responded to review feedback cycle \(cycle)."
                : "Planner response failed in cycle \(cycle).",
            inputPreview: prompt,
            outputPreview: result.output,
            sortOrder: 130 + (cycle * 100)
        )
        let message = WorkflowMessage(
            runID: currentPlanMessage.runID,
            kind: .plannerResponse,
            producerStepID: record.id,
            payload: .plannerResponse(
                PlannerResponseMessagePayload(
                    reviewMessageID: reviewMessage.id,
                    cycle: cycle,
                    response: result.output,
                    exitCode: result.exitCode
                )
            ),
            summary: record.summary
        )
        return (record, message)
    }
}
