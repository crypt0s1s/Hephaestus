import Anvil
import ChatContracts
import Foundation
import HephaestusKernel
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
    public var sessions: [ChatSessionSummaryState]
    public var isLoadingSessions: Bool
    public var persistenceErrorMessage: String?
    public var providerSettings: ProviderSettingsPanelState
    public var inspector: RunInspectorPanelState

    public init(
        runID: UUID? = nil,
        messages: [ChatMessageState] = [],
        draftText: String = "",
        isRunning: Bool = false,
        errorMessage: String? = nil,
        sessions: [ChatSessionSummaryState] = [],
        isLoadingSessions: Bool = false,
        persistenceErrorMessage: String? = nil,
        providerSettings: ProviderSettingsPanelState = ProviderSettingsPanelState(),
        inspector: RunInspectorPanelState = RunInspectorPanelState()
    ) {
        self.runID = runID
        self.messages = messages
        self.draftText = draftText
        self.isRunning = isRunning
        self.errorMessage = errorMessage
        self.sessions = sessions
        self.isLoadingSessions = isLoadingSessions
        self.persistenceErrorMessage = persistenceErrorMessage
        self.providerSettings = providerSettings
        self.inspector = inspector
    }
}

public enum ChatPageAction: Equatable {
    case changeDraft(String)
    case tapSend
    case tapNewChat
    case tapChat(UUID)
    case tapSettings
    case dismissSettings
    case changeProviderBaseURL(String)
    case changeProviderAPIKey(String)
    case changeProviderModel(String)
    case validateProviderSettings
    case saveProviderSettings
    case clearProviderSettings
    case tapInspector
    case dismissInspector
}

public struct ChatSessionSummaryState: Equatable, Identifiable {
    public let id: UUID
    public var title: String
    public var updatedAt: Date
    public var messageCount: Int

    public init(id: UUID, title: String, updatedAt: Date, messageCount: Int) {
        self.id = id
        self.title = title
        self.updatedAt = updatedAt
        self.messageCount = messageCount
    }
}

public struct ProviderSettingsPanelState: Equatable {
    public enum ValidationState: Equatable {
        case idle
        case validating
        case success(String)
        case failure(String)
    }

    public var isPresented: Bool
    public var baseURLString: String
    public var apiKeyReplacement: String
    public var model: String
    public var hasSavedAPIKey: Bool
    public var validatedAt: Date?
    public var validation: ValidationState
    public var isSaving: Bool
    public var errorMessage: String?

    public init(
        isPresented: Bool = false,
        baseURLString: String = "https://api.openai.com/v1",
        apiKeyReplacement: String = "",
        model: String = "gpt-4.1-mini",
        hasSavedAPIKey: Bool = false,
        validatedAt: Date? = nil,
        validation: ValidationState = .idle,
        isSaving: Bool = false,
        errorMessage: String? = nil
    ) {
        self.isPresented = isPresented
        self.baseURLString = baseURLString
        self.apiKeyReplacement = apiKeyReplacement
        self.model = model
        self.hasSavedAPIKey = hasSavedAPIKey
        self.validatedAt = validatedAt
        self.validation = validation
        self.isSaving = isSaving
        self.errorMessage = errorMessage
    }
}

public struct RunInspectorPanelState: Equatable {
    public var isPresented: Bool
    public var isLoading: Bool
    public var inspection: PersistedRunInspection?
    public var errorMessage: String?

    public init(
        isPresented: Bool = false,
        isLoading: Bool = false,
        inspection: PersistedRunInspection? = nil,
        errorMessage: String? = nil
    ) {
        self.isPresented = isPresented
        self.isLoading = isLoading
        self.inspection = inspection
        self.errorMessage = errorMessage
    }
}

extension ChatSessionSummaryState {
    init(summary: PersistedSessionSummary) {
        self.init(
            id: summary.id,
            title: summary.title,
            updatedAt: summary.updatedAt,
            messageCount: summary.messageCount
        )
    }
}

