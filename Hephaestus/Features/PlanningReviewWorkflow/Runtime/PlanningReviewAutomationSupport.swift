import Foundation

extension PlanningReviewPrototypeAutomation {
    func applyReviewerCycleResult(
        _ reviewerRecords: PlanningReviewCycleResult,
        cycle: Int,
        run: inout PlanningReviewPrototypeAutomationRun,
        persistMessages: PlanningReviewMessagePersistenceHandler,
        progress: WorkflowProgressHandler?
    ) async -> WorkflowMessage? {
        guard let consolidatedMessage = reviewerRecords.consolidatedMessage else {
            run.terminalFailure = "All reviewers failed in cycle \(cycle)."
            run.timeline += "\nAutomated review cycle \(cycle) failed because all reviewers failed."
            await publishProgress(run, progress: progress)
            return nil
        }
        do {
            try await persistMessages(reviewerRecords.workflowMessages)
        } catch {
            run.terminalFailure =
                "Workflow message persistence failed before planner response: \(error.localizedDescription)"
            run.records.append(messagePersistenceFailureRecord(cycle: cycle, error: error))
            run.timeline += "\nAutomated review cycle \(cycle) failed before planner response."
            await publishProgress(run, progress: progress)
            return nil
        }
        run.workflowMessages.append(contentsOf: reviewerRecords.workflowMessages)
        run.timeline += "\nAutomated review cycle \(cycle) completed."
        await publishProgress(run, progress: progress)
        return consolidatedMessage
    }

    func applyPlannerResponseResult(
        _ responseRecord: (record: WorkflowStepRecord, message: WorkflowMessage),
        previousPlanMessage: WorkflowMessage,
        cycle: Int,
        run: inout PlanningReviewPrototypeAutomationRun,
        persistMessages: PlanningReviewMessagePersistenceHandler,
        progress: WorkflowProgressHandler?
    ) async {
        var responseMessages = [responseRecord.message]
        let currentPlanMessage = makeCurrentPlanMessage(
            from: responseRecord.message,
            previousPlanMessage: previousPlanMessage,
            cycle: cycle,
            recordID: responseRecord.record.id
        )
        if let currentPlanMessage {
            responseMessages.append(currentPlanMessage)
            run.currentPlanMessage = currentPlanMessage
        }
        do {
            try await persistMessages(responseMessages)
        } catch {
            run.terminalFailure =
                "Workflow message persistence failed after planner response: \(error.localizedDescription)"
            run.records.append(messagePersistenceFailureRecord(cycle: cycle, error: error))
            run.timeline += "\nPlanner response cycle \(cycle) failed while persisting messages."
            await publishProgress(run, progress: progress)
            return
        }
        run.workflowMessages.append(contentsOf: responseMessages)
        if responseRecord.record.status == .failed {
            run.terminalFailure = "Planner response failed in cycle \(cycle)."
            run.timeline += "\nPlanner response cycle \(cycle) failed."
        } else {
            run.timeline += "\nPlanner response cycle \(cycle) completed."
        }
        await publishProgress(run, progress: progress)
    }

    func failureResult(
        _ run: inout PlanningReviewPrototypeAutomationRun,
        reason: String
    ) -> ProcessResult {
        run.timeline += "\nAutomated review cycles failed: \(reason)"
        return ProcessResult(
            exitCode: 1,
            output: """
                == Planning Review Workflow ==
                Automated review cycles failed: \(reason)
                Inspect the run updates and retry after addressing the failure.
                """,
            timeline: run.timeline,
            stepRecords: run.records,
            workflowMessages: run.workflowMessages
        )
    }

    func userReviewResult(_ run: inout PlanningReviewPrototypeAutomationRun) -> ProcessResult {
        run.records.append(userReviewRecord())
        run.timeline += "\nInteractive user review is waiting."
        return ProcessResult(
            exitCode: 0,
            output: """
                == Planning Review Workflow ==
                Automated review cycles completed for \(run.planPath).
                Interactive user review is waiting.
            """,
            timeline: run.timeline,
            stepRecords: run.records,
            workflowMessages: run.workflowMessages
        )
    }

    func userReviewRecord() -> WorkflowStepRecord {
        WorkflowStepRecord(
            id: "planning-review-interactive-user-review",
            title: "Interactive user review",
            status: .inProgress,
            summary: "Automated cycles completed. Waiting for the user to review the latest plan.",
            sortOrder: 400
        )
    }

    func messagePersistenceFailureRecord(cycle: Int, error: Error) -> WorkflowStepRecord {
        WorkflowStepRecord(
            id: "planning-review-message-persistence-\(cycle)",
            title: "Persist workflow messages cycle \(cycle)",
            status: .failed,
            summary: "Workflow message persistence failed before the workflow could continue.",
            outputPreview: error.localizedDescription,
            sortOrder: 140 + (cycle * 100)
        )
    }

    func isTerminalFailedRecord(_ record: WorkflowStepRecord) -> Bool {
        record.status == .failed && !record.id.hasPrefix("planning-review-reviewer-")
    }

    func publishProgress(
        _ run: PlanningReviewPrototypeAutomationRun,
        progress: WorkflowProgressHandler?
    ) async {
        await progress?(
            WorkflowRunProgress(
                timeline: run.timeline,
                debugLogURL: nil,
                stepRecords: run.records,
                workflowMessages: run.workflowMessages
            )
        )
    }
}
