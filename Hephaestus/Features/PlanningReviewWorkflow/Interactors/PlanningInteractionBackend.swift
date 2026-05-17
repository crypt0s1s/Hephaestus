import Foundation

protocol PlanningInteractionBackendRunning {
    func session(
        for interaction: PlanningInteractionState,
        project: WorkflowProject
    ) async throws -> BackendSession

    func startPlannerTurn(
        note: String,
        session: BackendSession
    ) async throws -> AsyncThrowingStream<BackendEvent, Error>
}

struct PlanningInteractionBackend: PlanningInteractionBackendRunning {
    let backendAdapter: any HarnessBackendAdapter

    func session(
        for interaction: PlanningInteractionState,
        project: WorkflowProject
    ) async throws -> BackendSession {
        if let session = interaction.backendSession {
            return try await backendAdapter.resumeSession(ResumeSessionRequest(session: session))
        }
        return try await backendAdapter.startSession(
            StartSessionRequest(project: project, title: "Planning Review")
        )
    }

    func startPlannerTurn(
        note: String,
        session: BackendSession
    ) async throws -> AsyncThrowingStream<BackendEvent, Error> {
        try await backendAdapter.startTurn(
            StartTurnRequest(
                session: session,
                prompt: PlanningInteractionPrototypePrompts.plannerPrompt(for: note),
                timeoutSeconds: 180,
                sandboxMode: "read-only"
            )
        )
    }
}
