import Foundation

struct PlanningReviewServices {
  let backendAdapter: any HarnessBackendAdapter
  let planArtifactMaterializer: any PlanningPlanArtifactMaterializing
  let automation: any PlanningReviewAutomating

  init(
    backendAdapter: any HarnessBackendAdapter,
    planArtifactMaterializer: any PlanningPlanArtifactMaterializing = PlanningPlanArtifactStore(),
    automation: (any PlanningReviewAutomating)? = nil
  ) {
    self.backendAdapter = backendAdapter
    self.planArtifactMaterializer = planArtifactMaterializer
    self.automation = automation ?? PlanningReviewPrototypeAutomation(
      agentStep: CodexAgentStep(backendAdapter: backendAdapter))
  }

  func makeWorkflowRunner() -> PlanningReviewWorkflowRunner {
    PlanningReviewWorkflowRunner(automation: automation)
  }
}