extension ChatMessageState {
    init?(message: RunMessage) {
        switch message.role {
        case .user:
            self.init(id: message.id, role: .user, text: message.text)
        case .assistant:
            self.init(id: message.id, role: .assistant, text: message.text)
        case .system, .tool:
            return nil
        }
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}

private enum ChatScrollTarget {
    static let bottom = "chat-scroll-bottom"
    static let coordinateSpace = "chat-scroll-coordinate-space"
    static let pinnedThreshold: CGFloat = 44
}

private enum ChatAccessibilityID {
    static let historyList = "chat.history.list"
    static let historyEmptyState = "chat.history.emptyState"
    static let newChatButton = "chat.history.newChat"
    static let settingsButton = "chat.provider.settings"
    static let inspectorButton = "chat.inspector.open"
    static let transcript = "chat.transcript"
    static let emptyState = "chat.emptyState"
    static let messageInput = "chat.messageInput"
    static let sendButton = "chat.sendButton"
    static let runningStatus = "chat.runningStatus"
    static let errorBanner = "chat.errorBanner"
    static let persistenceError = "chat.persistence.error"
    static let providerBaseURL = "provider.baseURL"
    static let providerAPIKey = "provider.apiKey"
    static let providerModel = "provider.model"
    static let providerValidate = "provider.validate"
    static let providerSave = "provider.save"
    static let providerClear = "provider.clear"
    static let inspectorPanel = "inspector.panel"
    static let inspectorTimeline = "inspector.timeline"
}

public struct ChatPage: View {
    public let state: ChatPageState
    public let handle: (ChatPageAction) -> Void
    @State private var isTranscriptPinnedToBottom = true

    private var trimmedDraft: String {
        state.draftText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canSend: Bool {
        !state.isRunning && !trimmedDraft.isEmpty
    }

    public init(state: ChatPageState, handle: @escaping (ChatPageAction) -> Void) {
        self.state = state
        self.handle = handle
    }

    public var body: some View {
        HStack(spacing: 0) {
            HistorySidebar(
                sessions: state.sessions,
                selectedRunID: state.runID,
                isLoading: state.isLoadingSessions,
                errorMessage: state.persistenceErrorMessage,
                handle: handle
            )
            .frame(width: 250)

            Divider()

            VStack(spacing: 0) {
                ChatHeader(
                    isRunning: state.isRunning,
                    runID: state.runID,
                    canInspect: state.runID != nil,
                    handle: handle
                )

                Divider()

                transcript

                Divider()

                VStack(spacing: 10) {
                    if let errorMessage = state.errorMessage {
                        ErrorBanner(message: errorMessage)
                    }

                    composer
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 14)
                .background(.bar)
            }
        }
        .frame(minWidth: 920, minHeight: 560)
        .background(Color(nsColor: .windowBackgroundColor))
        .sheet(
            isPresented: Binding(
                get: { state.providerSettings.isPresented },
                set: { if !$0 { handle(.dismissSettings) } }
            )
        ) {
            ProviderSettingsSheet(state: state.providerSettings, handle: handle)
        }
        .popover(
            isPresented: Binding(
                get: { state.inspector.isPresented },
                set: { if !$0 { handle(.dismissInspector) } }
            ),
            attachmentAnchor: .rect(.bounds),
            arrowEdge: .top
        ) {
            RunInspectorSheet(state: state.inspector)
        }
    }

    private var transcript: some View {
        ScrollViewReader { proxy in
            GeometryReader { viewport in
                ScrollView {
                    LazyVStack(spacing: 14) {
                        if state.messages.isEmpty {
                            EmptyChatState()
                                .padding(.top, 68)
                        } else {
                            ForEach(state.messages) { message in
                                MessageBubble(message: message)
                            }
                        }

                        if state.isRunning {
                            RunningStatus()
                        }

                        Color.clear
                            .frame(height: 1)
                            .id(ChatScrollTarget.bottom)
                            .background {
                                GeometryReader { bottomMarker in
                                    Color.clear.preference(
                                        key: ChatBottomDistancePreferenceKey.self,
                                        value: bottomMarker.frame(in: .named(ChatScrollTarget.coordinateSpace)).maxY
                                            - viewport.size.height
                                    )
                                }
                            }
                    }
                    .padding(.horizontal, 22)
                    .padding(.vertical, 20)
                }
                .coordinateSpace(name: ChatScrollTarget.coordinateSpace)
                .accessibilityLabel("Chat transcript")
                .accessibilityIdentifier(ChatAccessibilityID.transcript)
                .onPreferenceChange(ChatBottomDistancePreferenceKey.self) { distanceFromBottom in
                    isTranscriptPinnedToBottom = distanceFromBottom <= ChatScrollTarget.pinnedThreshold
                }
                .onChange(of: state.messages, initial: true) {
                    scrollToBottomIfPinned(proxy)
                }
                .onChange(of: state.isRunning, initial: false) {
                    scrollToBottomIfPinned(proxy)
                }
            }
        }
    }

    private func scrollToBottomIfPinned(_ proxy: ScrollViewProxy) {
        guard isTranscriptPinnedToBottom else { return }
        proxy.scrollTo(ChatScrollTarget.bottom, anchor: .bottom)
    }

    private var composer: some View {
        HStack(alignment: .center, spacing: 10) {
            TextField("Ask Hephaestus", text: Binding(
                get: { state.draftText },
                set: { handle(.changeDraft($0)) }
            ), axis: .vertical)
            .textFieldStyle(.plain)
            .lineLimit(1...4)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Color(nsColor: .textBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.primary.opacity(0.10), lineWidth: 1)
            }
            .onSubmit {
                handle(.tapSend)
            }
            .accessibilityLabel("Message")
            .accessibilityIdentifier(ChatAccessibilityID.messageInput)

            Button {
                handle(.tapSend)
            } label: {
                Label("Send", systemImage: "paperplane.fill")
                    .labelStyle(.iconOnly)
                    .frame(width: 34, height: 34)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(!canSend)
            .help("Send message")
            .accessibilityLabel("Send message")
            .accessibilityIdentifier(ChatAccessibilityID.sendButton)
        }
    }
}

private struct ChatBottomDistancePreferenceKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

private struct HistorySidebar: View {
    let sessions: [ChatSessionSummaryState]
    let selectedRunID: UUID?
    let isLoading: Bool
    let errorMessage: String?
    let handle: (ChatPageAction) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Chats")
                    .font(.headline)
                Spacer()
                Button {
                    handle(.tapNewChat)
                } label: {
                    Label("New chat", systemImage: "square.and.pencil")
                        .labelStyle(.iconOnly)
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.borderless)
                .help("New chat")
                .accessibilityIdentifier(ChatAccessibilityID.newChatButton)
            }

