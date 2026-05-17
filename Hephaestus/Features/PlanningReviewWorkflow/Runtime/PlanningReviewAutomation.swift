import Foundation

protocol PlanningReviewAutomating {
    var reviewCycleCount: Int { get }
    var startedTimeline: String { get }

    func runCycle(
        cycle: Int,
        project: WorkflowProject,
        run: inout PlanningReviewAutomationRun,
        progress: WorkflowProgressHandler?
    ) async -> Bool

    func finish(_ run: PlanningReviewAutomationRun) -> ProcessResult
}

struct PlanningReviewPrototypeAutomation {
    private static let reviewers = ["Reviewer A", "Reviewer B"]
    let reviewCycleCount = 2
    let agent: any PlanningAgentRunning
    let artifactStore: any PlanningPlanArtifactMaterializing

    init(
        agent: any PlanningAgentRunning,
        artifactStore: any PlanningPlanArtifactMaterializing
    ) {
        self.agent = agent
        self.artifactStore = artifactStore
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
        run: inout PlanningReviewAutomationRun,
        progress: WorkflowProgressHandler?
    ) async -> Bool {
        guard let currentPlanOutput = run.currentPlanOutput else {
            markMissingCurrentPlan(cycle: cycle, run: &run)
            return false
        }
        let reviewerResults = await runReviewers(
            cycle: cycle,
            project: project,
            planOutput: currentPlanOutput,
            planPath: run.planPath
        )
        let reviewerRecords = reviewRecords(from: reviewerResults, cycle: cycle)
        run.records.append(contentsOf: reviewerRecords)

        guard let feedback = await appendConsolidatedFeedback(
            from: reviewerResults,
            project: project,
            cycle: cycle,
            run: &run,
            progress: progress
        ) else { return false }
        await appendReviewerCycle(feedback, cycle: cycle, run: &run, progress: progress)

        guard await canRunPlannerResponse(feedback, cycle: cycle, run: &run, progress: progress)
        else { return false }

        let responseRecord = await runPlannerResponse(
            cycle: cycle,
            project: project,
            sessionID: run.sessionID,
            currentPlanOutput: currentPlanOutput,
            consolidatedFeedbackOutput: feedback.consolidatedOutput
        )
        return await appendPlannerResponse(responseRecord, cycle: cycle, run: &run, progress: progress)
    }

    private func appendConsolidatedFeedback(
        from reviewerResults: [PlanningReviewerRun],
        project: WorkflowProject,
        cycle: Int,
        run: inout PlanningReviewAutomationRun,
        progress: WorkflowProgressHandler?
    ) async -> PlanningReviewCycleFeedback? {
        do {
            return try makeCycleFeedback(
                from: reviewerResults,
                project: project,
                sessionID: run.sessionID,
                cycle: cycle
            )
        } catch {
            await appendAutomationFailure(
                id: "planning-review-consolidated-feedback-\(cycle)",
                title: "Consolidated feedback cycle \(cycle)",
                summary: "Could not persist consolidated review feedback: \(error.localizedDescription)",
                cycle: cycle,
                run: &run,
                progress: progress
            )
            return nil
        }
    }

    private func markMissingCurrentPlan(
        cycle: Int,
        run: inout PlanningReviewAutomationRun
    ) {
        let record = WorkflowStepRecord(
            id: "planning-review-cycle-\(cycle)-missing-plan",
            title: "Review cycle \(cycle)",
            status: .failed,
            summary: "Automated review cycle could not start because no current plan output exists.",
            sortOrder: 100 + (cycle * 100)
        )
        run.terminalFailureRecordID = record.id
        run.records.append(record)
    }

    private func appendReviewerCycle(
        _ reviewerRecords: PlanningReviewCycleFeedback,
        cycle: Int,
        run: inout PlanningReviewAutomationRun,
        progress: WorkflowProgressHandler?
    ) async {
        run.records.append(reviewerRecords.consolidatedRecord)
        run.relatedOutputs.append(reviewerRecords.consolidatedOutput)
        run.timeline += "\nAutomated review cycle \(cycle) completed."
        await progress?(
            WorkflowRunProgress(timeline: run.timeline, debugLogURL: nil, stepRecords: run.records)
        )
    }

    private func canRunPlannerResponse(
        _ reviewerRecords: PlanningReviewCycleFeedback,
        cycle: Int,
        run: inout PlanningReviewAutomationRun,
        progress: WorkflowProgressHandler?
    ) async -> Bool {
        guard !reviewerRecords.successfulReviewerResults.isEmpty else {
            run.terminalFailureRecordID = reviewerRecords.consolidatedRecord.id
            run.timeline += "\nPlanner response cycle \(cycle) skipped because all reviewers failed."
            await progress?(
                WorkflowRunProgress(timeline: run.timeline, debugLogURL: nil, stepRecords: run.records)
            )
            return false
        }
        return true
    }

