import Foundation

public struct Agent: Sendable, Hashable {
    public let id: UUID
    public let name: String
    public let profile: AgentProfile

    public init(id: UUID = UUID(), name: String, profile: AgentProfile) {
        self.id = id
        self.name = name
        self.profile = profile
    }
}

public struct AgentProfile: Sendable, Hashable {
    public let id: UUID
    public let name: String
    public let systemPrompt: String
    public let defaultModel: String
    public let contextPolicyID: String

    public init(
        id: UUID = UUID(),
        name: String,
        systemPrompt: String,
        defaultModel: String,
        contextPolicyID: String
    ) {
        self.id = id
        self.name = name
        self.systemPrompt = systemPrompt
        self.defaultModel = defaultModel
        self.contextPolicyID = contextPolicyID
    }
}

public enum RunStatus: Sendable, Hashable {
    case idle
    case running
    case failed
    case cancelled
}

public enum TurnStatus: Sendable, Hashable {
    case accepted
    case preparingContext
    case awaitingProvider
    case streaming
    case succeeded
    case failed
    case cancelled
}

public enum MessageRole: String, Sendable, Hashable, Codable {
    case system
    case user
    case assistant
    case tool
}

public enum MessagePart: Sendable, Hashable, Codable {
    case text(String)

    public var text: String {
        switch self {
        case .text(let value):
            return value
        }
    }
}

public enum MessageSource: Sendable, Hashable, Codable {
    case localUser
    case provider
    case replay
}

public struct RunMessage: Sendable, Hashable, Identifiable, Codable {
    public let id: UUID
    public let role: MessageRole
    public let parts: [MessagePart]
    public let createdAt: Date
    public let source: MessageSource
    public let turnID: UUID?

    public init(
        id: UUID = UUID(),
        role: MessageRole,
        parts: [MessagePart],
        createdAt: Date = Date(),
        source: MessageSource,
        turnID: UUID?
    ) {
        self.id = id
        self.role = role
        self.parts = parts
        self.createdAt = createdAt
        self.source = source
        self.turnID = turnID
    }

    public var text: String {
        parts.map(\.text).joined()
    }
}

public struct Turn: Sendable, Hashable, Identifiable {
    public let id: UUID
    public let runID: UUID
    public var status: TurnStatus
    public let userMessageID: UUID
    public var assistantMessageID: UUID?
    public var providerRequestID: UUID?

    public init(
        id: UUID = UUID(),
        runID: UUID,
        status: TurnStatus,
        userMessageID: UUID,
        assistantMessageID: UUID? = nil,
        providerRequestID: UUID? = nil
    ) {
        self.id = id
        self.runID = runID
        self.status = status
        self.userMessageID = userMessageID
        self.assistantMessageID = assistantMessageID
        self.providerRequestID = providerRequestID
    }
}

public struct RunSnapshot: Sendable, Hashable {
    public let runID: UUID
    public let agent: Agent
    public let status: RunStatus
    public let activeTurn: Turn?
    public let messages: [RunMessage]
}

public struct ContextAssemblyTrace: Sendable, Hashable {
    public let includedMessageIDs: [UUID]
    public let excludedMessageIDs: [UUID]

    public init(includedMessageIDs: [UUID], excludedMessageIDs: [UUID]) {
        self.includedMessageIDs = includedMessageIDs
        self.excludedMessageIDs = excludedMessageIDs
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
                excludedMessageIDs: excluded.map(\.id)
            )
        )
    }
}

public struct ProviderMessage: Sendable, Hashable {
    public let role: MessageRole
    public let text: String

    public init(role: MessageRole, text: String) {
        self.role = role
        self.text = text
    }
}

public struct ProviderRequest: Sendable, Hashable, Identifiable {
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
    case userMessageAppended(EventHeader, UUID)
    case contextPrepared(EventHeader, UUID)
    case providerChunkReceived(EventHeader, UUID)
    case assistantMessageCompleted(EventHeader, UUID)

