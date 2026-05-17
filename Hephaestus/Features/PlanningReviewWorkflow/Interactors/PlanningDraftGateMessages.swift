import Foundation

@MainActor
extension WorkflowRunnerModel {
    static func planningDraftGateErrorMessage(for gateState: InteractiveStepGateState) -> String {
        switch gateState {
        case .interacting:
            return "Keep planning with the agent or write a draft manually."
        case .needsOutput(let issue):
            return issue.message
        case .awaitingUserReview:
            return "Review the draft plan before accepting it for review."
        case .accepted:
            return "The draft plan has already been accepted for review."
        }
    }
}
