import Foundation

public struct ProjectID: Hashable, Codable, Sendable, CustomStringConvertible {
    public var rawValue: UUID

    public init(rawValue: UUID) {
        self.rawValue = rawValue
    }

    public var description: String {
        rawValue.uuidString
    }
}

public struct Project: Hashable, Codable, Identifiable, Sendable {
    public var id: ProjectID
    public var name: String
    public var rootURL: URL?
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: ProjectID,
        name: String,
        rootURL: URL? = nil,
        createdAt: Date,
        updatedAt: Date
    ) {
        self.id = id
        self.name = name
        self.rootURL = rootURL
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public enum DefaultProject {
    public static let id = ProjectID(
        rawValue: UUID(uuidString: "00000000-0000-0000-0000-000000000001") ?? UUID()
    )

    public static func local(
        rootURL: URL? = nil,
        now: Date = Date()
    ) -> Project {
        Project(
            id: id,
            name: rootURL?.lastPathComponent.nilIfEmpty ?? "Local Project",
            rootURL: rootURL,
            createdAt: now,
            updatedAt: now
        )
    }
}

extension String {
    fileprivate var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