    private func appendPlannerResponse(
        _ responseRecord: PlanningPlannerResponseRun,
        cycle: Int,
        run: inout PlanningReviewAutomationRun,
        progress: WorkflowProgressHandler?
    ) async -> Bool {
        run.records.append(responseRecord.record)
        if responseRecord.record.status == .failed {
            run.terminalFailureRecordID = responseRecord.record.id
        }
        if let revisedPlanOutput = responseRecord.revisedPlanOutput {
            run.currentPlanOutput = revisedPlanOutput
            run.relatedOutputs.append(revisedPlanOutput)
            run.planPath = revisedPlanOutput.artifact.projectRelativePath ?? run.planPath
        }
        run.timeline += "\nPlanner response cycle \(cycle) completed."
        await progress?(
            WorkflowRunProgress(timeline: run.timeline, debugLogURL: nil, stepRecords: run.records)
        )
        return responseRecord.record.status != .failed
    }

    func finish(_ run: PlanningReviewAutomationRun) -> ProcessResult {
        var finishedRun = run
        let failedRecord = finishedRun.terminalFailureRecordID.flatMap { id in
            finishedRun.records.first { $0.id == id }
        }
            ?? finishedRun.records.first(where: { record in
                record.status == .failed && !record.id.hasPrefix("planning-review-reviewer-")
            })
            ?? (finishedRun.relatedOutputs.isEmpty
                ? finishedRun.records.first(where: { $0.status == .failed })
                : nil)
        if let failedRecord {
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
                Latest reviewed plan: \(finishedRun.currentPlanOutput?.summary ?? "No revised plan summary available.")
                Interactive user review is waiting.
                """,
            timeline: finishedRun.timeline,
            stepRecords: finishedRun.records
        )
    }

    private func runReviewers(
        cycle: Int,
        project: WorkflowProject,
        planOutput: InteractiveStepOutput,
        planPath: String
    ) async -> [PlanningReviewerRun] {
        async let reviewerA = runReviewer(
            name: Self.reviewers[0],
            cycle: cycle,
            project: project,
            planOutput: planOutput,
            planPath: planPath
        )
        async let reviewerB = runReviewer(
            name: Self.reviewers[1],
            cycle: cycle,
            project: project,
            planOutput: planOutput,
            planPath: planPath
        )
        return await [reviewerA, reviewerB]
    }

    private func makeCycleFeedback(
        from results: [PlanningReviewerRun],
        project: WorkflowProject,
        sessionID: String,
        cycle: Int
    ) throws -> PlanningReviewCycleFeedback {
        let consolidatedOutput = try consolidatedFeedbackOutput(
            from: results,
            project: project,
            sessionID: sessionID,
            cycle: cycle
        )
        return PlanningReviewCycleFeedback(
            consolidatedRecord: consolidatedFeedbackRecord(
                output: consolidatedOutput,
                results: results,
                cycle: cycle
            ),
            consolidatedOutput: consolidatedOutput,
            successfulReviewerResults: results.filter { $0.result.exitCode == 0 }
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
        planOutput: InteractiveStepOutput,
        planPath: String
    ) async -> PlanningReviewerRun {
        let prompt = reviewerPrompt(
            name: name,
            project: project,
            planOutput: planOutput,
            planPath: planPath
        )
        let result = await agent.run(
            PlanningAgentInvocation(
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

    private func consolidatedFeedbackOutput(
        from results: [PlanningReviewerRun],
        project: WorkflowProject,
        sessionID: String,
        cycle: Int
    ) throws -> InteractiveStepOutput {
        let content = results
            .map { result in
                let status = result.result.exitCode == 0 ? "succeeded" : "failed"
                return """
                ## \(result.name)
                Status: \(status)

                \(result.result.output)
                """
            }
            .joined(separator: "\n\n")
        return try artifactStore.materializeConsolidatedFeedback(
            project: project,
            sessionID: sessionID,
            cycle: cycle,
            content: content
        )
    }

    private func consolidatedFeedbackRecord(
        output: InteractiveStepOutput,
        results: [PlanningReviewerRun],
        cycle: Int
    ) -> WorkflowStepRecord {
        let failedCount = results.filter { $0.result.exitCode != 0 }.count
        let succeededCount = results.count - failedCount
        let status: WorkflowStepRecordStatus = succeededCount == 0 ? .failed : .succeeded
        return WorkflowStepRecord(
            id: "planning-review-consolidated-feedback-\(cycle)",
            title: "Consolidated feedback cycle \(cycle)",
            status: status,
            summary: failedCount == 0
                ? "Created consolidated review feedback message for cycle \(cycle)."
                : "Created consolidated review feedback message with \(failedCount) failed reviewer(s).",
            inputPreview: "Reviewer outputs: \(results.map(\.name).joined(separator: ", "))",
            outputPreview: output.artifact.content,
            sortOrder: 120 + (cycle * 100)
        )
    }

    private func appendAutomationFailure(
        id: WorkflowStepRecord.ID,
        title: String,
        summary: String,
        cycle: Int,
        run: inout PlanningReviewAutomationRun,
        progress: WorkflowProgressHandler?
    ) async {
        let record = WorkflowStepRecord(
            id: id,
            title: title,
            status: .failed,
            summary: summary,
            sortOrder: 120 + (cycle * 100)
        )
        run.terminalFailureRecordID = record.id
        run.records.append(record)
        run.timeline += "\nAutomated review cycle \(cycle) failed at \(title)."
        await progress?(
            WorkflowRunProgress(timeline: run.timeline, debugLogURL: nil, stepRecords: run.records)
        )
    }

}
