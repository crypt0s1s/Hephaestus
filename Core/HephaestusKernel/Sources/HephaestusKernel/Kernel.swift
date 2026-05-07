import Foundation

public struct RunSnapshot: Sendable, Hashable {
    public let runID: UUID
    public let agent: Agent
    public let status: RunStatus
    public let activeTurn: Turn?
    public let messages: [RunMessage]
    public let turns: [Turn]

    public init(
        runID: UUID,
        agent: Agent,
        status: RunStatus,
        activeTurn: Turn?,
        messages: [RunMessage],
        turns: [Turn]
    ) {
        self.runID = runID
        self.agent = agent
        self.status = status
        self.activeTurn = activeTurn
        self.messages = messages
        self.turns = turns
    }
}

public struct ContextAssemblyTrace: Sendable, Hashable, Codable {
    public let includedMessageIDs: [UUID]
    public let excludedMessageIDs: [UUID]
    public let messageLimit: Int?

    public init(includedMessageIDs: [UUID], excludedMessageIDs: [UUID], messageLimit: Int? = nil) {
        self.includedMessageIDs = includedMessageIDs
        self.excludedMessageIDs = excludedMessageIDs
        self.messageLimit = messageLimit
    }
}

public struct ContextPackage: Sendable, Hashable {
    public let systemPrompt: String
    public let messages: [RunMessage]
    public let currentUserMessageID: UUID
    public let trace: ContextAssemblyTrace
}

public protocol ContextManaging: Sendable {
    func makeContext(
        for snapshot: RunSnapshot,
        newMessage: RunMessage,
        profile: AgentProfile
    ) async throws -> ContextPackage
}

public struct RecentContextManager: ContextManaging {
    public let messageLimit: Int

    public init(messageLimit: Int = 20) {
        self.messageLimit = messageLimit
    }

    public func makeContext(
        for snapshot: RunSnapshot,
        newMessage: RunMessage,
        profile: AgentProfile
    ) async throws -> ContextPackage {
        var candidates = snapshot.messages.filter { $0.role != .system }
        if !candidates.contains(where: { $0.id == newMessage.id }) {
            candidates.append(newMessage)
        }

        let selected = Array(candidates.suffix(messageLimit))
        let selectedIDs = Set(selected.map(\.id))
        let excluded = candidates.filter { !selectedIDs.contains($0.id) }

        return ContextPackage(
            systemPrompt: profile.systemPrompt,
            messages: selected,
            currentUserMessageID: newMessage.id,
            trace: ContextAssemblyTrace(
                includedMessageIDs: selected.map(\.id),
                excludedMessageIDs: excluded.map(\.id),
                messageLimit: messageLimit
            )
        )
    }
}

public struct ProviderMessage: Sendable, Hashable, Codable {
    public let role: MessageRole
    public let text: String

    public init(role: MessageRole, text: String) {
        self.role = role
        self.text = text
    }
}

public struct ProviderRequest: Sendable, Hashable, Identifiable, Codable {
    public let id: UUID
    public let runID: UUID
    public let turnID: UUID
    public let model: String
    public let messages: [ProviderMessage]
    public let stream: Bool

    public init(
        id: UUID = UUID(),
        runID: UUID,
        turnID: UUID,
        model: String,
        messages: [ProviderMessage],
        stream: Bool
    ) {
        self.id = id
        self.runID = runID
        self.turnID = turnID
        self.model = model
        self.messages = messages
        self.stream = stream
    }
}

public enum ProviderDelta: Sendable, Hashable {
    case text(String)
}

public enum ProviderFinishReason: Sendable, Hashable {
    case stop
    case length
    case cancelled
    case error
}

public struct ProviderResponseChunk: Sendable, Hashable {
    public let providerRequestID: UUID
    public let delta: ProviderDelta
    public let finishReason: ProviderFinishReason?

    public init(providerRequestID: UUID, delta: ProviderDelta, finishReason: ProviderFinishReason?) {
        self.providerRequestID = providerRequestID
        self.delta = delta
        self.finishReason = finishReason
    }
}

public protocol ProviderClient: Sendable {
    func stream(request: ProviderRequest) -> AsyncThrowingStream<ProviderResponseChunk, Error>
}

public enum RunEvent: Sendable, Hashable, Identifiable {
    case userMessageAccepted(EventHeader, RunMessage)
    case contextPrepared(EventHeader, ContextAssemblyTrace)
    case providerRequestPrepared(EventHeader, ProviderRequest)
    case providerChunkReceived(EventHeader, UUID, String)
    case assistantMessageCompleted(EventHeader, RunMessage)
    case turnCancelled(EventHeader)
    case turnFailed(EventHeader, String)

    public var id: UUID { header.id }

    public var header: EventHeader {
        switch self {
        case .userMessageAccepted(let header, _),
             .contextPrepared(let header, _),
             .providerRequestPrepared(let header, _),
             .providerChunkReceived(let header, _, _),
             .assistantMessageCompleted(let header, _),
             .turnCancelled(let header),
             .turnFailed(let header, _):
            return header
        }
    }
}

public struct EventHeader: Sendable, Hashable, Identifiable {
    public let id: UUID
    public let runID: UUID
    public let turnID: UUID?
    public let sequence: Int
    public let createdAt: Date

    public init(id: UUID = UUID(), runID: UUID, turnID: UUID?, sequence: Int, createdAt: Date = Date()) {
        self.id = id
        self.runID = runID
        self.turnID = turnID
        self.sequence = sequence
        self.createdAt = createdAt
    }
}

