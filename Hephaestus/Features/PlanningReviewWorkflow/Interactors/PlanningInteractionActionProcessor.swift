import Foundation

@MainActor
struct PlanningInteractionActionProcessor {
    enum Action {
        case changeNote(String)
        case tapAddNote
        case changeDraft(String)
        case tapSubmit
        case tapAcceptPlan
        case tapRequestAnotherCycle
        case tapContinuePlanning
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
        case .tapSubmit:
            Task { await model.submitPlanningDraftPlan() }
        case .tapAcceptPlan:
            model.acceptPlanningReview()
        case .tapRequestAnotherCycle:
            Task { await model.requestAnotherPlanningReviewCycle() }
        case .tapContinuePlanning:
            model.continuePlanningReview()
        }
    }
}
