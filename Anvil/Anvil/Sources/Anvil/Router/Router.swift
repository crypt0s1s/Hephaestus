import Foundation
import SwiftUI

@MainActor
public final class Router<Route: Hashable, Modal: Identifiable>: ObservableObject {
    @Published public var path: [Route]
    @Published public var modal: Modal?

    public init(path: [Route] = [], modal: Modal? = nil) {
        self.path = path
        self.modal = modal
    }

    public func push(_ route: Route) {
        path.append(route)
    }

    public func replaceStack(_ routes: [Route]) {
        path = routes
    }

    public func pop() {
        _ = path.popLast()
    }

    public func popToRoot() {
        path.removeAll()
    }

    public func present(_ modal: Modal) {
        self.modal = modal
    }

    public func dismissModal() {
        modal = nil
    }
}

extension Router where Route == AnyRouteInput, Modal == AnyModalInput {
    public func apply(_ intent: NavigationIntent) {
        switch intent {
        case .push(let route):
            push(route)
        case .replaceStack(let routes):
            replaceStack(routes)
        case .presentModal(let modal):
            present(modal)
        case .dismissModal:
            dismissModal()
        }
    }
}
