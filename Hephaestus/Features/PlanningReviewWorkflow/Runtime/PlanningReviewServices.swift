import Foundation

struct PlanningReviewServices {
    let backendAdapter: any HarnessBackendAdapter
    let planArtifactMaterializer: any PlanningPlanArtifactMaterializing
    let messageStore: any PlanningReviewMessagePersisting
    let automation: any PlanningReviewAutomating

    init(
        backendAdapter: any HarnessBackendAdapter,
        planArtifactMaterializer: any PlanningPlanArtifactMaterializing = PlanningPlanArtifactStore(),
        messageStore: any PlanningReviewMessagePersisting = PlanningReviewMessageStore(),
        automation: (any PlanningReviewAutomating)? = nil
    ) {
        self.backendAdapter = backendAdapter
        self.planArtifactMaterializer = planArtifactMaterializer
        self.messageStore = messageStore
        self.automation =
            automation
            ?? PlanningReviewPrototypeAutomation(
                agentStep: CodexAgentStep(backendAdapter: backendAdapter))
    }

    func makeWorkflowRunner() -> PlanningReviewWorkflowRunner {
        PlanningReviewWorkflowRunner(automation: automation)
    }
}
