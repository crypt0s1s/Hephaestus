import Foundation

@MainActor
extension WorkflowRunnerModel {
    func planningInteractionState(sessionID: String) -> PlanningInteractionState? {
        guard state.planningInteraction?.sessionID == sessionID else { return nil }
        return state.planningInteraction
    }

    func seedPlanningInteractionState(_ interaction: PlanningInteractionState) {
        update {
            $0.planningInteraction = interaction
        }
    }
}
