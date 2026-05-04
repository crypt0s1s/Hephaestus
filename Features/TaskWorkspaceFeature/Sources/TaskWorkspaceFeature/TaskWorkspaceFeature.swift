import Anvil
import Foundation
import HephaestusDomain
import HephaestusKernel
import HephaestusObservation
import HephaestusRuntime
import SwiftUI
import TaskWorkspaceContracts

public struct ConversationMessageState: Equatable, Identifiable, Sendable {
    public enum Role: Equatable, Sendable {
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

public struct TaskWorkspaceError: Error, Equatable, Sendable, CustomStringConvertible {
    public let description: String

    public init(_ description: String) {
        self.description = description
    }

    public init(_ error: Error) {
        self.init(String(describing: error))
    }
}

public struct TaskWorkspaceState: Equatable {
    public var workspaceSnapshot: TaskWorkspaceSnapshot?
    public var runID: UUID?
    public var selectedSnapshot: TaskSessionSnapshot?
    public var messages: [ConversationMessageState]
    public var draftText: String
    public var isRunning: Bool
    public var errorMessage: String?
    public var sessions: StoreState<[TaskSummaryState], TaskWorkspaceError>
    public var providerSettings: ProviderSettingsPanelState
    public var inspector: RunInspectorPanelState

    public init(
        workspaceSnapshot: TaskWorkspaceSnapshot? = nil,
        runID: UUID? = nil,
        selectedSnapshot: TaskSessionSnapshot? = nil,
        messages: [ConversationMessageState] = [],
        draftText: String = "",
        isRunning: Bool = false,
        errorMessage: String? = nil,
        sessions: [TaskSummaryState] = [],
        isLoadingSessions: Bool = false,
        persistenceErrorMessage: String? = nil,
        providerSettings: ProviderSettingsPanelState = ProviderSettingsPanelState(),
        inspector: RunInspectorPanelState = RunInspectorPanelState()
    ) {
        self.workspaceSnapshot = workspaceSnapshot
        self.runID = runID
        self.selectedSnapshot = selectedSnapshot
        self.messages = messages
        self.draftText = draftText
        self.isRunning = isRunning
        self.errorMessage = errorMessage
        if let persistenceErrorMessage {
            self.sessions = .error(TaskWorkspaceError(persistenceErrorMessage))
        } else if isLoadingSessions {
            self.sessions = .loading(placeholder: sessions)
        } else {
            self.sessions = .loaded(sessions)
        }
        self.providerSettings = providerSettings
        self.inspector = inspector
    }

    public var sessionSummaries: [TaskSummaryState] {
        sessions.data ?? []
    }

    public var isLoadingSessions: Bool {
        sessions.isLoading
    }

    public var persistenceErrorMessage: String? {
        sessions.failure?.description
    }
}

public enum TaskWorkspaceAction: Equatable {
    case changeDraft(String)
    case tapSend
    case tapNewTask
    case tapTask(UUID)
    case tapCancel
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

public struct TaskSummaryState: Equatable, Identifiable, Sendable {
    public let id: UUID
    public var title: String
    public var updatedAt: Date
    public var messageCount: Int
    public var task: AgentTask