            if let errorMessage {
                ErrorBanner(message: errorMessage)
                    .accessibilityIdentifier(ChatAccessibilityID.persistenceError)
            }

            if isLoading {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Loading")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            } else if sessions.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Image(systemName: "tray")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                    Text("No saved chats")
                        .font(.callout.weight(.semibold))
                    Text("Start a chat and it will appear here.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 18)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier(ChatAccessibilityID.historyEmptyState)
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 6) {
                        ForEach(sessions) { session in
                            let isSelected = selectedRunID == session.id
                            Button {
                                guard !isSelected else { return }
                                handle(.tapChat(session.id))
                            } label: {
                                HistoryRow(
                                    session: session,
                                    isSelected: isSelected
                                )
                            }
                            .buttonStyle(.plain)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                .accessibilityIdentifier(ChatAccessibilityID.historyList)
            }
        }
        .padding(14)
        .background(Color(nsColor: .controlBackgroundColor))
    }
}

private struct HistoryRow: View {
    let session: ChatSessionSummaryState
    let isSelected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(session.title)
                .font(.callout.weight(.medium))
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("\(session.messageCount) messages")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .background(isSelected ? Color.accentColor.opacity(0.15) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(isSelected ? Color.accentColor.opacity(0.35) : Color.primary.opacity(0.06), lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(session.title), \(session.messageCount) messages")
    }
}

private struct ChatHeader: View {
    let isRunning: Bool
    let runID: UUID?
    let canInspect: Bool
    let handle: (ChatPageAction) -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "hammer.fill")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 34, height: 34)
                .background(Color.accentColor)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text("Hephaestus Chat")
                    .font(.headline)
                Text(runSubtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                handle(.tapInspector)
            } label: {
                Label("Inspect run", systemImage: "list.bullet.rectangle")
                    .labelStyle(.iconOnly)
                    .frame(width: 30, height: 30)
            }
            .buttonStyle(.borderless)
            .disabled(!canInspect)
            .help("Inspect run")
            .accessibilityLabel("Inspect run")
            .accessibilityIdentifier(ChatAccessibilityID.inspectorButton)

            Button {
                handle(.tapSettings)
            } label: {
                Label("Provider settings", systemImage: "gearshape")
                    .labelStyle(.iconOnly)
                    .frame(width: 30, height: 30)
            }
            .buttonStyle(.borderless)
            .help("Provider settings")
            .accessibilityLabel("Provider settings")
            .accessibilityIdentifier(ChatAccessibilityID.settingsButton)

            HStack(spacing: 6) {
                Circle()
                    .fill(isRunning ? Color.orange : Color.green)
                    .frame(width: 8, height: 8)
                Text(isRunning ? "Responding" : "Ready")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.primary.opacity(0.06))
            .clipShape(Capsule())
            .accessibilityLabel(isRunning ? "Assistant responding" : "Assistant ready")
            .accessibilityIdentifier(isRunning ? ChatAccessibilityID.runningStatus : "chat.readyStatus")
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .background(.bar)
    }

    private var runSubtitle: String {
        guard let runID else {
            return "New local run"
        }
        return "Run \(runID.uuidString.prefix(8))"
    }
}

