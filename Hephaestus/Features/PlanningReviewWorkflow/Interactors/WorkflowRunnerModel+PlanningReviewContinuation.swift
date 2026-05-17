import Foundation

@MainActor
extension WorkflowRunnerModel {
    func latestPlanningReviewPlanContent(for interaction: WorkflowInteractionState) -> String? {
        let latestPlanMessage =
            interaction.workflowMessages.last { $0.kind == .currentPlan }
            ?? interaction.workflowMessages.first { $0.kind == .submittedPlan }
        return latestPlanMessage?.planContent ?? interaction.submittedOutput?.artifact.content
    }

    func planningReviewFeedbackHistory(from messages: [WorkflowMessage]) -> String {
        let consolidatedReviews = messages.compactMap(\.consolidatedReview)
        guard !consolidatedReviews.isEmpty else {
            return "No automated feedback messages were recorded."
        }
        let responsesByCycle = Dictionary(grouping: messages.compactMap(\.plannerResponse)) {
            $0.cycle
        }
        return consolidatedReviews
            .map { review in
                planningReviewFeedbackHistorySection(
                    review: review,
                    plannerResponse: responsesByCycle[review.cycle]?.last
                )
            }
            .joined(separator: "\n\n")
    }

    func planningReviewFeedbackHistorySection(
        review: ConsolidatedReviewMessagePayload,
        plannerResponse: PlannerResponseMessagePayload?
    ) -> String {
        """
        Cycle \(review.cycle)
        Review feedback:
        \(review.feedback)

        Failed reviewers:
        \(planningReviewFailedReviewerSummary(from: review.failedReviewers))

        Planner response:
        \(plannerResponse?.response ?? "No planner response was recorded.")
        """
    }

    func planningReviewFailedReviewerSummary(
        from failedReviewers: [FailedReviewerMessagePayload]
    ) -> String {
        guard !failedReviewers.isEmpty else { return "None" }
        return failedReviewers.map {
            "- \($0.reviewerName) (\($0.stepID), exit \($0.exitCode)): \($0.details)"
        }
        .joined(separator: "\n")
    }

    func planningReviewContinuationRecords(
        from records: [WorkflowStepRecord],
        feedbackHistory: String
    ) -> [WorkflowStepRecord] {
        var continuedRecords = records.map { record in
            planningReviewContinuedRecord(from: record, feedbackHistory: feedbackHistory)
        }
        guard !continuedRecords.contains(where: { $0.id == "planning-review-interactive-planning-continued" })
        else { return continuedRecords }
        continuedRecords.append(planningReviewResumedRecord(after: continuedRecords))
        return continuedRecords
    }

    func planningReviewContinuedRecord(
        from record: WorkflowStepRecord,
        feedbackHistory: String
    ) -> WorkflowStepRecord {
        guard record.id == "planning-review-interactive-user-review" else { return record }
        var updatedRecord = record
        updatedRecord.status = .needsFix
        updatedRecord.summary = "User continued planning with the latest plan and feedback history."
        updatedRecord.outputPreview = feedbackHistory
        return updatedRecord
    }

    func planningReviewResumedRecord(after records: [WorkflowStepRecord]) -> WorkflowStepRecord {
        WorkflowStepRecord(
            id: "planning-review-interactive-planning-continued",
            title: "Interactive planning resumed",
            status: .inProgress,
            summary: "Latest plan and review history are available for continued planning.",
            sortOrder: (records.map(\.sortOrder).max() ?? 400) + 10
        )
    }

    func reopenPlanningInteraction(
        _ interaction: inout WorkflowInteractionState,
        latestPlan: String?,
        feedbackHistory: String
    ) {
        if let latestPlan, interaction.draft != latestPlan {
            interaction.draft = latestPlan
            interaction.draftProvenance = .agentGenerated
        } else {
            interaction.draftProvenance = interaction.trimmedDraft.isEmpty ? .empty : .userEdited
        }
        interaction.submittedOutput = nil
        interaction.phase = .idle
        interaction.runtimeRun.status = .paused
        interaction.runtimeRun.activePause = Self.makeInteractiveInputPause(
            runID: interaction.runtimeRun.id,
            stepID: interaction.stepID
        )
        interaction.runtimeRun.updatedAt = Date()
        interaction.errorMessage = nil
        interaction.entries.append(continuedPlanningEntry(feedbackHistory: feedbackHistory))
    }

    func continuedPlanningEntry(feedbackHistory: String) -> WorkflowInteractionEntry {
        WorkflowInteractionEntry(
            source: .system,
            text: """
                Reopened planning with the latest plan in the draft editor.

                Feedback history:
                \(feedbackHistory)
                """
        )
    }

    func continuedPlanningStatusMessage(project: WorkflowProject) -> String {
        "Planning reopened for \(project.name). Edit the latest draft before submitting it again."
    }
}
