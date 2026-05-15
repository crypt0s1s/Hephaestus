import Foundation

@MainActor
extension WorkflowRunnerModel {
    var planningReviewServices: PlanningReviewServices {
        guard let services = interactiveSessionStore.service(
            workflowID: PlanningReviewWorkflowRunner.id,
            as: PlanningReviewServices.self
        ) else {
            preconditionFailure("Planning review services are not registered.")
        }
        return services
    }

    var currentPlanningInteractionState: PlanningInteractionState? {
        guard let activity = state.interactiveActivity,
            activity.workflowID == PlanningReviewWorkflowRunner.id
        else { return nil }
        return planningInteractionState(sessionID: activity.sessionID)
    }

    func planningInteractionState(sessionID: String) -> PlanningInteractionState? {
        interactiveSessionStore.planningInteractionState(sessionID: sessionID)
    }

    func seedPlanningInteractionState(_ interaction: PlanningInteractionState) {
        interactiveSessionStore.setPlanningInteractionState(interaction)
        update {
            $0.interactiveActivity = interaction.interactiveActivityProjection
        }
    }

    func clearPlanningInteractionSessions() {
        interactiveSessionStore.removeSessions(workflowID: PlanningReviewWorkflowRunner.id)
    }
}

@MainActor
extension WorkflowInteractiveSessionStore {
    func setPlanningInteractionState(_ interaction: PlanningInteractionState) {
        setSessionState(
            interaction,
            workflowID: PlanningReviewWorkflowRunner.id,
            sessionID: interaction.sessionID
        )
    }

    func planningInteractionState(sessionID: String) -> PlanningInteractionState? {
        sessionState(
            workflowID: PlanningReviewWorkflowRunner.id,
            sessionID: sessionID,
            as: PlanningInteractionState.self
        )
    }
}
