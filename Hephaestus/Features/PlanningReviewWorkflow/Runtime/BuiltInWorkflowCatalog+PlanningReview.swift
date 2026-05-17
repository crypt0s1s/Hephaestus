import Foundation

extension BuiltInWorkflowCatalog {
    @MainActor
    static func production(
        processRunner: WorkflowProcessRunning,
        environment: [String: String],
        interactiveSessionStore: WorkflowInteractiveSessionStore,
        planningReviewServices: PlanningReviewServices? = nil
    ) -> BuiltInWorkflowCatalog {
        let coreCatalog = BuiltInWorkflowCatalog.core(processRunner: processRunner)
        let planningReviewServices =
            planningReviewServices
            ?? PlanningReviewServices.production(
                processRunner: processRunner,
                environment: environment
            )
        interactiveSessionStore.setService(
            planningReviewServices,
            workflowID: PlanningReviewWorkflowRunner.id
        )
        return BuiltInWorkflowCatalog(
            workflows: coreCatalog.workflows + [
                planningReviewServices.makeWorkflowRunner(),
            ]
        )
    }
}

extension PlanningReviewServices {
    static func production(
        processRunner: WorkflowProcessRunning,
        environment: [String: String]
    ) -> PlanningReviewServices {
        #if DEBUG
        if environment["HEPHAESTUS_PROVIDER"] == "mock" {
            let artifactStore = PlanningPlanArtifactStore()
            return PlanningReviewServices(
                backendAdapter: UITestHarnessBackendAdapter(),
                planArtifactMaterializer: artifactStore,
                automation: PlanningReviewPrototypeAutomation(
                    agent: UITestPlanningAgentRunner(),
                    artifactStore: artifactStore,
                    reviewCycleCount: 1
                )
            )
        }
        #endif

        return PlanningReviewServices(
            backendAdapter: CodexHarnessBackendAdapter(processRunner: processRunner)
        )
    }
}
