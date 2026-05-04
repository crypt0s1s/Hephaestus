import Foundation
import HephaestusDomain
import HephaestusObservation

public struct HarnessBackendID: Hashable, Codable, Sendable, CustomStringConvertible {
    public var rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public var description: String {
        rawValue
    }
}

public enum HarnessBackendAvailability: String, Hashable, Codable, Sendable {
    case available
    case unavailable
}

public struct HarnessBackendDescriptor: Hashable, Codable, Identifiable, Sendable {
    public var id: HarnessBackendID
    public var displayName: String
    public var availability: HarnessBackendAvailability
    public var capabilities: Set<HarnessBackendCapability>

    public init(
        id: HarnessBackendID,
        displayName: String,
        availability: HarnessBackendAvailability,
        capabilities: Set<HarnessBackendCapability>
    ) {
        self.id = id
        self.displayName = displayName
        self.availability = availability
        self.capabilities = capabilities
    }
}

public enum HarnessBackendCapability: String, Hashable, Codable, Sendable {
    case liveEvents
    case conversation
    case toolEvents
    case approvalEvents
    case fileChangeSummaries
    case structuredFinalOutput
    case resume
    case rawPayloadCapture
}

public struct HarnessRunIdentity: Hashable, Codable, Sendable {
    public var taskID: TaskID
    public var runID: UUID
    public var backendID: HarnessBackendID

    public init(
        taskID: TaskID,
        runID: UUID,
        backendID: HarnessBackendID
    ) {
        self.taskID = taskID
        self.runID = runID
        self.backendID = backendID
    }
}

public struct HarnessRunRequest: Hashable, Sendable {
    public var identity: HarnessRunIdentity
    public var prompt: String

    public init(identity: HarnessRunIdentity, prompt: String) {
        self.identity = identity
        self.prompt = prompt
    }
}
