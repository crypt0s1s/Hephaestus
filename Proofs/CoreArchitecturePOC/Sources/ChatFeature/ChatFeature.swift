import Anvil
import ChatContracts
import Foundation
import HephaestusKernel
import SwiftUI

public protocol SubmitUserMessageUseCase {
    func submit(_ text: String) async throws -> String
}

public struct ChatPageState: Equatable {
    public var messages: [String]
    public var draftText: String
    public var isRunning: Bool
    public var errorMessage: String?

    public init(messages: [String] = [], draftText: String = "", isRunning: Bool = false, errorMessage: String? = nil) {
        self.messages = messages
        self.draftText = draftText
        self.isRunning = isRunning
        self.errorMessage = errorMessage
    }
}

public enum ChatPageAction: Equatable {
    case changeDraft(String)
    case tapSend
}

public struct ChatPage: View {
    public let state: ChatPageState
    public let handle: (ChatPageAction) -> Void

    public init(state: ChatPageState, handle: @escaping (ChatPageAction) -> Void) {
        self.state = state
        self.handle = handle
    }

    public var body: some View {
        VStack {
            ForEach(state.messages, id: \.self) { message in
                Text(message)
            }
            TextField("Message", text: Binding(
                get: { state.draftText },
                set: { handle(.changeDraft($0)) }
            ))
            Button("Send") {
                handle(.tapSend)
            }
            .disabled(state.isRunning)
        }
    }
}

@MainActor
public final class ChatPageInteractor: BaseInteractor<ChatPageState, ChatPageAction> {
    private let input: ChatRouteInput
    private let submitMessage: SubmitUserMessageUseCase
    private let router: Router<AnyRouteInput, AnyModalInput>

    public init(
        input: ChatRouteInput,
        submitMessage: SubmitUserMessageUseCase,
        router: Router<AnyRouteInput, AnyModalInput>
    ) {
        self.input = input
        self.submitMessage = submitMessage
        self.router = router
        super.init(initialState: ChatPageState())
    }

    public override func handleAction(_ action: ChatPageAction) async {
        switch action {
        case .changeDraft(let text):
            handleChangeDraft(text)
        case .tapSend:
            await handleTapSend()
        }
    }

    private func handleChangeDraft(_ text: String) {
        setState { state in
            state.draftText = text
        }
    }

    private func handleTapSend() async {
        let text = state.draftText
        guard !text.isEmpty else { return }
        setState { state in
            state.messages.append("User: \(text)")
            state.draftText = ""
            state.isRunning = true
            state.errorMessage = nil
        }

        do {
            let response = try await submitMessage.submit(text)
            setState { state in
                state.messages.append("Assistant: \(response)")
                state.isRunning = false
            }
        } catch {
            setState { state in
                state.errorMessage = String(describing: error)
                state.isRunning = false
            }
        }
    }
}

public enum ChatRoutes {
    public static var registration: RouteRegistration {
        RouteRegistration(
            routeID: ChatRouteInput.routeID,
            version: ChatRouteInput.version,
            decodeDeepLink: { url in
                guard url.host == "route",
                      url.pathComponents.filter({ $0 != "/" }).first == ChatRouteInput.routeID
                else { return nil }
                let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
                let runIDValue = components?.queryItems?.first(where: { $0.name == "runID" })?.value
                return try AnyRouteInput(ChatRouteInput(runID: runIDValue.flatMap(UUID.init(uuidString:))))
            },
            build: { anyInput, context in
                let input = try anyInput.decode(ChatRouteInput.self)
                let submitMessage = try context.dependency(SubmitUserMessageUseCase.self)
                return AnyView(
                    Page(
                        interactor: ChatPageInteractor(
                            input: input,
                            submitMessage: submitMessage,
                            router: context.router
                        ),
                        view: ChatPage.init
                    )
                )
            }
        )
    }

    public static var settingsModalRegistration: ModalRegistration {
        ModalRegistration(
            modalID: ChatSettingsModalInput.modalID,
            version: ChatSettingsModalInput.version,
            decodeDeepLink: { url in
                guard url.host == "modal",
                      url.pathComponents.filter({ $0 != "/" }).first == ChatSettingsModalInput.modalID
                else { return nil }
                return try AnyModalInput(ChatSettingsModalInput())
            },
            build: { _, _ in
                AnyView(Text("Chat Settings"))
            }
        )
    }
}

public final class KernelSubmitUserMessageUseCase: SubmitUserMessageUseCase {
    private let run: Run

    public init(run: Run) {
        self.run = run
    }

    public func submit(_ text: String) async throws -> String {
        try await run.submitUserMessage(text).text
    }
}