private struct EmptyChatState: View {
    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "sparkles")
                .font(.system(size: 30, weight: .medium))
                .foregroundStyle(Color.accentColor)
                .accessibilityHidden(true)

            VStack(spacing: 5) {
                Text("Start a focused run")
                    .font(.title3.weight(.semibold))
                Text("Ask a question, test an idea, or capture the next implementation step.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 420)
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(ChatAccessibilityID.emptyState)
    }
}

private struct RunningStatus: View {
    var body: some View {
        HStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)
            Text("Assistant is writing")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.leading, 6)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(ChatAccessibilityID.runningStatus)
    }
}

private struct ErrorBanner: View {
    let message: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
                .accessibilityHidden(true)
            Text(message)
                .font(.callout)
                .foregroundStyle(.primary)
                .textSelection(.enabled)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.red.opacity(0.10))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.red.opacity(0.22), lineWidth: 1)
        }
        .accessibilityLabel("Chat error: \(message)")
        .accessibilityIdentifier(ChatAccessibilityID.errorBanner)
    }
}

private struct ProviderSettingsSheet: View {
    let state: ProviderSettingsPanelState
    let handle: (ChatPageAction) -> Void

    private var canSubmit: Bool {
        !state.isSaving && state.validation != .validating
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Provider Settings")
                        .font(.title3.weight(.semibold))
                    Text(state.hasSavedAPIKey ? "A saved API key is available." : "No API key is saved.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Cancel") {
                    handle(.dismissSettings)
                }
                .keyboardShortcut(.cancelAction)
            }

            VStack(alignment: .leading, spacing: 12) {
                LabeledContent("Base URL") {
                    TextField("https://api.openai.com/v1", text: Binding(
                        get: { state.baseURLString },
                        set: { handle(.changeProviderBaseURL($0)) }
                    ))
                    .textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier(ChatAccessibilityID.providerBaseURL)
                }

                LabeledContent("API key") {
                    SecureField(state.hasSavedAPIKey ? "Leave blank to keep saved key" : "Required", text: Binding(
                        get: { state.apiKeyReplacement },
                        set: { handle(.changeProviderAPIKey($0)) }
                    ))
                    .textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier(ChatAccessibilityID.providerAPIKey)
                }

                LabeledContent("Model") {
                    TextField("gpt-4.1-mini", text: Binding(
                        get: { state.model },
                        set: { handle(.changeProviderModel($0)) }
                    ))
                    .textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier(ChatAccessibilityID.providerModel)
                }
            }

            validationView

            if let errorMessage = state.errorMessage {
                ErrorBanner(message: errorMessage)
            }

            HStack {
                Button("Clear") {
                    handle(.clearProviderSettings)
                }
                .disabled(state.isSaving)
                .accessibilityIdentifier(ChatAccessibilityID.providerClear)

                Spacer()

                Button("Validate") {
                    handle(.validateProviderSettings)
                }
                .disabled(!canSubmit)
                .accessibilityIdentifier(ChatAccessibilityID.providerValidate)

                Button("Save") {
                    handle(.saveProviderSettings)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canSubmit)
                .accessibilityIdentifier(ChatAccessibilityID.providerSave)
            }
        }
        .padding(22)
        .frame(width: 560)
    }

    @ViewBuilder
    private var validationView: some View {
        switch state.validation {
        case .idle:
            Text("Validate before saving live provider settings.")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .validating:
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text("Validating provider")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        case .success(let message):
            Label(message, systemImage: "checkmark.circle.fill")
                .font(.caption)
                .foregroundStyle(.green)
        case .failure(let message):
            Label(message, systemImage: "xmark.octagon.fill")
                .font(.caption)
                .foregroundStyle(.red)
                .textSelection(.enabled)
        }
    }
}

private struct RunInspectorSheet: View {
    let state: RunInspectorPanelState

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Run Inspector")
                .font(.title3.weight(.semibold))

            if state.isLoading {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Loading run details")
                        .foregroundStyle(.secondary)
                }
                Spacer()
            } else if let errorMessage = state.errorMessage {
                ErrorBanner(message: errorMessage)
                Spacer()
            } else if let inspection = state.inspection {
                RunInspectionContent(inspection: inspection)
            } else {
                ContentUnavailableView("No run selected", systemImage: "list.bullet.rectangle")
                Spacer()
            }
        }
        .padding(22)
        .frame(width: 720, height: 620)
        .accessibilityIdentifier(ChatAccessibilityID.inspectorPanel)
    }
}

