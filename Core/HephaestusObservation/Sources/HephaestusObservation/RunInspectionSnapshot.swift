import Foundation
import HephaestusDomain

public enum ObservedTurnStatus: String, Hashable, Codable, Sendable {
    case accepted
    case preparingContext
    case awaitingProvider
    case streaming
    case succeeded
    case failed
    case cancelled
    case unknown
}

public struct ObservedTurn: Hashable, Identifiable, Sendable {
    public var id: UUID
    public var runID: UUID
    public var status: ObservedTurnStatus
    public var userMessageID: UUID?
    public var assistantMessageID: UUID?
    public var providerRequestID: UUID?

    public init(
        id: UUID,
        runID: UUID,
        status: ObservedTurnStatus,
        userMessageID: UUID? = nil,
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

public struct ObservedProviderRequest: Hashable, Identifiable, Sendable {
    public var id: UUID
    public var runID: UUID
    public var turnID: UUID
    public var model: String
    public var messageCount: Int
    public var systemPromptIncluded: Bool
    public var stream: Bool
    public var createdAt: Date

    public init(
        id: UUID,
        runID: UUID,
        turnID: UUID,
        model: String,
        messageCount: Int,
        systemPromptIncluded: Bool,
        stream: Bool,
        createdAt: Date
    ) {
        self.id = id
        self.runID = runID
        self.turnID = turnID
        self.model = model
        self.messageCount = messageCount
        self.systemPromptIncluded = systemPromptIncluded
        self.stream = stream
        self.createdAt = createdAt
    }
}

public struct ObservedContextTrace: Hashable, Identifiable, Sendable {
    public var id: UUID
    public var runID: UUID
    public var turnID: UUID
    public var policyID: String
    public var policyName: String
    public var messageLimit: Int?
    public var includedMessageIDs: [UUID]
    public var excludedMessageIDs: [UUID]
    public var createdAt: Date

    public init(
        id: UUID,
        runID: UUID,
        turnID: UUID,
        policyID: String,
        policyName: String,
        messageLimit: Int? = nil,
        includedMessageIDs: [UUID],
        excludedMessageIDs: [UUID],
        createdAt: Date
    ) {
        self.id = id
        self.runID = runID
        self.turnID = turnID
        self.policyID = policyID
        self.policyName = policyName
        self.messageLimit = messageLimit
        self.includedMessageIDs = includedMessageIDs
        self.excludedMessageIDs = excludedMessageIDs
        self.createdAt = createdAt
    }
}

public struct RunInspectionSnapshot: Hashable, Sendable {
    public var runID: UUID
    public var taskID: TaskID?
    public var title: String
    public var events: [ObservationEvent]
    public var turns: [ObservedTurn]
    public var providerRequests: [ObservedProviderRequest]
    public var contextTraces: [ObservedContextTrace]

    public init(
        runID: UUID,
        taskID: TaskID? = nil,
        title: String,
        events: [ObservationEvent],
        turns: [ObservedTurn] = [],
        providerRequests: [ObservedProviderRequest] = [],
        contextTraces: [ObservedContextTrace] = []
    ) {
        self.runID = runID
        self.taskID = taskID
        self.title = title
        self.events = events
        self.turns = turns
        self.providerRequests = providerRequests
        self.contextTraces = contextTraces
    }
}
