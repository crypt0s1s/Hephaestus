import Foundation
import HephaestusDomain

public enum ObservationEventKind: String, Hashable, Codable, Sendable {
    case runCreated
    case turnStarted
    case messageAppended
    case assistantDelta
    case toolCallStarted
    case toolCallCompleted
    case approvalRequested
    case approvalResolved
    case fileChanged
    case contextPrepared
    case providerRequestPrepared
    case error
    case runCompleted
    case turnCancelled
    case unknown
}

public struct ObservationEvent: Hashable, Identifiable, Sendable {
    public var id: UUID
    public var runID: UUID
    public var taskID: TaskID?
    public var turnID: UUID?
    public var sequence: Int
    public var createdAt: Date
    public var kind: ObservationEventKind
    public var summary: String
    public var error: String?

    public init(
        id: UUID,
        runID: UUID,
        taskID: TaskID? = nil,
        turnID: UUID? = nil,
        sequence: Int,
        createdAt: Date,
        kind: ObservationEventKind,
        summary: String,
        error: String? = nil
    ) {
        self.id = id
        self.runID = runID
        self.taskID = taskID
        self.turnID = turnID
        self.sequence = sequence
        self.createdAt = createdAt
        self.kind = kind
        self.summary = summary
        self.error = error
    }
}
