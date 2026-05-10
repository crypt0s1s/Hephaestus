import Foundation

@MainActor
struct PlanningInteractionActionProcessor {
  enum Action {
    case changeNote(String)
    case tapAddNote
    case changeDraft(String)
    case tapSubmit
  }

  let model: WorkflowRunnerModel

  func handle(_ action: Action) {
    switch action {
    case .changeNote(let note):
      model.updatePlanningDraftMessage(note)
    case .tapAddNote:
      model.sendPlanningMessage()
    case .changeDraft(let draft):
      model.updatePlanningDraftPlan(draft)
    case .tapSubmit:
      model.submitPlanningDraftPlan()
    }
  }
}
