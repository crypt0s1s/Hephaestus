import Foundation

@MainActor
struct PlanningInteractionActionProcessor {
    enum Action {
        case changeNote(String)
        case tapAddNote
        case changeDraft(String)
        case tapAcceptDraftForReview
        case tapAcceptReviewedWorkflow
        case tapRequestAnotherCycle
        case tapContinuePlanning
        case chooseRecovery(InteractiveStepRecoveryAction)
    }

    let model: WorkflowRunnerModel

    func handle(_ action: Action) {
        switch action {
        case .changeNote(let note):
            model.updatePlanningDraftMessage(note)
        case .tapAddNote:
            Task { await model.sendPlanningMessage() }
        case .changeDraft(let draft):
            model.updatePlanningDraftPlan(draft)
        case .tapAcceptDraftForReview:
            Task { await model.submitPlanningDraftPlan() }
        case .tapAcceptReviewedWorkflow:
            model.acceptPlanningReview()
        case .tapRequestAnotherCycle:
            Task { await model.requestAnotherPlanningReviewCycle() }
        case .tapContinuePlanning:
            model.continuePlanningReview()
        case .chooseRecovery(let recoveryAction):
            model.choosePlanningRecoveryAction(recoveryAction)
        }
    }
}
