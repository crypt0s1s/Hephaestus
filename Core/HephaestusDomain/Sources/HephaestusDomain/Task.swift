import Foundation

public struct TaskID: Hashable, Codable, Sendable, CustomStringConvertible {
    public var rawValue: UUID

    public init(rawValue: UUID) {
        self.rawValue = rawValue
    }

    public var description: String {
        rawValue.uuidString
    }
}

public enum TaskStatus: String, Hashable, Codable, Sendable {
    case draft
    case running
    case waitingForInput
    case completed
    case failed
    case cancelled
}

public struct AgentTask: Hashable, Codable, Identifiable, Sendable {
    public var id: TaskID
    public var projectID: ProjectID
    public var title: String
    public var status: TaskStatus
    public var createdAt: Date
    public var updatedAt: Date
    public var activeRunID: UUID?

    public init(
        id: TaskID,
        projectID: ProjectID,
        title: String,
        status: TaskStatus,
        createdAt: Date,
        updatedAt: Date,
        activeRunID: UUID? = nil
    ) {
        self.id = id
        self.projectID = projectID
        self.title = title
        self.status = status
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.activeRunID = activeRunID
    }
}
