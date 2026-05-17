import Foundation

@MainActor
extension WorkflowRunnerModel {
    func acceptPlanningReview() {
        guard let project = state.selectedProject,
            let interaction = currentPlanningInteractionState,
            interaction.canResolveCompletedOutput
        else { return }
        let finalizedOutput = finalizeLatestPlanningOutput(project: project, interaction: interaction)
        guard finalizedOutput.didSucceed else { return }
        applyAcceptedPlanningReview(
            acceptedSummary: finalizedOutput.output?.summary
                ?? interaction.latestResolvedOutput?.summary
                ?? interaction.submittedOutput?.summary
                ?? "Submitted plan",
            finalizedOutput: finalizedOutput.output
        )
    }

    func applyAlreadyAcceptedPlan(
        interaction: PlanningInteractionState,
        output: InteractiveStepOutput
    ) {
        var acceptedInteraction = interaction
        acceptedInteraction.sessionID = UUID().uuidString
        acceptedInteraction.submittedOutput = nil
        acceptedInteraction.relatedOutputs = []
        acceptedInteraction.latestResolvedOutput = nil
        acceptedInteraction.phase = .idle
        acceptedInteraction.updatePlanningDraftCandidate(content: output.artifact.content, source: .user)
        acceptedInteraction.errorMessage =
            """
            This draft was already accepted for review. Edit or accept the reopened draft to start a new \
            review session.
            """
        seedPlanningInteractionState(acceptedInteraction)
        update {
            $0.isRunning = false
            $0.activeWorkflowID = PlanningReviewWorkflowRunner.id
            $0.activeWorkflowActivity = .waitingForInteraction
            $0.interactiveActivity = acceptedInteraction.interactiveActivityProjection
            $0.lastRunWorkflowID = PlanningReviewWorkflowRunner.id
            $0.lastRunSucceeded = nil
            $0.statusMessage = "Draft was already accepted. A new planning session is ready."
        }
    }

    private func finalizeLatestPlanningOutput(
        project: WorkflowProject,
        interaction: PlanningInteractionState
    ) -> FinalizedPlanningOutput {
        let latestOutput = interaction.latestResolvedOutput ?? interaction.submittedOutput
        do {
            let output = try latestOutput.map {
                try planningReviewServices.planArtifactMaterializer.finalizeReviewedPlan(
                    project: project,
                    sessionID: interaction.sessionID,
                    output: $0
                )
            }
            return FinalizedPlanningOutput(output: output, didSucceed: true)
        } catch {
            updateInteraction {
                $0.errorMessage = "Final plan acceptance failed: \(error.localizedDescription)"
            }
            return FinalizedPlanningOutput(output: nil, didSucceed: false)
        }
    }

    private func applyAcceptedPlanningReview(
        acceptedSummary: String,
        finalizedOutput: InteractiveStepOutput?
    ) {
        guard var interaction = currentPlanningInteractionState else { return }
        interaction.phase = .accepted
        if let finalizedOutput {
            interaction.latestResolvedOutput = finalizedOutput
        }
        interaction.entries.append(
            PlanningInteractionEntry(
                source: .system,
                text: "Accepted the submitted plan and completed the workflow."
            )
        )
        seedPlanningInteractionState(interaction)
        update {
            $0.isRunning = false
            $0.activeWorkflowID = nil
            $0.activeWorkflowActivity = nil
            $0.interactiveActivity = interaction.interactiveActivityProjection
            $0.lastRunWorkflowID = PlanningReviewWorkflowRunner.id
            $0.lastRunSucceeded = true
            $0.statusMessage = "Planning review workflow accepted."
            $0.timelineOutput += "\nPlanning review workflow accepted."
            $0.output = """
                == Planning Review Workflow ==
                Planning review workflow accepted.
                Latest accepted plan: \(acceptedSummary)
                """
            $0.stepRecords = $0.stepRecords.map {
                Self.acceptedPlanningReviewRecord($0, finalizedOutput: finalizedOutput)
            }
        }
    }

    private static func acceptedPlanningReviewRecord(
        _ record: WorkflowStepRecord,
        finalizedOutput: InteractiveStepOutput?
    )
        -> WorkflowStepRecord {
        guard record.id == "planning-review-interactive-user-review" else { return record }
        var acceptedRecord = record
        acceptedRecord.status = .succeeded
        acceptedRecord.summary = "User accepted the reviewed plan."
        if let finalizedOutput {
            acceptedRecord.artifactReferences = [.init(output: finalizedOutput, title: "Final accepted plan")]
        }
        return acceptedRecord
    }
}

private struct FinalizedPlanningOutput {
    let output: InteractiveStepOutput?
    let didSucceed: Bool
}
