import Foundation

@MainActor
extension WorkflowRunnerModel {
  func applyCompletedPlannerTurn(_ response: String) {
    let plan = PlanningInteractionPrototypePrompts.extractDraftPlan(from: response)
    updateInteraction {
      if let plan {
        $0.draft = plan
        $0.draftProvenance = .agentGenerated
        $0.entries.append(WorkflowInteractionEntry(source: .system, text: Self.generatedDraftNotice))
      }
      $0.phase = .idle
      $0.errorMessage = plan == nil
        ? "Planner response did not include a fenced markdown plan, so the draft was not changed."
        : nil
    }
  }

  private static let generatedDraftNotice =
    "The planner generated a draft. Edit it before submitting so the workflow has a user-reviewed plan."
}
