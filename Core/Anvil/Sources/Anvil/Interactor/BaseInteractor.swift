import Foundation
import SwiftUI

@MainActor
open class BaseInteractor<State, Action>: ObservableObject {
    @Published public private(set) var state: State

    private let taskScope = PageTaskScope()

    public init(initialState: State) {
        self.state = initialState
    }

    public func handle(_ action: Action) {
        taskScope.run { [weak self] in
            await self?.handleAction(action)
        }
    }

    open func onAppear() {}

    open func onDisappear() {
        taskScope.cancelAll()
    }

    open func handleAction(_ action: Action) async {
        preconditionFailure("Override handleAction(_:)")
    }

    public func setState(_ update: (inout State) -> Void) {
        update(&state)
    }
}
