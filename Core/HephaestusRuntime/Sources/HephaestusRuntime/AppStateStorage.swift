import Foundation
import HephaestusKernel

public struct PersistedAppState: Sendable, Equatable, Codable {
    public var schemaVersion: Int
    public var providerSettings: PersistedProviderSettings?
    public var sessions: [PersistedSession]

    public init(
        schemaVersion: Int = 1,
        providerSettings: PersistedProviderSettings? = nil,
        sessions: [PersistedSession] = []
    ) {
        self.schemaVersion = schemaVersion
        self.providerSettings = providerSettings
        self.sessions = sessions
    }
}

public struct PersistedProviderSettings: Sendable, Equatable, Codable {
    public let baseURLString: String
    public let apiKey: String?
    public let model: String
    public let validatedAt: Date?

    public init(baseURLString: String, apiKey: String?, model: String, validatedAt: Date? = nil) {
        self.baseURLString = baseURLString
        self.apiKey = apiKey
        self.model = model
        self.validatedAt = validatedAt
    }
}

public struct ProviderSettingsDraft: Sendable, Equatable {
    public let baseURLString: String
    public let apiKey: String?
    public let model: String

    public init(baseURLString: String, apiKey: String?, model: String) {
        self.baseURLString = baseURLString
        self.apiKey = apiKey
        self.model = model
    }
}

public struct ProviderSettingsSummary: Sendable, Equatable {
    public let baseURLString: String
    public let model: String
    public let hasSavedAPIKey: Bool
    public let validatedAt: Date?

    public init(baseURLString: String, model: String, hasSavedAPIKey: Bool, validatedAt: Date?) {
        self.baseURLString = baseURLString
        self.model = model
        self.hasSavedAPIKey = hasSavedAPIKey
        self.validatedAt = validatedAt
    }
}

public enum ProviderSettingsValidationResult: Sendable, Equatable {
    case success
    case failure(String)
}

public struct PersistedSession: Sendable, Equatable, Identifiable, Codable {
    public let id: UUID
    public var title: String
    public let createdAt: Date
    public var updatedAt: Date
    public var messages: [RunMessage]
    public var turns: [Turn]
    public var events: [PersistedRuntimeEvent]
    public var providerRequests: [PersistedProviderRequestSummary]
    public var contextTraces: [PersistedContextTrace]

    public init(
        id: UUID = UUID(),
        title: String,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        messages: [RunMessage] = [],
        turns: [Turn] = [],
        events: [PersistedRuntimeEvent] = [],
        providerRequests: [PersistedProviderRequestSummary] = [],
        contextTraces: [PersistedContextTrace] = []
    ) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.messages = messages
        self.turns = turns
        self.events = events
        self.providerRequests = providerRequests
        self.contextTraces = contextTraces
    }
}

public struct PersistedSessionSummary: Sendable, Equatable, Identifiable {
    public let id: UUID
    public let title: String
    public let createdAt: Date
    public let updatedAt: Date
    public let messageCount: Int

    public init(id: UUID, title: String, createdAt: Date, updatedAt: Date, messageCount: Int) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.messageCount = messageCount
    }
}

public struct PersistedRuntimeEvent: Sendable, Equatable, Identifiable, Codable {
    public enum Kind: String, Sendable, Equatable, Codable {
        case runCreated
        case userMessageAccepted
        case contextPrepared
        case providerRequestPrepared
        case assistantTextDelta
        case assistantMessageCompleted
        case turnCancelled
        case turnFailed
    }

    public let id: UUID
    public let runID: UUID
    public let turnID: UUID?
    public let sequence: Int
    public let createdAt: Date
    public let kind: Kind
    public let summary: String
    public let messageID: UUID?
    public let providerRequestID: UUID?
    public let error: String?

    public init(
        id: UUID,
        runID: UUID,
        turnID: UUID?,
        sequence: Int,
        createdAt: Date,
        kind: Kind,
        summary: String,
        messageID: UUID? = nil,
        providerRequestID: UUID? = nil,
        error: String? = nil
    ) {
        self.id = id
        self.runID = runID
        self.turnID = turnID
        self.sequence = sequence
        self.createdAt = createdAt
        self.kind = kind
        self.summary = summary
        self.messageID = messageID
        self.providerRequestID = providerRequestID
        self.error = error
    }
}

public struct PersistedProviderRequestSummary: Sendable, Equatable, Identifiable, Codable {
    public let id: UUID
    public let runID: UUID
    public let turnID: UUID
    public let model: String
    public let messageCount: Int
    public let systemPromptIncluded: Bool
    public let stream: Bool
    public let createdAt: Date

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

public struct PersistedContextTrace: Sendable, Equatable, Identifiable, Codable {
    public let id: UUID
    public let runID: UUID
    public let turnID: UUID
    public let policyID: String
    public let policyName: String
    public let messageLimit: Int?
    public let includedMessageIDs: [UUID]
    public let excludedMessageIDs: [UUID]
    public let createdAt: Date

    public init(
        id: UUID = UUID(),
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

public struct PersistedRunInspection: Sendable, Equatable {
    public let session: PersistedSession

    public init(session: PersistedSession) {
        self.session = session
    }

    public var orderedEvents: [PersistedRuntimeEvent] {
        session.events.sorted { $0.sequence < $1.sequence }
    }
}

public enum AppStateStoreFailure: Error, Sendable, Equatable, CustomStringConvertible {
    case unsupportedSchemaVersion(Int)
    case sessionNotFound(UUID)

    public var description: String {
        switch self {
        case .unsupportedSchemaVersion(let version):
            return "Unsupported app-state schema version \(version)."
        case .sessionNotFound(let id):
            return "Persisted session \(id) was not found."
        }
    }
}

public protocol AppStateStore: Sendable {
    func load() async throws -> PersistedAppState
    func save(_ state: PersistedAppState) async throws
}

public actor FileAppStateStore: AppStateStore {
    private let fileURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let fileManager: FileManager

    public init(fileURL: URL, fileManager: FileManager = .default) {
        self.fileURL = fileURL
        self.fileManager = fileManager
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.encoder = encoder
        self.decoder = JSONDecoder()
    }

    public func load() async throws -> PersistedAppState {
        guard fileManager.fileExists(atPath: fileURL.path) else {
            return PersistedAppState()
        }

        let data = try Data(contentsOf: fileURL)
        let state = try decoder.decode(PersistedAppState.self, from: data)
        guard state.schemaVersion == 1 else {
            throw AppStateStoreFailure.unsupportedSchemaVersion(state.schemaVersion)
        }
        return state
    }

    public func save(_ state: PersistedAppState) async throws {
        guard state.schemaVersion == 1 else {
            throw AppStateStoreFailure.unsupportedSchemaVersion(state.schemaVersion)
        }

        let directory = fileURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try encoder.encode(state)
        try data.write(to: fileURL, options: [.atomic])
    }
}

public actor InMemoryAppStateStore: AppStateStore {
    private var state: PersistedAppState

    public init(state: PersistedAppState = PersistedAppState()) {
        self.state = state
    }

    public func load() async throws -> PersistedAppState {
        state
    }

    public func save(_ state: PersistedAppState) async throws {
        self.state = state
    }
}
