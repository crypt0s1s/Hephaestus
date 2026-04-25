import Foundation

public protocol RouteInput: Codable, Hashable, Sendable {
    static var routeID: String { get }
    static var version: Int { get }
}

public protocol ModalInput: Codable, Hashable, Sendable {
    static var modalID: String { get }
    static var version: Int { get }
}

public enum DestinationInputError: Error, Equatable {
    case routeIDMismatch(expected: String, actual: String)
    case modalIDMismatch(expected: String, actual: String)
    case unsupportedVersion(expected: Int, actual: Int)
}

public struct AnyRouteInput: Hashable, Sendable {
    public let routeID: String
    public let version: Int
    public let encoded: Data

    public init<T: RouteInput>(_ input: T, encoder: JSONEncoder = JSONEncoder()) throws {
        routeID = T.routeID
        version = T.version
        encoded = try encoder.encode(input)
    }

    public func decode<T: RouteInput>(_ type: T.Type, decoder: JSONDecoder = JSONDecoder()) throws -> T {
        guard routeID == T.routeID else {
            throw DestinationInputError.routeIDMismatch(expected: T.routeID, actual: routeID)
        }
        guard version == T.version else {
            throw DestinationInputError.unsupportedVersion(expected: T.version, actual: version)
        }
        return try decoder.decode(T.self, from: encoded)
    }
}

public struct AnyModalInput: Hashable, Identifiable, Sendable {
    public let modalID: String
    public let version: Int
    public let encoded: Data
    public let instanceID: UUID

    public var id: UUID { instanceID }

    public init<T: ModalInput>(_ input: T, instanceID: UUID = UUID(), encoder: JSONEncoder = JSONEncoder()) throws {
        modalID = T.modalID
        version = T.version
        encoded = try encoder.encode(input)
        self.instanceID = instanceID
    }

    public func decode<T: ModalInput>(_ type: T.Type, decoder: JSONDecoder = JSONDecoder()) throws -> T {
        guard modalID == T.modalID else {
            throw DestinationInputError.modalIDMismatch(expected: T.modalID, actual: modalID)
        }
        guard version == T.version else {
            throw DestinationInputError.unsupportedVersion(expected: T.version, actual: version)
        }
        return try decoder.decode(T.self, from: encoded)
    }
}

public enum NavigationIntent: Equatable {
    case push(AnyRouteInput)
    case replaceStack([AnyRouteInput])
    case presentModal(AnyModalInput)
    case dismissModal
}
