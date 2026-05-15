import Foundation

@MainActor
extension WorkflowRunnerModel {
    func choosePlanningRecoveryAction(_ action: InteractiveStepRecoveryAction) {
        switch action {
        case .requestAgentRevision:
            updateInteraction {
                let issueMessage = Self.planningDraftGateErrorMessage(for: $0.gateState)
                $0.note = """
                    Please produce a reviewable draft plan that resolves this issue:
                    \(issueMessage)
                    """
                $0.errorMessage = nil
            }
        case .editOutput, .pasteOutput:
            updateInteraction {
                $0.errorMessage = "Edit or paste the draft plan in the editor, then accept it for review."
            }
        }
    }
}
