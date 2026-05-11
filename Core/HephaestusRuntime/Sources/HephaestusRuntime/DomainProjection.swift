import Foundation
import HephaestusDomain
import HephaestusKernel
import HephaestusObservation

extension AgentTask {
    public init(
        sessionSummary: PersistedSessionSummary,
        projectID: ProjectID = DefaultProject.id,
        status: TaskStatus = .completed
    ) {
        self.init(
            id: TaskID(rawValue: sessionSummary.id),
            projectID: projectID,
            title: sessionSummary.title,
            status: status,
            createdAt: sessionSummary.createdAt,
            updatedAt: sessionSummary.updatedAt,
            activeRunID: sessionSummary.id
        )
    }

    public init(
        session: PersistedSession,
        projectID: ProjectID = DefaultProject.id
    ) {
        self.init(
            id: TaskID(rawValue: session.id),
            projectID: projectID,
            title: session.title,
            status: TaskStatus(session: session),
            createdAt: session.createdAt,
            updatedAt: session.updatedAt,
            activeRunID: session.id
        )
    }
}

extension TaskStatus {
    public init(session: PersistedSession) {
        guard let status = session.turns.last?.status else {
            self = session.messages.isEmpty ? .draft : .completed
            return
        }

        switch status {
        case .accepted, .preparingContext, .awaitingProvider, .streaming:
            self = .running
        case .succeeded:
            self = .completed
        case .failed:
            self = .failed
        case .cancelled:
            self = .cancelled
        }
    }
}

extension RunInspectionSnapshot {
    public init(inspection: PersistedRunInspection, taskID: TaskID? = nil) {
        let session = inspection.session
        let resolvedTaskID = taskID ?? TaskID(rawValue: session.id)
        self.init(
            runID: session.id,
            taskID: resolvedTaskID,
            title: session.title,
            events: inspection.orderedEvents.map {
                ObservationEvent(event: $0, taskID: resolvedTaskID)
            },
            turns: session.turns.map(ObservedTurn.init(turn:)),
            providerRequests: session.providerRequests.map(ObservedProviderRequest.init(request:)),
            contextTraces: session.contextTraces.map(ObservedContextTrace.init(trace:))
        )
    }
}

extension ObservationEvent {
    public init(event: PersistedRuntimeEvent, taskID: TaskID? = nil) {
        self.init(
            id: event.id,
            runID: event.runID,
            taskID: taskID,
            turnID: event.turnID,
            sequence: event.sequence,
            createdAt: event.createdAt,
            kind: ObservationEventKind(event.kind),
            summary: event.summary,
            error: event.error
        )
    }
}

extension ObservationEventKind {
    public init(_ kind: PersistedRuntimeEvent.Kind) {
        switch kind {
        case .runCreated:
            self = .runCreated
        case .userMessageAccepted:
            self = .messageAppended
        case .contextPrepared:
            self = .contextPrepared
        case .providerRequestPrepared:
            self = .providerRequestPrepared
        case .assistantTextDelta:
            self = .assistantDelta
        case .assistantMessageCompleted:
            self = .runCompleted
        case .turnCancelled:
            self = .turnCancelled
        case .turnFailed:
            self = .error
        }
    }
}

extension ObservedTurn {
    public init(turn: Turn) {
        self.init(
            id: turn.id,
            runID: turn.runID,
            status: ObservedTurnStatus(turn.status),
            userMessageID: turn.userMessageID,
            assistantMessageID: turn.assistantMessageID,
            providerRequestID: turn.providerRequestID
        )
    }
}

extension ObservedTurnStatus {
    public init(_ status: TurnStatus) {
        switch status {
        case .accepted:
            self = .accepted
        case .preparingContext:
            self = .preparingContext
        case .awaitingProvider:
            self = .awaitingProvider
        case .streaming:
            self = .streaming
        case .succeeded:
            self = .succeeded
        case .failed:
            self = .failed
        case .cancelled:
            self = .cancelled
        }
    }
}

extension ObservedProviderRequest {
    public init(request: PersistedProviderRequestSummary) {
        self.init(
            id: request.id,
            runID: request.runID,
            turnID: request.turnID,
            model: request.model,
            messageCount: request.messageCount,
            systemPromptIncluded: request.systemPromptIncluded,
            stream: request.stream,
            createdAt: request.createdAt
        )
    }
}

extension ObservedContextTrace {
    public init(trace: PersistedContextTrace) {
        self.init(
            id: trace.id,
            runID: trace.runID,
            turnID: trace.turnID,
            policyID: trace.policyID,
            policyName: trace.policyName,
            messageLimit: trace.messageLimit,
            includedMessageIDs: trace.includedMessageIDs,
            excludedMessageIDs: trace.excludedMessageIDs,
            createdAt: trace.createdAt
        )
    }
}
