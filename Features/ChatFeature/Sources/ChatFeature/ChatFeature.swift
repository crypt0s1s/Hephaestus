import Anvil
import ChatContracts
import Foundation
import HephaestusRuntime
import SwiftUI

public struct ChatMessageState: Equatable, Identifiable {
    public enum Role: Equatable {
        case user
        case assistant
    }

    public var id: UUID
    public var role: Role
    public var text: String
    public var isStreaming: Bool

    public init(id: UUID = UUID(), role: Role, text: String, isStreaming: Bool = false) {
        self.id = id
        self.role = role
        self.text = text
        self.isStreaming = isStreaming
    }
}

public struct ChatPageState: Equatable {
    public var runID: UUID?
    public var messages: [ChatMessageState]
    public var draftText: String
    public var isRunning: Bool
    public var errorMessage: String?

    public init(
        runID: UUID? = nil,
        messages: [ChatMessageState] = [],
        draftText: String = "",
        isRunning: Bool = false,
        errorMessage: String? = nil
    ) {
        self.runID = runID
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
        VStack(alignment: .leading, spacing: 16) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    ForEach(state.messages) { message in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(message.role == .user ? "You" : "Assistant")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(message.text + (message.isStreaming ? "▌" : ""))
                                .textSelection(.enabled)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                        .background(message.role == .user ? Color.blue.opacity(0.12) : Color.gray.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                }
                .padding()
            }

            if let errorMessage = state.errorMessage {
                Text(errorMessage)
                    .foregroundStyle(.red)
            }

            HStack {
                TextField("Message", text: Binding(
                    get: { state.draftText },
                    set: { handle(.changeDraft($0)) }
                ))
                Button("Send") {
                    handle(.tapSend)
                }
                .disabled(state.isRunning || state.draftText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding()
        }
        .frame(minWidth: 560, minHeight: 420)
    }
}

@MainActor
public final class ChatPageInteractor: BaseInteractor<ChatPageState, ChatPageAction> {
    private let createRun: CreateRunUseCase
    private let streamUserMessage: StreamUserMessageUseCase
    private let router: Router<AnyRouteInput, AnyModalInput>

    public init(
        input: ChatRouteInput,
        createRun: CreateRunUseCase,
        streamUserMessage: StreamUserMessageUseCase,
        router: Router<AnyRouteInput, AnyModalInput>
    ) {
        self.createRun = createRun
        self.streamUserMessage = streamUserMessage
        self.router = router
        super.init(initialState: ChatPageState(runID: input.runID))
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
        let text = state.draftText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        do {
            let runID = try await ensureRun()
            setState { state in
                state.draftText = ""
                state.isRunning = true
                state.errorMessage = nil
            }

            let stream = try await streamUserMessage.streamUserMessage(runID: runID, text: text)
            for try await event in stream {
                apply(event)
            }
        } catch is CancellationError {
            setState { state in
                state.isRunning = false
                markStreamingAssistantComplete(in: &state)
            }
        } catch {
            setState { state in
                state.errorMessage = String(describing: error)
                state.isRunning = false
                markStreamingAssistantComplete(in: &state)
            }
        }
    }

    private func ensureRun() async throws -> UUID {
        if let runID = state.runID {
            return runID
        }
        let runID = await createRun.createRun()
        setState { state in
            state.runID = runID
        }
        return runID
    }

    private func apply(_ event: RuntimeEvent) {
        setState { state in
            switch event {
            case .runCreated(_, let runID):
                state.runID = runID
            case .userMessageAccepted(_, let messageID, let text):
                state.messages.append(
                    ChatMessageState(id: messageID, role: .user, text: text)
                )
            case .contextPrepared(_, _):
                break
            case .assistantTextDelta(_, let text):
                appendAssistantDelta(text, to: &state)
            case .assistantMessageCompleted(_, let messageID, let text):
                completeAssistantMessage(messageID: messageID, text: text, in: &state)
                state.isRunning = false
            case .turnCancelled(_):
                state.isRunning = false
                markStreamingAssistantComplete(in: &state)
            case .turnFailed(_, let reason):
                state.errorMessage = reason
                state.isRunning = false
                markStreamingAssistantComplete(in: &state)
            }
        }
    }

    private func appendAssistantDelta(_ text: String, to state: inout ChatPageState) {
        if let index = state.messages.lastIndex(where: { $0.role == .assistant && $0.isStreaming }) {
            state.messages[index].text += text
        } else {
            state.messages.append(
                ChatMessageState(role: .assistant, text: text, isStreaming: true)
            )
        }
    }

    private func completeAssistantMessage(messageID: UUID, text: String, in state: inout ChatPageState) {
        if let index = state.messages.lastIndex(where: { $0.role == .assistant && $0.isStreaming }) {
            state.messages[index].id = messageID
            state.messages[index].text = text
            state.messages[index].isStreaming = false
        } else {
            state.messages.append(
                ChatMessageState(id: messageID, role: .assistant, text: text)
            )
        }
    }

    private func markStreamingAssistantComplete(in state: inout ChatPageState) {
        if let index = state.messages.lastIndex(where: { $0.role == .assistant && $0.isStreaming }) {
            state.messages[index].isStreaming = false
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
                let runID: UUID?
                if let runIDValue {
                    guard let parsedRunID = UUID(uuidString: runIDValue) else {
                        return nil
                    }
                    runID = parsedRunID
                } else {
                    runID = nil
                }
                return try AnyRouteInput(ChatRouteInput(runID: runID))
            },
            build: { anyInput, context in
                let input = try anyInput.decode(ChatRouteInput.self)
                let createRun = try context.dependency(CreateRunUseCase.self)
                let streamUserMessage = try context.dependency(StreamUserMessageUseCase.self)
                return AnyView(
                    Page(
                        interactor: ChatPageInteractor(
                            input: input,
                            createRun: createRun,
                            streamUserMessage: streamUserMessage,
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
