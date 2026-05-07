import Foundation

public struct Agent: Sendable, Hashable, Codable {
    public let id: UUID
    public let name: String
    public let profile: AgentProfile

    public init(id: UUID = UUID(), name: String, profile: AgentProfile) {
        self.id = id
        self.name = name
        self.profile = profile
    }
}

public struct AgentProfile: Sendable, Hashable, Codable {
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

public enum RunStatus: Sendable, Hashable, Codable {
    case idle
    case running
    case failed
    case cancelled
}

public enum TurnStatus: Sendable, Hashable, Codable {
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

public struct Turn: Sendable, Hashable, Identifiable, Codable {
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