    public init(
        id: UUID,
        title: String,
        updatedAt: Date,
        messageCount: Int,
        task: AgentTask? = nil
    ) {
        self.id = id
        self.title = title
        self.updatedAt = updatedAt
        self.messageCount = messageCount
        self.task = task ?? AgentTask(
            id: TaskID(rawValue: id),
            projectID: DefaultProject.id,
            title: title,
            status: messageCount == 0 ? .draft : .completed,
            createdAt: updatedAt,
            updatedAt: updatedAt,
            activeRunID: id
        )
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
    public var loadState: StoreState<RunInspectionSnapshot?, TaskWorkspaceError>

    public init(
        isPresented: Bool = false,
        isLoading: Bool = false,
        inspection: RunInspectionSnapshot? = nil,
        errorMessage: String? = nil
    ) {
        self.isPresented = isPresented
        if let errorMessage {
            loadState = .error(TaskWorkspaceError(errorMessage))
        } else if isLoading {
            loadState = .loading(placeholder: inspection)
        } else {
            loadState = .loaded(inspection)
        }
    }

    public var isLoading: Bool {
        loadState.isLoading
    }

    public var inspection: RunInspectionSnapshot? {
        switch loadState {
        case .loading(let placeholder):
            return placeholder ?? nil
        case .loaded(let inspection):
            return inspection
        case .error:
            return nil
        }
    }

    public var errorMessage: String? {
        loadState.failure?.description
    }
}

extension TaskSummaryState {
    init(summary: PersistedSessionSummary) {
        self.init(
            id: summary.id,
            title: summary.title,
            updatedAt: summary.updatedAt,
            messageCount: summary.messageCount,
            task: AgentTask(sessionSummary: summary)
        )
    }
}

extension ConversationMessageState {
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

private enum ConversationScrollTarget {
    static let bottom = "conversation-scroll-bottom"
    static let coordinateSpace = "conversation-scroll-coordinate-space"
    static let pinnedThreshold: CGFloat = 44
}

private enum TaskWorkspaceAccessibilityID {
    static let historyList = "task.list"
    static let historyEmptyState = "task.list.emptyState"
    static let newTaskButton = "task.new"
    static let settingsButton = "task.provider.settings"
    static let inspectorButton = "task.inspector.open"
    static let transcript = "conversation.transcript"
    static let emptyState = "task.emptyState"
    static let messageInput = "conversation.messageInput"
    static let sendButton = "conversation.sendButton"
    static let runningStatus = "task.runningStatus"
    static let errorBanner = "task.errorBanner"
    static let persistenceError = "task.persistence.error"
    static let providerBaseURL = "provider.baseURL"
    static let providerAPIKey = "provider.apiKey"
    static let providerModel = "provider.model"
    static let providerValidate = "provider.validate"
    static let providerSave = "provider.save"
    static let providerClear = "provider.clear"
    static let inspectorPanel = "inspector.panel"
    static let inspectorTimeline = "inspector.timeline"
}

public struct TaskWorkspacePage: View {
    public let state: TaskWorkspaceState
    public let handle: (TaskWorkspaceAction) -> Void
    @State private var isTranscriptPinnedToBottom = true

