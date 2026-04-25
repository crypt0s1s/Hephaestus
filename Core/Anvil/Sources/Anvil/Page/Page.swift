import SwiftUI

public struct Page<Interactor: BaseInteractor<State, Action>, State, Action, Content: View>: View {
    @StateObject private var interactor: Interactor
    private let view: (State, @escaping (Action) -> Void) -> Content

    public init(
        interactor: @autoclosure @escaping () -> Interactor,
        @ViewBuilder view: @escaping (State, @escaping (Action) -> Void) -> Content
    ) {
        _interactor = StateObject(wrappedValue: interactor())
        self.view = view
    }

    public var body: some View {
        view(interactor.state, interactor.handle)
            .onAppear { interactor.onAppear() }
            .onDisappear { interactor.onDisappear() }
    }
}
