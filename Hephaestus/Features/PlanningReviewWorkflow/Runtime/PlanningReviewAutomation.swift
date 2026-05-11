import Foundation

protocol PlanningReviewAutomating {
    var reviewCycleCount: Int { get }
    var startedTimeline: String { get }

    func runCycle(
        cycle: Int,
        project: WorkflowProject,
        submittedOutput: InteractiveStepOutput,
        run: inout PlanningReviewPrototypeAutomationRun,
        progress: WorkflowProgressHandler?
    ) async

    func finish(_ run: PlanningReviewPrototypeAutomationRun) -> ProcessResult
}

struct PlanningReviewPrototypeAutomation {
    private static let reviewers = ["Reviewer A", "Reviewer B"]
    let reviewCycleCount = 2
    private let agentStep: CodexAgentStep

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
        submittedOutput: InteractiveStepOutput,
        run: inout PlanningReviewPrototypeAutomationRun,
        progress: WorkflowProgressHandler?
    ) async {
        let reviewerRecords = await runReviewerCycle(
            cycle: cycle,
            project: project,
            submittedOutput: submittedOutput,
            planPath: run.planPath
        )
        run.records.append(contentsOf: reviewerRecords.records)
        run.timeline += "\nAutomated review cycle \(cycle) completed."
        await progress?(
            WorkflowRunProgress(timeline: run.timeline, debugLogURL: nil, stepRecords: run.records)
        )

        let responseRecord = await runPlannerResponse(
            cycle: cycle,
            project: project,
            submittedOutput: submittedOutput,
            feedback: reviewerRecords.feedback
        )
        run.records.append(responseRecord)
        run.timeline += "\nPlanner response cycle \(cycle) completed."
        await progress?(
            WorkflowRunProgress(timeline: run.timeline, debugLogURL: nil, stepRecords: run.records)
        )
    }

    func finish(_ run: PlanningReviewPrototypeAutomationRun) -> ProcessResult {
        var finishedRun = run
        if let failedRecord = finishedRun.records.first(where: { $0.status == .failed }) {
            finishedRun.timeline += "\nAutomated review cycles failed at \(failedRecord.title)."
            return ProcessResult(
                exitCode: 1,
                output: """
                    == Planning Review Workflow ==
                    Automated review cycles failed at \(failedRecord.title).
                    Inspect the run updates and retry after addressing the failure.
                    """,
                timeline: finishedRun.timeline,
                stepRecords: finishedRun.records
            )
        }
        finishedRun.records.append(userReviewRecord())
        finishedRun.timeline += "\nInteractive user review is waiting."
        return ProcessResult(
            exitCode: 0,
            output: """
                == Planning Review Workflow ==
                Automated review cycles completed for \(finishedRun.planPath).
                Interactive user review is waiting.
                """,
            timeline: finishedRun.timeline,
            stepRecords: finishedRun.records
        )
    }

    private func runReviewerCycle(
        cycle: Int,
        project: WorkflowProject,
        submittedOutput: InteractiveStepOutput,
        planPath: String
    ) async -> (records: [WorkflowStepRecord], feedback: String) {
        async let reviewerA = runReviewer(
            name: Self.reviewers[0],
            cycle: cycle,
            project: project,
            submittedOutput: submittedOutput,
            planPath: planPath
        )
        async let reviewerB = runReviewer(
            name: Self.reviewers[1],
            cycle: cycle,
            project: project,
            submittedOutput: submittedOutput,
            planPath: planPath
        )
        let results = await [reviewerA, reviewerB]
        return (reviewRecords(from: results, cycle: cycle), reviewFeedback(from: results))
    }

    private func runPlannerResponse(
        cycle: Int,
        project: WorkflowProject,
        submittedOutput: InteractiveStepOutput,
        feedback: String
    ) async -> WorkflowStepRecord {
        let prompt = plannerResponsePrompt(
            project: project,
            submittedOutput: submittedOutput,
            feedback: feedback
        )
        let result = await agentStep.run(
            CodexAgentInvocation(
                name: "Planner Response Cycle \(cycle)",
                project: project,
                prompt: prompt,
                timeoutSeconds: 180,
                sandboxMode: "read-only"
            ))
        return WorkflowStepRecord(
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
    }

    private func userReviewRecord() -> WorkflowStepRecord {
        WorkflowStepRecord(
            id: "planning-review-interactive-user-review",
            title: "Interactive user review",
            status: .inProgress,
            summary: "Automated cycles completed. Waiting for the user to review the latest plan.",
            sortOrder: 400
        )
    }

    private func runReviewer(
        name: String,
        cycle: Int,
        project: WorkflowProject,
        submittedOutput: InteractiveStepOutput,
        planPath: String
    ) async -> PlanningReviewerRun {
        let prompt = reviewerPrompt(
            name: name,
            project: project,
            submittedOutput: submittedOutput,
            planPath: planPath
        )
        let result = await agentStep.run(
            CodexAgentInvocation(
                name: "\(name) Planning Review Cycle \(cycle)",
                project: project,
                prompt: prompt,
                timeoutSeconds: 120,
                sandboxMode: "read-only"
            ))
        return PlanningReviewerRun(name: name, prompt: prompt, result: result)
    }

    private func reviewRecords(
        from results: [PlanningReviewerRun],
        cycle: Int
    ) -> [WorkflowStepRecord] {
        results.enumerated().map { offset, result in
            WorkflowStepRecord(
                id: "planning-review-reviewer-\(cycle)-\(offset + 1)",
                title: "\(result.name) cycle \(cycle)",
                status: result.result.exitCode == 0 ? .succeeded : .failed,
                summary: result.result.exitCode == 0
                    ? "\(result.name) finished review cycle \(cycle)."
                    : "\(result.name) failed review cycle \(cycle).",
                inputPreview: result.prompt,
                outputPreview: result.result.output,
                sortOrder: 100 + (cycle * 100) + offset
            )
        }
    }

    private func reviewFeedback(from results: [PlanningReviewerRun]) -> String {
        results
            .map { "\($0.name):\n\($0.result.output)" }
            .joined(separator: "\n\n")
    }

    private func reviewerPrompt(
        name: String,
        project: WorkflowProject,
        submittedOutput: InteractiveStepOutput,
        planPath: String
    ) -> String {
        """
        You are \(name), a review-only planning agent.

        Review the submitted implementation plan. Do not edit files.

        Project path: \(project.path)
        Plan artifact path: \(planPath)

        Plan content:
        \(submittedOutput.artifact.content)

        Return at most 5 findings with severity P1, P2, or P3. Return exactly "pass" if the plan is
        clear, scoped, and testable.
        """
    }

    private func plannerResponsePrompt(
        project: WorkflowProject,
        submittedOutput: InteractiveStepOutput,
        feedback: String
    ) -> String {
        """
        You are the planner agent responding to automated review feedback.

        Do not edit files. Explain how the plan should change, then provide a revised markdown plan.

        Project path: \(project.path)

        Current plan:
        \(submittedOutput.artifact.content)

        Review feedback:
        \(feedback)
        """
    }
}

struct PlanningReviewPrototypeAutomationRun {
    var timeline: String
    var records: [WorkflowStepRecord]
    var planPath: String
}

struct PlanningReviewerRun {
    let name: String
    let prompt: String
    let result: ProcessResult
}