    private var trimmedDraft: String {
        state.draftText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canSend: Bool {
        !state.isRunning && !trimmedDraft.isEmpty
    }

    public init(state: TaskWorkspaceState, handle: @escaping (TaskWorkspaceAction) -> Void) {
        self.state = state
        self.handle = handle
    }

    public var body: some View {
        HStack(spacing: 0) {
            HistorySidebar(
                sessions: state.sessionSummaries,
                selectedRunID: state.runID,
                isLoading: state.isLoadingSessions,
                errorMessage: state.persistenceErrorMessage,
                handle: handle
            )
            .frame(width: 250)

            Divider()

            VStack(spacing: 0) {
                TaskHeader(
                    isRunning: state.isRunning,
                    runID: state.runID,
                    canInspect: state.runID != nil,
                    canCancel: state.isRunning,
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
                            EmptyTaskState()
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
                            .id(ConversationScrollTarget.bottom)
                            .background {
                                GeometryReader { bottomMarker in
                                    Color.clear.preference(
                                        key: ConversationBottomDistancePreferenceKey.self,
                                        value: bottomMarker.frame(in: .named(ConversationScrollTarget.coordinateSpace)).maxY
                                            - viewport.size.height
                                    )
                                }
                            }
                    }
                    .padding(.horizontal, 22)
                    .padding(.vertical, 20)
                }
                .coordinateSpace(name: ConversationScrollTarget.coordinateSpace)
                .accessibilityLabel("Conversation transcript")
                .accessibilityIdentifier(TaskWorkspaceAccessibilityID.transcript)
                .onPreferenceChange(ConversationBottomDistancePreferenceKey.self) { distanceFromBottom in
                    isTranscriptPinnedToBottom = distanceFromBottom <= ConversationScrollTarget.pinnedThreshold
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
        proxy.scrollTo(ConversationScrollTarget.bottom, anchor: .bottom)
    }

    private var composer: some View {
        HStack(alignment: .center, spacing: 10) {
            TextField("Add task instruction", text: Binding(
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
            .accessibilityIdentifier(TaskWorkspaceAccessibilityID.messageInput)

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
            .accessibilityIdentifier(TaskWorkspaceAccessibilityID.sendButton)
        }
    }
}

private struct ConversationBottomDistancePreferenceKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

private struct HistorySidebar: View {
    let sessions: [TaskSummaryState]
    let selectedRunID: UUID?
    let isLoading: Bool
    let errorMessage: String?
    let handle: (TaskWorkspaceAction) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Tasks")
                    .font(.headline)
                Spacer()
                Button {
                    handle(.tapNewTask)
                } label: {
                    Label("New task", systemImage: "square.and.pencil")
                        .labelStyle(.iconOnly)
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.borderless)
                .help("New task")
                .accessibilityIdentifier(TaskWorkspaceAccessibilityID.newTaskButton)
            }

            if let errorMessage {
                ErrorBanner(message: errorMessage)
                    .accessibilityIdentifier(TaskWorkspaceAccessibilityID.persistenceError)
            }

            if isLoading && sessions.isEmpty {
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
                    Text("No tasks")
                        .font(.callout.weight(.semibold))
                    Text("Start a task and it will appear here.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 18)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier(TaskWorkspaceAccessibilityID.historyEmptyState)
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 6) {
                        if isLoading {
                            HStack(spacing: 8) {
                                ProgressView()
                                    .controlSize(.small)
                                Text("Refreshing")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                        }

                        ForEach(sessions) { session in
                            let isSelected = selectedRunID == session.id
                            Button {
                                guard !isSelected else { return }
                                handle(.tapTask(session.id))
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
                .accessibilityIdentifier(TaskWorkspaceAccessibilityID.historyList)
            }
        }
        .padding(14)
        .background(Color(nsColor: .controlBackgroundColor))
    }
}

private struct HistoryRow: View {
    let session: TaskSummaryState
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

private struct TaskHeader: View {
    let isRunning: Bool
    let runID: UUID?
    let canInspect: Bool
    let canCancel: Bool
    let handle: (TaskWorkspaceAction) -> Void

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
                    Text("Task Workspace")
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
            .accessibilityIdentifier(TaskWorkspaceAccessibilityID.inspectorButton)

            Button {
                handle(.tapCancel)
            } label: {
                Label("Cancel response", systemImage: "stop.circle")
                    .labelStyle(.iconOnly)
                    .frame(width: 30, height: 30)
            }
            .buttonStyle(.borderless)
            .disabled(!canCancel)
            .help("Cancel response")
            .accessibilityLabel("Cancel response")

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
            .accessibilityIdentifier(TaskWorkspaceAccessibilityID.settingsButton)

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
            .accessibilityIdentifier(isRunning ? TaskWorkspaceAccessibilityID.runningStatus : "task.readyStatus")
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .background(.bar)
    }

    private var runSubtitle: String {
        guard let runID else {
            return "New local run"
        }
        return "Foundry task \(runID.uuidString.prefix(8))"
    }
}

private struct EmptyTaskState: View {
    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "sparkles")
                .font(.system(size: 30, weight: .medium))
                .foregroundStyle(Color.accentColor)
                .accessibilityHidden(true)

            VStack(spacing: 5) {
                Text("Start a focused task")
                    .font(.title3.weight(.semibold))
                Text("Describe the task, then inspect the run as it moves through the workspace.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 420)
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(TaskWorkspaceAccessibilityID.emptyState)
    }
}

private struct RunningStatus: View {
    var body: some View {
        HStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)
            Text("Foundry is running")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.leading, 6)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(TaskWorkspaceAccessibilityID.runningStatus)
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
        .accessibilityLabel("Task error: \(message)")
        .accessibilityIdentifier(TaskWorkspaceAccessibilityID.errorBanner)
    }
}

private struct ProviderSettingsSheet: View {
    let state: ProviderSettingsPanelState
    let handle: (TaskWorkspaceAction) -> Void

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
                    .accessibilityIdentifier(TaskWorkspaceAccessibilityID.providerBaseURL)
                }

                LabeledContent("API key") {
                    SecureField(state.hasSavedAPIKey ? "Leave blank to keep saved key" : "Required", text: Binding(
                        get: { state.apiKeyReplacement },
                        set: { handle(.changeProviderAPIKey($0)) }
                    ))
                    .textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier(TaskWorkspaceAccessibilityID.providerAPIKey)
                }

                LabeledContent("Model") {
                    TextField("gpt-4.1-mini", text: Binding(
                        get: { state.model },
                        set: { handle(.changeProviderModel($0)) }
                    ))
                    .textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier(TaskWorkspaceAccessibilityID.providerModel)
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
                .accessibilityIdentifier(TaskWorkspaceAccessibilityID.providerClear)

                Spacer()

                Button("Validate") {
                    handle(.validateProviderSettings)
                }
                .disabled(!canSubmit)
                .accessibilityIdentifier(TaskWorkspaceAccessibilityID.providerValidate)

                Button("Save") {
                    handle(.saveProviderSettings)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canSubmit)
                .accessibilityIdentifier(TaskWorkspaceAccessibilityID.providerSave)
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
        .accessibilityIdentifier(TaskWorkspaceAccessibilityID.inspectorPanel)
    }
}

private struct RunInspectionContent: View {
    let inspection: RunInspectionSnapshot

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                InspectorSection(title: "Timeline") {
                    if inspection.events.isEmpty {
                        UnavailableRow(text: "No runtime events are available.")
                    } else {
                        ForEach(inspection.events) { event in
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
                .accessibilityIdentifier(TaskWorkspaceAccessibilityID.inspectorTimeline)

                InspectorSection(title: "Turns") {
                    if inspection.turns.isEmpty {
                        UnavailableRow(text: "No turns are available.")
                    } else {
                        ForEach(inspection.turns) { turn in
                            TurnInspectionRow(turn: turn)
                        }
                    }
                }

                InspectorSection(title: "Provider") {
                    if inspection.providerRequests.isEmpty {
                        UnavailableRow(text: "Provider request details are unavailable.")
                    } else {
                        ForEach(inspection.providerRequests) { request in
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
                    if inspection.contextTraces.isEmpty {
                        UnavailableRow(text: "Context details are unavailable.")
                    } else {
                        ForEach(inspection.contextTraces) { trace in
                            ContextTraceRow(trace: trace)
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
    let turn: ObservedTurn

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Turn \(turn.id.uuidString.prefix(8)) - \(turn.status.rawValue)")
                .font(.caption.weight(.semibold))
            Text("User message: \(shortID(turn.userMessageID))")
                .font(.caption)
                .textSelection(.enabled)
            if let assistantMessageID = turn.assistantMessageID {
                Text("Assistant message: \(assistantMessageID.uuidString.prefix(8))")
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

    private func shortID(_ id: UUID?) -> String {
        id.map { String($0.uuidString.prefix(8)) } ?? "unavailable"
    }
}

private struct ContextTraceRow: View {
    let trace: ObservedContextTrace

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
            ContextMessageList(title: "Included", ids: trace.includedMessageIDs, emptyText: "No messages were included.")
            ContextMessageList(title: "Excluded", ids: trace.excludedMessageIDs, emptyText: "No messages were excluded.")
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
                    Text("Message \(id.uuidString.prefix(8))")
                        .font(.caption)
                        .textSelection(.enabled)
                }
            }
        }
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
    let message: ConversationMessageState

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
public final class TaskWorkspaceInteractor: BaseInteractor<TaskWorkspaceState, TaskWorkspaceAction> {
    private let workspace: TaskWorkspaceService
    private let initialRunID: UUID?
    private let loadProviderSettings: LoadProviderSettingsUseCase?
    private let saveProviderSettings: SaveProviderSettingsUseCase?
    private let clearProviderSettings: ClearProviderSettingsUseCase?
    private let validateProviderSettings: ValidateProviderSettingsUseCase?
    private let loadRunInspection: LoadRunInspectionUseCase?
    private let subscribeToWorkspace: Bool
    private var didLoadInitialState = false
    private var workspaceTaskID: UUID?
    private var lifecycleTaskID: UUID?

    public init(
        input: TaskWorkspaceRouteInput,
        workspace: TaskWorkspaceService,
        loadProviderSettings: LoadProviderSettingsUseCase? = nil,
        saveProviderSettings: SaveProviderSettingsUseCase? = nil,
        clearProviderSettings: ClearProviderSettingsUseCase? = nil,
        validateProviderSettings: ValidateProviderSettingsUseCase? = nil,
        loadRunInspection: LoadRunInspectionUseCase? = nil,
        subscribeToWorkspace: Bool = true
    ) {
        self.workspace = workspace
        self.initialRunID = input.taskID
        self.loadProviderSettings = loadProviderSettings
        self.saveProviderSettings = saveProviderSettings
        self.clearProviderSettings = clearProviderSettings
        self.validateProviderSettings = validateProviderSettings
        self.loadRunInspection = loadRunInspection
        self.subscribeToWorkspace = subscribeToWorkspace
        super.init(initialState: TaskWorkspaceState(runID: input.taskID))
    }

    public override func onAppear() {
        cancelPageTask(lifecycleTaskID)
        lifecycleTaskID = nil
        if didLoadInitialState {
            if subscribeToWorkspace, workspaceTaskID == nil {
                attachToWorkspace()
            }
            return
        }

        didLoadInitialState = true
        lifecycleTaskID = runPageTask { [weak self] in
            await self?.loadInitialState()
        }
    }

    public override func onDisappear() {
        cancelPageTask(lifecycleTaskID)
        lifecycleTaskID = nil
        detachWorkspace()
        super.onDisappear()
    }

    public override func handleAction(_ action: TaskWorkspaceAction) async {
        switch action {
        case .changeDraft(let text):
            handleChangeDraft(text)
        case .tapSend:
            await handleTapSend()
        case .tapNewTask:
            await handleTapNewTask()
        case .tapTask(let id):
            await handleTapTask(id)
        case .tapCancel:
            handleTapCancel()
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
        guard subscribeToWorkspace else { return }
        await workspace.refreshSummaries()
        if let initialRunID {
            await workspace.selectTask(initialRunID, force: true)
        }
        if workspaceTaskID == nil {
            attachToWorkspace()
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

        if let runID = state.runID, workspace.snapshot.selectedTaskID != runID {
            let selected = await workspace.selectTask(runID, force: true)
            apply(workspace.snapshot)
            guard selected else {
                return
            }
        }

        setState { state in
            state.draftText = ""
            state.isRunning = true
            state.errorMessage = nil
        }

        let accepted = await workspace.sendMessage(text)
        apply(workspace.snapshot)
        if !accepted {
            setState { $0.isRunning = false }
        }
    }

    private func handleTapNewTask() async {
        let changed = await workspace.createNewTask(title: nil)
        apply(workspace.snapshot)
        if changed {
            setState {
                $0.draftText = ""
                $0.inspector = RunInspectorPanelState()
            }
        }
    }

    private func handleTapTask(_ id: UUID) async {
        guard state.runID != id else { return }
        let changed = await workspace.selectTask(id)
        apply(workspace.snapshot)
        if changed {
            setState {
                $0.draftText = ""
                $0.inspector = RunInspectorPanelState()
            }
        }
    }

    private func handleTapCancel() {
        workspace.cancelSelectedTurn()
        apply(workspace.snapshot)
    }

    private func attachToWorkspace() {
        cancelPageTask(workspaceTaskID)
        workspaceTaskID = runPageTask { [weak self] in
            guard let self else { return }
            for await snapshot in workspace.subscribeSnapshots() {
                apply(snapshot)
            }
        }
    }

    private func detachWorkspace() {
        cancelPageTask(workspaceTaskID)
        workspaceTaskID = nil
    }

    private func apply(_ snapshot: TaskWorkspaceSnapshot) {
        setState { state in
            if let currentSnapshot = state.workspaceSnapshot,
               snapshot.revision < currentSnapshot.revision {
                return
            }
            state.workspaceSnapshot = snapshot
            if let selectedTaskID = snapshot.selectedTaskID {
                state.runID = selectedTaskID
                state.selectedSnapshot = snapshot.selectedTask
                state.messages = snapshot.selectedTask?.messages ?? []
                state.isRunning = snapshot.selectedTask?.isRunning ?? false
                state.errorMessage = snapshot.selectedTask?.errorMessage ?? snapshot.selectionError?.description
            } else if state.runID == nil, !state.isRunning {
                state.selectedSnapshot = nil
                state.messages = []
                state.isRunning = false
                state.errorMessage = snapshot.selectionError?.description
            } else if let selectionError = snapshot.selectionError {
                state.errorMessage = selectionError.description
            }
            state.sessions = snapshot.sessions.mapError(TaskWorkspaceError.init)
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
        guard let runID = state.runID, let loadRunInspection else { return }
        setState {
            $0.inspector.isPresented = true
            $0.inspector.loadState = .loading(placeholder: $0.inspector.inspection)
        }
        do {
            let inspection = try await loadRunInspection.loadRunInspection(runID: runID)
            setState {
                $0.inspector.loadState = .loaded(inspection)
            }
        } catch {
            setState {
                $0.inspector.loadState = .error(TaskWorkspaceError(error))
            }
        }
    }

    private func currentProviderDraft() -> ProviderSettingsDraft {
        ProviderSettingsDraft(
            baseURLString: state.providerSettings.baseURLString,
            apiKey: state.providerSettings.apiKeyReplacement.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            model: state.providerSettings.model
        )
    }
}

public enum TaskWorkspaceRoutes {
    public static var registration: RouteRegistration {
        RouteRegistration(
            routeID: TaskWorkspaceRouteInput.routeID,
            version: TaskWorkspaceRouteInput.version,
            decodeDeepLink: { url in
                guard url.host == "route",
                      url.pathComponents.filter({ $0 != "/" }).first == TaskWorkspaceRouteInput.routeID
                else { return nil }
                let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
                let taskIDValue = components?.queryItems?.first(where: { $0.name == "taskID" })?.value
                let taskID: UUID?
                if let taskIDValue {
                    guard let parsedTaskID = UUID(uuidString: taskIDValue) else {
                        return nil
                    }
                    taskID = parsedTaskID
                } else {
                    taskID = nil
                }
                return try AnyRouteInput(TaskWorkspaceRouteInput(taskID: taskID))
            },
            build: { anyInput, context in
                let input = try anyInput.decode(TaskWorkspaceRouteInput.self)
                return try buildTaskWorkspace(
                    input: input,
                    context: context
                )
            }
        )
    }

    public static var settingsModalRegistration: ModalRegistration {
        ModalRegistration(
            modalID: TaskWorkspaceSettingsModalInput.modalID,
            version: TaskWorkspaceSettingsModalInput.version,
            decodeDeepLink: { url in
                guard url.host == "modal",
                      url.pathComponents.filter({ $0 != "/" }).first == TaskWorkspaceSettingsModalInput.modalID
                else { return nil }
                return try AnyModalInput(TaskWorkspaceSettingsModalInput())
            },
            build: { _, context in
                let workspace = try context.dependency(TaskWorkspaceService.self)
                let input = TaskWorkspaceRouteInput(taskID: workspace.snapshot.selectedTaskID)
                return try buildTaskWorkspace(input: input, context: context)
            }
        )
    }

    @MainActor
    private static func buildTaskWorkspace(
        input: TaskWorkspaceRouteInput,
        context: RouteBuildContext
    ) throws -> AnyView {
        let loadProviderSettings = try? context.dependency(LoadProviderSettingsUseCase.self)
        let saveProviderSettings = try? context.dependency(SaveProviderSettingsUseCase.self)
        let clearProviderSettings = try? context.dependency(ClearProviderSettingsUseCase.self)
        let validateProviderSettings = try? context.dependency(ValidateProviderSettingsUseCase.self)
        let loadRunInspection = try? context.dependency(LoadRunInspectionUseCase.self)
        let workspace = try context.dependency(TaskWorkspaceService.self)
        return AnyView(
            Page(
                interactor: TaskWorkspaceInteractor(
                    input: input,
                    workspace: workspace,
                    loadProviderSettings: loadProviderSettings,
                    saveProviderSettings: saveProviderSettings,
                    clearProviderSettings: clearProviderSettings,
                    validateProviderSettings: validateProviderSettings,
                    loadRunInspection: loadRunInspection
                ),
                view: TaskWorkspacePage.init
            )
        )
    }
}
