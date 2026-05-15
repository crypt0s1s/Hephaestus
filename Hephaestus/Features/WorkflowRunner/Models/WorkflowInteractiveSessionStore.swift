import Foundation

@MainActor
final class WorkflowInteractiveSessionStore {
    private var sessionStates: [SessionKey: Any] = [:]
    private var services: [WorkflowDefinition.ID: Any] = [:]

    func setSessionState<State>(
        _ state: State,
        workflowID: WorkflowDefinition.ID,
        sessionID: String
    ) {
        sessionStates[SessionKey(workflowID: workflowID, sessionID: sessionID)] = state
    }

    func sessionState<State>(
        workflowID: WorkflowDefinition.ID,
        sessionID: String,
        as type: State.Type = State.self
    ) -> State? {
        sessionStates[SessionKey(workflowID: workflowID, sessionID: sessionID)] as? State
    }

    func removeSession(workflowID: WorkflowDefinition.ID, sessionID: String) {
        sessionStates.removeValue(forKey: SessionKey(workflowID: workflowID, sessionID: sessionID))
    }

    func removeSessions(workflowID: WorkflowDefinition.ID) {
        sessionStates = sessionStates.filter { $0.key.workflowID != workflowID }
    }

    func removeAllSessions() {
        sessionStates.removeAll()
    }

    func setService<Service>(_ service: Service, workflowID: WorkflowDefinition.ID) {
        services[workflowID] = service
    }

    func service<Service>(
        workflowID: WorkflowDefinition.ID,
        as type: Service.Type = Service.self
    ) -> Service? {
        services[workflowID] as? Service
    }
}

private struct SessionKey: Hashable {
    var workflowID: WorkflowDefinition.ID
    var sessionID: String
}