private struct RunInspectionContent: View {
    let inspection: PersistedRunInspection

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                InspectorSection(title: "Timeline") {
                    if inspection.orderedEvents.isEmpty {
                        UnavailableRow(text: "No runtime events are available.")
                    } else {
                        ForEach(inspection.orderedEvents) { event in
                            VStack(alignment: .leading, spacing: 4) {
                                Text("\(event.sequence). \(event.kind.rawValue)")
                                    .font(.caption.weight(.semibold))
                                Text(event.summary)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .textSelection(.enabled)
                                if let error = event.error {
                                    Text(error)
                                        .font(.caption)
                                        .foregroundStyle(.red)
                                        .textSelection(.enabled)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(10)
                            .background(event.error == nil ? Color.primary.opacity(0.04) : Color.red.opacity(0.10))
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        }
                    }
                }
                .accessibilityIdentifier(ChatAccessibilityID.inspectorTimeline)

                InspectorSection(title: "Turns") {
                    if inspection.session.turns.isEmpty {
                        UnavailableRow(text: "No turns are available.")
                    } else {
                        ForEach(inspection.session.turns) { turn in
                            TurnInspectionRow(turn: turn, messages: inspection.session.messages)
                        }
                    }
                }

                InspectorSection(title: "Provider") {
                    if inspection.session.providerRequests.isEmpty {
                        UnavailableRow(text: "Provider request details are unavailable.")
                    } else {
                        ForEach(inspection.session.providerRequests) { request in
                            Text("\(request.model): \(request.messageCount) messages, stream \(request.stream ? "on" : "off"), system prompt \(request.systemPromptIncluded ? "included" : "excluded")")
                                .font(.caption)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(10)
                                .background(Color.primary.opacity(0.04))
                                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        }
                    }
                }

                InspectorSection(title: "Context") {
                    if inspection.session.contextTraces.isEmpty {
                        UnavailableRow(text: "Context details are unavailable.")
                    } else {
                        ForEach(inspection.session.contextTraces) { trace in
                            ContextTraceRow(trace: trace, messages: inspection.session.messages)
                        }
                    }
                }
            }
        }
    }
}