    public var id: UUID {
        header.id
    }

    public var header: EventHeader {
        switch self {
        case .userMessageAppended(let header, _),
             .contextPrepared(let header, _),
             .providerChunkReceived(let header, _),
             .assistantMessageCompleted(let header, _):
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
    public let id: UUID
    private let agent: Agent
    private let contextManager: ContextManaging
    private let provider: ProviderClient
    private var status: RunStatus = .idle
    private var messages: [RunMessage] = []
    private var turns: [Turn] = []
    private var activeTurn: Turn?
    private var sequence = 0

    public init(
        id: UUID = UUID(),
        agent: Agent,
        contextManager: ContextManaging,
        provider: ProviderClient
    ) {
        self.id = id
        self.agent = agent
        self.contextManager = contextManager
        self.provider = provider
    }

    public func snapshot() -> RunSnapshot {
        RunSnapshot(
            runID: id,
            agent: agent,
            status: status,
            activeTurn: activeTurn,
            messages: messages
        )
    }

    public func submitUserMessage(_ text: String) async throws -> RunMessage {
        guard status == .idle else {
            throw RunFailure.alreadyRunning
        }

        status = .running
        let turnID = UUID()
        let userMessage = RunMessage(
            role: .user,
            parts: [.text(text)],
            source: .localUser,
            turnID: turnID
        )
        var turn = Turn(runID: id, status: .accepted, userMessageID: userMessage.id)
        activeTurn = turn
        turns.append(turn)
        messages.append(userMessage)
        _ = nextEvent(.userMessageAppended, turnID: turnID, messageID: userMessage.id)

        turn.status = .preparingContext
        activeTurn = turn
        let context = try await contextManager.makeContext(
            for: snapshot(),
            newMessage: userMessage,
            profile: agent.profile
        )
        _ = nextEvent(.contextPrepared, turnID: turnID, messageID: userMessage.id)

        let request = ProviderRequest(
            runID: id,
            turnID: turnID,
            model: agent.profile.defaultModel,
            messages: ([ProviderMessage(role: .system, text: context.systemPrompt)] + context.messages.map {
                ProviderMessage(role: $0.role, text: $0.text)
            }),
            stream: true
        )

        turn.status = .streaming
        turn.providerRequestID = request.id
        activeTurn = turn

        var responseText = ""
        for try await chunk in provider.stream(request: request) {
            if case .text(let value) = chunk.delta {
                responseText += value
            }
            _ = nextEvent(.providerChunkReceived, turnID: turnID, messageID: nil)
        }

        let assistantMessage = RunMessage(
            role: .assistant,
            parts: [.text(responseText)],
            source: .provider,
            turnID: turnID
        )
        messages.append(assistantMessage)
        turn.status = .succeeded
        turn.assistantMessageID = assistantMessage.id
        activeTurn = nil
        if let index = turns.firstIndex(where: { $0.id == turn.id }) {
            turns[index] = turn
        }
        status = .idle
        _ = nextEvent(.assistantMessageCompleted, turnID: turnID, messageID: assistantMessage.id)
        return assistantMessage
    }

    private enum EventKind {
        case userMessageAppended
        case contextPrepared
        case providerChunkReceived
        case assistantMessageCompleted
    }

    private func nextEvent(_ kind: EventKind, turnID: UUID, messageID: UUID?) -> RunEvent {
        sequence += 1
        let header = EventHeader(runID: id, turnID: turnID, sequence: sequence)
        switch kind {
        case .userMessageAppended:
            return .userMessageAppended(header, messageID!)
        case .contextPrepared:
            return .contextPrepared(header, messageID!)
        case .providerChunkReceived:
            return .providerChunkReceived(header, messageID ?? UUID())
        case .assistantMessageCompleted:
            return .assistantMessageCompleted(header, messageID!)
        }
    }
}

public enum RunFailure: Error, Equatable {
    case alreadyRunning
}
