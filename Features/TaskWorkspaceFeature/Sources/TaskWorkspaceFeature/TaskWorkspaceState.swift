import Anvil
import Foundation
import HephaestusDomain
import HephaestusKernel
import HephaestusObservation
import HephaestusRuntime
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