public actor Run {
    public nonisolated let id: UUID
    private let agent: Agent
    private let contextManager: ContextManaging
    private let provider: ProviderClient
    private var status: RunStatus = .idle
    private var messages: [RunMessage] = []
    private var turns: [Turn] = []
    private var activeTurn: Turn?
    var sequence = 0

    public init(
        id: UUID = UUID(),
        agent: Agent,
        contextManager: ContextManaging,
        provider: ProviderClient,
        initialMessages: [RunMessage] = [],
        initialTurns: [Turn] = [],
        initialSequence: Int = 0
    ) {
        self.id = id
        self.agent = agent
        self.contextManager = contextManager
        self.provider = provider
        self.messages = initialMessages
        self.turns = initialTurns
        self.sequence = initialSequence
    }

    public func snapshot() -> RunSnapshot {
        RunSnapshot(
            runID: id,
            agent: agent,
            status: status,
            activeTurn: activeTurn,
            messages: messages,
            turns: turns
        )
    }

    public func streamUserMessage(_ text: String) -> AsyncThrowingStream<RunEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                await executeUserMessage(text, continuation: continuation)
            }
            continuation.onTermination = { @Sendable _ in
                task.cancel()
            }
        }
    }

    private func executeUserMessage(
        _ text: String,
        continuation: AsyncThrowingStream<RunEvent, Error>.Continuation
    ) async {
        guard status == .idle else {
            continuation.finish(throwing: RunFailure.alreadyRunning)
            return
        }

        let userMessage = beginTurn(text: text)
        let turnID = userMessage.turnID ?? UUID()
        var turn = activeTurn ?? Turn(id: turnID, runID: id, status: .accepted, userMessageID: userMessage.id)
        continuation.yield(nextEvent(.userMessageAccepted(userMessage), turnID: turnID))

        do {
            try Task.checkCancellation()
            updateTurn(&turn) { $0.status = .preparingContext }
            let context = try await contextManager.makeContext(
                for: snapshot(),
                newMessage: userMessage,
                profile: agent.profile
            )
            continuation.yield(nextEvent(.contextPrepared(context.trace), turnID: turnID))

            let request = makeProviderRequest(context: context, turnID: turnID)
            updateTurn(&turn) {
                $0.status = .streaming
                $0.providerRequestID = request.id
            }
            continuation.yield(nextEvent(.providerRequestPrepared(request), turnID: turnID))

            let responseText = try await streamProviderResponse(
                request: request,
                turnID: turnID,
                continuation: continuation
            )

            let assistantMessage = completeTurn(&turn, responseText: responseText, turnID: turnID)
            continuation.yield(nextEvent(.assistantMessageCompleted(assistantMessage), turnID: turnID))
            continuation.finish()
        } catch is CancellationError {
            finishTurn(&turn, status: .cancelled)
            continuation.yield(nextEvent(.turnCancelled, turnID: turnID))
            continuation.finish(throwing: CancellationError())
        } catch {
            finishTurn(&turn, status: .failed)
            continuation.yield(nextEvent(.turnFailed(String(describing: error)), turnID: turnID))
            continuation.finish(throwing: error)
        }
    }

    private func beginTurn(text: String) -> RunMessage {
        status = .running
        let turnID = UUID()
        let userMessage = RunMessage(
            role: .user,
            parts: [.text(text)],
            source: .localUser,
            turnID: turnID
        )
        let turn = Turn(id: turnID, runID: id, status: .accepted, userMessageID: userMessage.id)
        activeTurn = turn
        turns.append(turn)
        messages.append(userMessage)
        return userMessage
    }

    private func makeProviderRequest(context: ContextPackage, turnID: UUID) -> ProviderRequest {
        ProviderRequest(
            runID: id,
            turnID: turnID,
            model: agent.profile.defaultModel,
            messages: [ProviderMessage(role: .system, text: context.systemPrompt)] + context.messages.map {
                ProviderMessage(role: $0.role, text: $0.text)
            },
            stream: true
        )
    }

    private func streamProviderResponse(
        request: ProviderRequest,
        turnID: UUID,
        continuation: AsyncThrowingStream<RunEvent, Error>.Continuation
    ) async throws -> String {
        var responseText = ""
        for try await chunk in provider.stream(request: request) {
            try Task.checkCancellation()
            if case .text(let value) = chunk.delta {
                responseText += value
                continuation.yield(nextEvent(.providerChunkReceived(request.id, value), turnID: turnID))
            }
        }
        return responseText
    }

    private func completeTurn(_ turn: inout Turn, responseText: String, turnID: UUID) -> RunMessage {
        let assistantMessage = RunMessage(
            role: .assistant,
            parts: [.text(responseText)],
            source: .provider,
            turnID: turnID
        )
        messages.append(assistantMessage)
        turn.assistantMessageID = assistantMessage.id
        finishTurn(&turn, status: .succeeded)
        return assistantMessage
    }

    private func updateTurn(_ turn: inout Turn, update: (inout Turn) -> Void) {
        update(&turn)
        activeTurn = turn
        if let index = turns.firstIndex(where: { $0.id == turn.id }) {
            turns[index] = turn
        }
    }

    private func finishTurn(_ turn: inout Turn, status turnStatus: TurnStatus) {
        turn.status = turnStatus
        activeTurn = nil
        if let index = turns.firstIndex(where: { $0.id == turn.id }) {
            turns[index] = turn
        }
        status = .idle
    }

}