private struct InspectorSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct TurnInspectionRow: View {
    let turn: Turn
    let messages: [RunMessage]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Turn \(turn.id.uuidString.prefix(8)) - \(String(describing: turn.status))")
                .font(.caption.weight(.semibold))
            Text("User: \(messageText(turn.userMessageID))")
                .font(.caption)
                .textSelection(.enabled)
            if let assistantMessageID = turn.assistantMessageID {
                Text("Assistant: \(messageText(assistantMessageID))")
                    .font(.caption)
                    .textSelection(.enabled)
            } else {
                Text("Assistant message unavailable")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(turn.status == .failed ? Color.red.opacity(0.10) : Color.primary.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func messageText(_ id: UUID) -> String {
        messages.first(where: { $0.id == id })?.text ?? "Unavailable"
    }
}

private struct ContextTraceRow: View {
    let trace: PersistedContextTrace
    let messages: [RunMessage]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(trace.policyName)
                .font(.caption.weight(.semibold))
            if let messageLimit = trace.messageLimit {
                Text("Budget: last \(messageLimit) messages")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else {
                Text("Budget unavailable")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            ContextMessageList(title: "Included", ids: trace.includedMessageIDs, emptyText: "No messages were included.", messages: messages)
            ContextMessageList(title: "Excluded", ids: trace.excludedMessageIDs, emptyText: "No messages were excluded.", messages: messages)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color.primary.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct ContextMessageList: View {
    let title: String
    let ids: [UUID]
    let emptyText: String
    let messages: [RunMessage]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            if ids.isEmpty {
                Text(emptyText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(ids, id: \.self) { id in
                    Text(summary(for: id))
                        .font(.caption)
                        .textSelection(.enabled)
                }
            }
        }
    }

    private func summary(for id: UUID) -> String {
        guard let message = messages.first(where: { $0.id == id }) else {
            return "Unavailable message \(id.uuidString.prefix(8))"
        }
        return "\(message.role.rawValue): \(message.text)"
    }
}

private struct UnavailableRow: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(Color.primary.opacity(0.04))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct MessageBubble: View {
    let message: ChatMessageState

    private var isUser: Bool {
        message.role == .user
    }

    var body: some View {
        HStack(alignment: .bottom) {
            if isUser {
                Spacer(minLength: 72)
            }

            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 6) {
                    Image(systemName: isUser ? "person.crop.circle.fill" : "hammer.circle.fill")
                        .foregroundStyle(isUser ? Color.accentColor : Color.secondary)
                        .accessibilityHidden(true)
                    Text(isUser ? "You" : "Assistant")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    if message.isStreaming {
                        Text("Streaming")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.orange)
                    }
                }

                Text(message.text + (message.isStreaming ? " ▌" : ""))
                    .font(.body)
                    .foregroundStyle(.primary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 13)
            .padding(.vertical, 11)
            .frame(maxWidth: 520, alignment: .leading)
            .background(background)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(border, lineWidth: 1)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(isUser ? "You" : "Assistant"): \(message.text)")

            if !isUser {
                Spacer(minLength: 72)
            }
        }
        .frame(maxWidth: .infinity, alignment: isUser ? .trailing : .leading)
    }

    private var background: Color {
        isUser ? Color.accentColor.opacity(0.13) : Color(nsColor: .controlBackgroundColor)
    }

    private var border: Color {
        isUser ? Color.accentColor.opacity(0.18) : Color.primary.opacity(0.08)
    }
}

@MainActor
public final class ChatPageInteractor: BaseInteractor<ChatPageState, ChatPageAction> {
    private let createRun: CreateRunUseCase
    private let streamUserMessage: StreamUserMessageUseCase
    private let loadProviderSettings: LoadProviderSettingsUseCase?
    private let saveProviderSettings: SaveProviderSettingsUseCase?
    private let clearProviderSettings: ClearProviderSettingsUseCase?
    private let validateProviderSettings: ValidateProviderSettingsUseCase?
    private let listSessions: ListSessionsUseCase?
    private let loadSession: LoadSessionUseCase?
    private let createSession: CreateSessionUseCase?
    private let inspectRun: InspectRunUseCase?
    private let router: Router<AnyRouteInput, AnyModalInput>
    private var didLoadInitialState = false

    public init(
        input: ChatRouteInput,
        createRun: CreateRunUseCase,
        streamUserMessage: StreamUserMessageUseCase,
        loadProviderSettings: LoadProviderSettingsUseCase? = nil,
        saveProviderSettings: SaveProviderSettingsUseCase? = nil,
        clearProviderSettings: ClearProviderSettingsUseCase? = nil,
        validateProviderSettings: ValidateProviderSettingsUseCase? = nil,
        listSessions: ListSessionsUseCase? = nil,
        loadSession: LoadSessionUseCase? = nil,
        createSession: CreateSessionUseCase? = nil,
        inspectRun: InspectRunUseCase? = nil,
        router: Router<AnyRouteInput, AnyModalInput>
    ) {
        self.createRun = createRun
        self.streamUserMessage = streamUserMessage
        self.loadProviderSettings = loadProviderSettings
        self.saveProviderSettings = saveProviderSettings
        self.clearProviderSettings = clearProviderSettings
        self.validateProviderSettings = validateProviderSettings
        self.listSessions = listSessions
        self.loadSession = loadSession
        self.createSession = createSession
        self.inspectRun = inspectRun
        self.router = router
        super.init(initialState: ChatPageState(runID: input.runID))
    }

    public override func onAppear() {
        guard !didLoadInitialState else { return }
        didLoadInitialState = true
        Task { [weak self] in
            await self?.loadInitialState()
        }
    }

    public override func handleAction(_ action: ChatPageAction) async {
        switch action {
        case .changeDraft(let text):
            handleChangeDraft(text)
        case .tapSend:
            await handleTapSend()
        case .tapNewChat:
            await handleTapNewChat()
        case .tapChat(let id):
            await handleTapChat(id)
        case .tapSettings:
            await handleTapSettings()
        case .dismissSettings:
            setState { $0.providerSettings.isPresented = false }
        case .changeProviderBaseURL(let value):
            setState {
                $0.providerSettings.baseURLString = value
                $0.providerSettings.validation = .idle
            }
        case .changeProviderAPIKey(let value):
            setState {
                $0.providerSettings.apiKeyReplacement = value
                $0.providerSettings.validation = .idle
            }
        case .changeProviderModel(let value):
            setState {
                $0.providerSettings.model = value
                $0.providerSettings.validation = .idle
            }
        case .validateProviderSettings:
            await handleValidateProviderSettings()
        case .saveProviderSettings:
            await handleSaveProviderSettings()
        case .clearProviderSettings:
            await handleClearProviderSettings()
        case .tapInspector:
            await handleTapInspector()
        case .dismissInspector:
            setState { $0.inspector.isPresented = false }
        }
    }

    private func loadInitialState() async {
        await loadProviderSettingsIntoState(present: false)
        await refreshSessions()
        if let runID = state.runID {
            await handleOpenSession(runID, force: true)
        }
    }

    private func handleChangeDraft(_ text: String) {
        setState { state in
            state.draftText = text
        }
    }

    private func handleTapSend() async {
        guard !state.isRunning else { return }
        let text = state.draftText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        setState { state in
            state.draftText = ""
            state.isRunning = true
            state.errorMessage = nil
        }

        var submittedRunID: UUID?
        do {
            let runID = try await ensureRun()
            submittedRunID = runID
            let stream = try await streamUserMessage.streamUserMessage(runID: runID, text: text)
            for try await event in stream {
                apply(event, visibleRunID: runID)
            }
            await refreshSessions()
        } catch is CancellationError {
            setState { state in
                if let submittedRunID, state.runID != submittedRunID { return }
                state.isRunning = false
                markStreamingAssistantComplete(in: &state)
            }
        } catch {
            setState { state in
                if let submittedRunID, state.runID != submittedRunID { return }
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
        if let createSession {
            let session = try await createSession.createSession(title: nil)
            setState { state in
                state.runID = session.id
            }
            await refreshSessions()
            return session.id
        }
        let runID = await createRun.createRun()
        setState { state in
            state.runID = runID
        }
        return runID
    }

    private func apply(_ event: RuntimeEvent, visibleRunID: UUID) {
        setState { state in
            guard state.runID == visibleRunID, event.header.runID == visibleRunID else {
                return
            }
            switch event {
            case .runCreated(_, let runID):
                state.runID = runID
            case .userMessageAccepted(_, let messageID, let text):
                state.messages.append(
                    ChatMessageState(id: messageID, role: .user, text: text)
                )
            case .contextPrepared(_, _):
                break
            case .providerRequestPrepared(_, _, _, _):
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

    private func handleTapNewChat() async {
        do {
            let session = try await createSession?.createSession(title: nil)
            setState { state in
                state.runID = session?.id
                state.messages = []
                state.draftText = ""
                state.errorMessage = nil
                state.persistenceErrorMessage = nil
                state.inspector = RunInspectorPanelState()
            }
            await refreshSessions()
        } catch {
            setPersistenceError(error)
        }
    }

    private func handleTapChat(_ id: UUID) async {
        await handleOpenSession(id)
    }

    private func handleOpenSession(_ id: UUID, force: Bool = false) async {
        guard force || state.runID != id else { return }
        guard let loadSession else { return }
        do {
            let session = try await loadSession.loadSession(id: id)
            setState { state in
                state.runID = session.id
                state.messages = session.messages.compactMap(ChatMessageState.init(message:))
                state.draftText = ""
                state.isRunning = false
                state.errorMessage = nil
                state.persistenceErrorMessage = nil
                state.inspector = RunInspectorPanelState()
            }
        } catch {
            setPersistenceError(error)
        }
    }

    private func handleTapSettings() async {
        await loadProviderSettingsIntoState(present: true)
    }

    private func loadProviderSettingsIntoState(present: Bool) async {
        do {
            let summary = try await loadProviderSettings?.loadProviderSettings()
            setState { state in
                state.providerSettings.isPresented = present || state.providerSettings.isPresented
                state.providerSettings.baseURLString = summary?.baseURLString ?? state.providerSettings.baseURLString
                state.providerSettings.model = summary?.model ?? state.providerSettings.model
                state.providerSettings.apiKeyReplacement = ""
                state.providerSettings.hasSavedAPIKey = summary?.hasSavedAPIKey ?? false
                state.providerSettings.validatedAt = summary?.validatedAt
                state.providerSettings.validation = .idle
                state.providerSettings.errorMessage = nil
            }
        } catch {
            setState { state in
                state.providerSettings.isPresented = present || state.providerSettings.isPresented
                state.providerSettings.errorMessage = String(describing: error)
            }
        }
    }

    private func handleValidateProviderSettings() async {
        guard let validateProviderSettings else { return }
        let draft = currentProviderDraft()
        setState {
            $0.providerSettings.validation = .validating
            $0.providerSettings.errorMessage = nil
        }
        let result = await validateProviderSettings.validateProviderSettings(draft)
        setState { state in
            switch result {
            case .success:
                state.providerSettings.validation = .success("Provider validated.")
            case .failure(let message):
                state.providerSettings.validation = .failure(message)
            }
        }
    }

    private func handleSaveProviderSettings() async {
        guard let saveProviderSettings else { return }
        let draft = currentProviderDraft()
        setState {
            $0.providerSettings.isSaving = true
            $0.providerSettings.errorMessage = nil
        }

        let validation = await validateProviderSettings?.validateProviderSettings(draft) ?? .success
        guard validation == .success else {
            setState { state in
                if case .failure(let message) = validation {
                    state.providerSettings.validation = .failure(message)
                }
                state.providerSettings.isSaving = false
            }
            return
        }

        do {
            let validatedAt = Date()
            try await saveProviderSettings.saveProviderSettings(draft, validatedAt: validatedAt)
            setState { state in
                state.providerSettings.hasSavedAPIKey = state.providerSettings.apiKeyReplacement.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? state.providerSettings.hasSavedAPIKey
                    : true
                state.providerSettings.apiKeyReplacement = ""
                state.providerSettings.validatedAt = validatedAt
                state.providerSettings.validation = .success("Provider settings saved.")
                state.providerSettings.isSaving = false
                state.providerSettings.isPresented = false
            }
        } catch {
            setState { state in
                state.providerSettings.errorMessage = String(describing: error)
                state.providerSettings.isSaving = false
            }
        }
    }

    private func handleClearProviderSettings() async {
        guard let clearProviderSettings else { return }
        do {
            try await clearProviderSettings.clearProviderSettings()
            setState { state in
                state.providerSettings = ProviderSettingsPanelState(isPresented: true)
            }
        } catch {
            setState { $0.providerSettings.errorMessage = String(describing: error) }
        }
    }

    private func handleTapInspector() async {
        guard let runID = state.runID, let inspectRun else { return }
        setState {
            $0.inspector.isPresented = true
            $0.inspector.isLoading = true
            $0.inspector.errorMessage = nil
        }
        do {
            let inspection = try await inspectRun.inspectRun(sessionID: runID)
            setState {
                $0.inspector.inspection = inspection
                $0.inspector.isLoading = false
            }
        } catch {
            setState {
                $0.inspector.errorMessage = String(describing: error)
                $0.inspector.isLoading = false
            }
        }
    }

    private func refreshSessions() async {
        guard let listSessions else { return }
        setState { $0.isLoadingSessions = true }
        do {
            let summaries = try await listSessions.listSessions()
            setState { state in
                state.sessions = summaries.map(ChatSessionSummaryState.init(summary:))
                state.persistenceErrorMessage = nil
                state.isLoadingSessions = false
            }
        } catch {
            setState {
                $0.persistenceErrorMessage = String(describing: error)
                $0.isLoadingSessions = false
            }
        }
    }

    private func setPersistenceError(_ error: Error) {
        setState { $0.persistenceErrorMessage = String(describing: error) }
    }

    private func currentProviderDraft() -> ProviderSettingsDraft {
        ProviderSettingsDraft(
            baseURLString: state.providerSettings.baseURLString,
            apiKey: state.providerSettings.apiKeyReplacement.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            model: state.providerSettings.model
        )
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
                let loadProviderSettings = try? context.dependency(LoadProviderSettingsUseCase.self)
                let saveProviderSettings = try? context.dependency(SaveProviderSettingsUseCase.self)
                let clearProviderSettings = try? context.dependency(ClearProviderSettingsUseCase.self)
                let validateProviderSettings = try? context.dependency(ValidateProviderSettingsUseCase.self)
                let listSessions = try? context.dependency(ListSessionsUseCase.self)
                let loadSession = try? context.dependency(LoadSessionUseCase.self)
                let createSession = try? context.dependency(CreateSessionUseCase.self)
                let inspectRun = try? context.dependency(InspectRunUseCase.self)
                return AnyView(
                    Page(
                        interactor: ChatPageInteractor(
                            input: input,
                            createRun: createRun,
                            streamUserMessage: streamUserMessage,
                            loadProviderSettings: loadProviderSettings,
                            saveProviderSettings: saveProviderSettings,
                            clearProviderSettings: clearProviderSettings,
                            validateProviderSettings: validateProviderSettings,
                            listSessions: listSessions,
                            loadSession: loadSession,
                            createSession: createSession,
                            inspectRun: inspectRun,
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
            build: { _, context in
                let loadProviderSettings = try? context.dependency(LoadProviderSettingsUseCase.self)
                let saveProviderSettings = try? context.dependency(SaveProviderSettingsUseCase.self)
                let clearProviderSettings = try? context.dependency(ClearProviderSettingsUseCase.self)
                let validateProviderSettings = try? context.dependency(ValidateProviderSettingsUseCase.self)
                let createRun = try context.dependency(CreateRunUseCase.self)
                let streamUserMessage = try context.dependency(StreamUserMessageUseCase.self)
                return AnyView(
                    Page(
                        interactor: ChatPageInteractor(
                            input: ChatRouteInput(runID: nil),
                            createRun: createRun,
                            streamUserMessage: streamUserMessage,
                            loadProviderSettings: loadProviderSettings,
                            saveProviderSettings: saveProviderSettings,
                            clearProviderSettings: clearProviderSettings,
                            validateProviderSettings: validateProviderSettings,
                            router: context.router
                        ),
                        view: { state, handle in
                            ProviderSettingsSheet(state: state.providerSettings, handle: handle)
                                .task { handle(.tapSettings) }
                        }
                    )
                )
            }
        )
    }
}
