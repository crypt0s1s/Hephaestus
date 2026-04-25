import Foundation
import SwiftUI

public enum RouteBuildError: Error, Equatable {
    case missingDependency(String)
}

public struct RouteBuildContext {
    public let router: Router<AnyRouteInput, AnyModalInput>
    private let resolveDependency: (Any.Type) throws -> Any

    public init(
        router: Router<AnyRouteInput, AnyModalInput>,
        resolveDependency: @escaping (Any.Type) throws -> Any
    ) {
        self.router = router
        self.resolveDependency = resolveDependency
    }

    public func dependency<T>(_ type: T.Type = T.self) throws -> T {
        guard let value = try resolveDependency(type) as? T else {
            throw RouteBuildError.missingDependency(String(describing: type))
        }
        return value
    }
}

public struct RouteRegistration {
    public let routeID: String
    public let version: Int
    public let decodeDeepLink: (URL) throws -> AnyRouteInput?
    public let build: @MainActor (AnyRouteInput, RouteBuildContext) throws -> AnyView

    public init(
        routeID: String,
        version: Int,
        decodeDeepLink: @escaping (URL) throws -> AnyRouteInput?,
        build: @escaping @MainActor (AnyRouteInput, RouteBuildContext) throws -> AnyView
    ) {
        self.routeID = routeID
        self.version = version
        self.decodeDeepLink = decodeDeepLink
        self.build = build
    }
}

public struct ModalRegistration {
    public let modalID: String
    public let version: Int
    public let decodeDeepLink: (URL) throws -> AnyModalInput?
    public let build: @MainActor (AnyModalInput, RouteBuildContext) throws -> AnyView

    public init(
        modalID: String,
        version: Int,
        decodeDeepLink: @escaping (URL) throws -> AnyModalInput?,
        build: @escaping @MainActor (AnyModalInput, RouteBuildContext) throws -> AnyView
    ) {
        self.modalID = modalID
        self.version = version
        self.decodeDeepLink = decodeDeepLink
        self.build = build
    }
}

public enum DestinationRegistryError: Error, Equatable {
    case duplicateRouteID(String)
    case duplicateModalID(String)
    case unknownRouteID(String)
    case unknownModalID(String)
    case unsupportedDeepLink(URL)
}

public struct DestinationRegistry {
    private let routes: [String: RouteRegistration]
    private let modals: [String: ModalRegistration]

    public init(routes: [RouteRegistration], modals: [ModalRegistration]) throws {
        var routeMap: [String: RouteRegistration] = [:]
        for route in routes {
            guard routeMap[route.routeID] == nil else {
                throw DestinationRegistryError.duplicateRouteID(route.routeID)
            }
            routeMap[route.routeID] = route
        }

        var modalMap: [String: ModalRegistration] = [:]
        for modal in modals {
            guard modalMap[modal.modalID] == nil else {
                throw DestinationRegistryError.duplicateModalID(modal.modalID)
            }
            modalMap[modal.modalID] = modal
        }

        self.routes = routeMap
        self.modals = modalMap
    }

    public func decodeDeepLink(_ url: URL) throws -> NavigationIntent {
        let components = url.pathComponents.filter { $0 != "/" }
        guard let destinationID = components.first else {
            throw DestinationRegistryError.unsupportedDeepLink(url)
        }

        switch url.host {
        case "route":
            guard let registration = routes[destinationID] else {
                throw DestinationRegistryError.unknownRouteID(destinationID)
            }
            guard let input = try registration.decodeDeepLink(url) else {
                throw DestinationRegistryError.unsupportedDeepLink(url)
            }
            return .push(input)
        case "modal":
            guard let registration = modals[destinationID] else {
                throw DestinationRegistryError.unknownModalID(destinationID)
            }
            guard let input = try registration.decodeDeepLink(url) else {
                throw DestinationRegistryError.unsupportedDeepLink(url)
            }
            return .presentModal(input)
        default:
            throw DestinationRegistryError.unsupportedDeepLink(url)
        }
    }

    @MainActor
    public func buildRoute(_ input: AnyRouteInput, context: RouteBuildContext) throws -> AnyView {
        guard let route = routes[input.routeID] else {
            throw DestinationRegistryError.unknownRouteID(input.routeID)
        }
        guard route.version == input.version else {
            throw DestinationRegistryError.unsupportedDeepLink(URL(string: "hephaestus://route/\(input.routeID)")!)
        }
        return try route.build(input, context)
    }

    @MainActor
    public func buildModal(_ input: AnyModalInput, context: RouteBuildContext) throws -> AnyView {
        guard let modal = modals[input.modalID] else {
            throw DestinationRegistryError.unknownModalID(input.modalID)
        }
        guard modal.version == input.version else {
            throw DestinationRegistryError.unsupportedDeepLink(URL(string: "hephaestus://modal/\(input.modalID)")!)
        }
        return try modal.build(input, context)
    }
}
