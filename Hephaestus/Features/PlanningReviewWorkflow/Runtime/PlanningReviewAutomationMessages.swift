import Foundation

extension PlanningReviewPrototypeAutomation {
    func runReviewer(
        name: String,
        cycle: Int,
        project: WorkflowProject,
        currentPlanMessage: WorkflowMessage,
        planPath: String
    ) async -> PlanningReviewerRun {
        let prompt = reviewerPrompt(
            name: name,
            project: project,
            currentPlanMessage: currentPlanMessage,
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
        return PlanningReviewerRun(
            name: name,
            stepID: reviewerStepID(cycle: cycle, offset: Self.reviewers.firstIndex(of: name) ?? 0),
            prompt: prompt,
            result: result
        )
    }

    func reviewRecords(
        from results: [PlanningReviewerRun],
        cycle: Int
    ) -> [WorkflowStepRecord] {
        results.enumerated().map { offset, result in
            WorkflowStepRecord(
                id: reviewerStepID(cycle: cycle, offset: offset),
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

    func reviewMessages(
        from results: [PlanningReviewerRun],
        cycle: Int,
        currentPlanMessage: WorkflowMessage
    ) -> [WorkflowMessage] {
        results.enumerated().compactMap { offset, result in
            guard result.result.exitCode == 0 else { return nil }
            return WorkflowMessage(
                runID: currentPlanMessage.runID,
                kind: .reviewerFeedback,
                producerStepID: reviewerStepID(cycle: cycle, offset: offset),
                payload: .reviewerFeedback(
                    ReviewerFeedbackMessagePayload(
                        reviewedMessageID: currentPlanMessage.id,
                        cycle: cycle,
                        reviewerName: result.name,
                        feedback: result.result.output,
                        exitCode: result.result.exitCode
                    )
                ),
                summary: "\(result.name) feedback for review cycle \(cycle)."
            )
        }
    }

    func consolidatedReviewMessage(
        cycle: Int,
        currentPlanMessage: WorkflowMessage,
        reviewerRuns: [PlanningReviewerRun],
        reviewerMessages: [WorkflowMessage]
    ) -> WorkflowMessage {
        WorkflowMessage(
            runID: currentPlanMessage.runID,
            kind: .consolidatedReview,
            producerStepID: "planning-review-consolidated-review-\(cycle)",
            payload: .consolidatedReview(
                ConsolidatedReviewMessagePayload(
                    reviewedMessageID: currentPlanMessage.id,
                    cycle: cycle,
                    reviewerMessageIDs: reviewerMessages.map(\.id),
                    failedReviewers: failedReviewerStates(from: reviewerRuns),
                    feedback: reviewFeedback(from: reviewerMessages)
                )
            ),
            summary: "Consolidated review feedback for cycle \(cycle)."
        )
    }

    func failedReviewerStates(from results: [PlanningReviewerRun]) -> [FailedReviewerMessagePayload] {
        results.compactMap { result in
            guard result.result.exitCode != 0 else { return nil }
            return FailedReviewerMessagePayload(
                reviewerName: result.name,
                stepID: result.stepID,
                exitCode: result.result.exitCode,
                details: result.result.output
            )
        }
    }

    func reviewerStepID(cycle: Int, offset: Int) -> String {
        "planning-review-reviewer-\(cycle)-\(offset + 1)"
    }

    func reviewFeedback(from messages: [WorkflowMessage]) -> String {
        messages.compactMap { message in
            guard case .reviewerFeedback(let payload) = message.payload else { return nil }
            return "\(payload.reviewerName):\n\(payload.feedback)"
        }
        .joined(separator: "\n\n")
    }

    func reviewerPrompt(
        name: String,
        project: WorkflowProject,
        currentPlanMessage: WorkflowMessage,
        planPath: String
    ) -> String {
        return """
        You are \(name), a review-only planning agent.

        Review the current implementation plan. Do not edit files.

        Project path: \(project.path)
        Plan artifact path: \(planPath)
        Current plan message ID: \(currentPlanMessage.id)

        Plan content:
        \(currentPlanMessage.planContent ?? "")

        Return at most 5 findings with severity P1, P2, or P3. Return exactly "pass" if the plan is
        clear, scoped, and testable.
        """
    }

    func plannerResponsePrompt(
        project: WorkflowProject,
        currentPlanMessage: WorkflowMessage,
        reviewMessage: WorkflowMessage
    ) -> String {
        let review = reviewMessage.consolidatedReview
        return """
        You are the planner agent responding to automated review feedback.

        Do not edit files. Explain how the plan should change, then provide a revised markdown plan.

        Project path: \(project.path)
        Current plan message ID: \(currentPlanMessage.id)
        Consolidated review message ID: \(reviewMessage.id)

        Current plan:
        \(currentPlanMessage.planContent ?? "")

        Review feedback:
        \(review?.feedback ?? "")

        Failed reviewers:
        \(failedReviewerFeedback(from: review?.failedReviewers ?? []))
        """
    }

    func failedReviewerFeedback(from failedReviewers: [FailedReviewerMessagePayload]) -> String {
        guard !failedReviewers.isEmpty else { return "None" }
        return failedReviewers.map {
            """
            \($0.reviewerName) (\($0.stepID)) failed with exit code \($0.exitCode):
            \($0.details)
            """
        }
        .joined(separator: "\n\n")
    }

    func makeCurrentPlanMessage(
        from responseMessage: WorkflowMessage,
        previousPlanMessage: WorkflowMessage,
        cycle: Int,
        recordID: String
    ) -> WorkflowMessage? {
        guard case .plannerResponse(let response) = responseMessage.payload,
            response.exitCode == 0
        else { return nil }
        return WorkflowMessage(
            runID: responseMessage.runID,
            kind: .currentPlan,
            producerStepID: recordID,
            payload: .currentPlan(
                CurrentPlanMessagePayload(
                    sourceMessageID: responseMessage.id,
                    cycle: cycle,
                    contentType: "text/markdown; artifact=plan",
                    content: response.response,
                    projectRelativePath: previousPlanMessage.planProjectRelativePath
                )
            ),
            summary: "Current revised plan after planner response cycle \(cycle)."
        )
    }
}
