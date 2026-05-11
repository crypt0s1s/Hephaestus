import Anvil
import Foundation
import HephaestusDomain
import TaskWorkspaceContracts

public struct TaskSessionError: Error, Equatable, Sendable, CustomStringConvertible {
    public let description: String

    public init(_ description: String) {
        self.description = description
    }

    public init(_ error: Error) {
        self.init(String(describing: error))
    }
}

public struct TaskWorkspaceServiceError: Error, Equatable, Sendable, CustomStringConvertible {
    public let description: String

    public init(_ description: String) {
        self.description = description
    }

    public init(_ error: Error) {
        self.init(String(describing: error))
    }
}

public struct TurnProgressState: Equatable, Sendable {
    public var activeTurnID: UUID?
    public var isRunning: Bool

    public init(activeTurnID: UUID? = nil, isRunning: Bool = false) {
        self.activeTurnID = activeTurnID
        self.isRunning = isRunning
    }
}

public struct TaskSessionSnapshot: Equatable, Sendable {
    public var id: UUID
    public var task: AgentTask
    public var title: String
    public var transcript: StoreState<[ConversationMessageState], TaskSessionError>
    public var turnState: StoreState<TurnProgressState, TaskSessionError>
    public var updatedAt: Date

    public init(
        id: UUID,
        title: String,
        task: AgentTask? = nil,
        transcript: StoreState<[ConversationMessageState], TaskSessionError> = .loaded([]),
        turnState: StoreState<TurnProgressState, TaskSessionError> = .loaded(TurnProgressState()),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.task =
            task
            ?? AgentTask(
                id: TaskID(rawValue: id),
                projectID: DefaultProject.id,
                title: title,
                status: .draft,
                createdAt: updatedAt,
                updatedAt: updatedAt,
                activeRunID: id
            )
        self.title = title
        self.transcript = transcript
        self.turnState = turnState
        self.updatedAt = updatedAt
    }

    public var messages: [ConversationMessageState] {
        transcript.data ?? []
    }

    public var isRunning: Bool {
        switch turnState {
        case .loading:
            true
        case .loaded(let progress):
            progress.isRunning
        case .error:
            false
        }
    }

    public var errorMessage: String? {
        transcript.failure?.description ?? turnState.failure?.description
    }
}

public struct TaskWorkspaceSnapshot: Equatable, Sendable {
    public var revision: Int
    public var selectedTaskID: UUID?
    public var selectedTask: TaskSessionSnapshot?
    public var selectionError: TaskWorkspaceServiceError?
    public var sessions: StoreState<[TaskSummaryState], TaskWorkspaceServiceError>

    public init(
        revision: Int = 0,
        selectedTaskID: UUID? = nil,
        selectedTask: TaskSessionSnapshot? = nil,
        selectionError: TaskWorkspaceServiceError? = nil,
        sessions: StoreState<[TaskSummaryState], TaskWorkspaceServiceError> = .loaded([])
    ) {
        self.revision = revision
        self.selectedTaskID = selectedTaskID
        self.selectedTask = selectedTask
        self.selectionError = selectionError
        self.sessions = sessions
    }
}
