import SwiftUI

public struct Page<PageInteractor: Interactor, Content: View>: View {
    @StateObject private var interactor: PageInteractor
    private let view: (PageInteractor.State, @escaping (PageInteractor.Action) -> Void) -> Content

    public init(
        interactor: @autoclosure @escaping () -> PageInteractor,
        @ViewBuilder view: @escaping (PageInteractor.State, @escaping (PageInteractor.Action) -> Void) -> Content
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
