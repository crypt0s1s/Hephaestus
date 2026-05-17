import Foundation

struct PlanningReviewServices {
    let backendAdapter: any HarnessBackendAdapter
    let interactionBackend: any PlanningInteractionBackendRunning
    let planArtifactMaterializer: any PlanningPlanArtifactMaterializing
    let messageStore: any PlanningReviewMessagePersisting
    let automation: any PlanningReviewAutomating

    init(
        backendAdapter: any HarnessBackendAdapter,
        interactionBackend: (any PlanningInteractionBackendRunning)? = nil,
        planArtifactMaterializer: any PlanningPlanArtifactMaterializing = PlanningPlanArtifactStore(),
        messageStore: any PlanningReviewMessagePersisting = PlanningReviewMessageStore(),
        automation: (any PlanningReviewAutomating)? = nil
    ) {
        self.backendAdapter = backendAdapter
        self.interactionBackend = interactionBackend ?? PlanningInteractionBackend(backendAdapter: backendAdapter)
        self.planArtifactMaterializer = planArtifactMaterializer
        self.messageStore = messageStore
        self.automation =
            automation
            ?? PlanningReviewPrototypeAutomation(
                agent: CodexPlanningAgentRunner(backendAdapter: backendAdapter),
                artifactStore: planArtifactMaterializer)
    }

    func makeWorkflowRunner() -> PlanningReviewWorkflowRunner {
        PlanningReviewWorkflowRunner(automation: automation)
    }
}
