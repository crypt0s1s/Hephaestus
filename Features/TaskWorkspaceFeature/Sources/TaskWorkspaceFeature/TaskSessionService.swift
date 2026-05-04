import Anvil
import Foundation
import HephaestusDomain
import HephaestusRuntime
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
        self.task = task ?? AgentTask(
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

@MainActor
public final class TaskSessionService {
    public private(set) var snapshot: TaskSessionSnapshot

    private let streamUserMessage: StreamUserMessageUseCase
    private let onSummaryChanged: @MainActor () -> Void
    private var snapshotContinuations: [UUID: AsyncStream<TaskSessionSnapshot>.Continuation] = [:]
    private var sendTask: Task<Void, Never>?

    public init(
        snapshot: TaskSessionSnapshot,
        streamUserMessage: StreamUserMessageUseCase,
        onSummaryChanged: @escaping @MainActor () -> Void = {}
    ) {
        self.snapshot = snapshot
        self.streamUserMessage = streamUserMessage
        self.onSummaryChanged = onSummaryChanged
    }

    public convenience init(
        session: PersistedSession,
        streamUserMessage: StreamUserMessageUseCase,
        onSummaryChanged: @escaping @MainActor () -> Void = {}
    ) {
        self.init(
            snapshot: TaskSessionSnapshot(
                id: session.id,
                title: session.title,
                task: AgentTask(session: session),
                transcript: .loaded(session.messages.compactMap(ConversationMessageState.init(message:))),
                turnState: .loaded(TurnProgressState()),
                updatedAt: session.updatedAt
            ),
            streamUserMessage: streamUserMessage,
            onSummaryChanged: onSummaryChanged
        )
    }

    public var id: UUID {
        snapshot.id
    }

    public func subscribeSnapshots(includeCurrent: Bool = true) -> AsyncStream<TaskSessionSnapshot> {
        AsyncStream { continuation in
            let subscriptionID = UUID()
            snapshotContinuations[subscriptionID] = continuation
            if includeCurrent {
                continuation.yield(snapshot)
            }
            continuation.onTermination = { @Sendable _ in
                Task { @MainActor in
                    self.snapshotContinuations[subscriptionID] = nil
                }
            }
        }
    }

    public func send(_ text: String) {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty, sendTask == nil else { return }

        updateSnapshot { snapshot in
            snapshot.transcript = .loaded(snapshot.messages)
            snapshot.turnState = .loading(placeholder: TurnProgressState(isRunning: true))
        }

        let runID = snapshot.id
        sendTask = Task { [streamUserMessage] in
            do {
                let stream = try await streamUserMessage.streamUserMessage(runID: runID, text: trimmedText)
                for try await event in stream {
                    await MainActor.run {
                        self.apply(event)
                    }
                }
                await MainActor.run {
                    if self.snapshot.isRunning {
                        self.finishActiveTurn()
                    }
                    self.sendTask = nil
                    self.onSummaryChanged()
                }
            } catch is CancellationError {
                await MainActor.run {
                    self.finishActiveTurn()
                    self.sendTask = nil
                    self.onSummaryChanged()
                }
            } catch {
                await MainActor.run {
                    self.failActiveTurn(TaskSessionError(error))
                    self.sendTask = nil
                    self.onSummaryChanged()
                }
            }
        }
    }

    public func cancelActiveTurn() {
        guard sendTask != nil else { return }
        sendTask?.cancel()
        sendTask = nil
        finishActiveTurn()
        onSummaryChanged()
    }

    private func apply(_ event: RuntimeEvent) {
        guard event.header.runID == snapshot.id else { return }
        var shouldRefreshSummary = false
        updateSnapshot { snapshot in
            var messages = snapshot.messages
            switch event {
            case .runCreated(_, let runID):
                snapshot.id = runID
            case .userMessageAccepted(let header, let messageID, let text):
                messages.append(ConversationMessageState(id: messageID, role: .user, text: text))
                snapshot.title = snapshot.title == "New Task" ? text.firstLineTitle : snapshot.title
                snapshot.updatedAt = header.createdAt
                snapshot.transcript = .loaded(messages)
                snapshot.turnState = .loading(placeholder: TurnProgressState(activeTurnID: header.turnID, isRunning: true))
                shouldRefreshSummary = true
            case .contextPrepared(let header, _),
                 .providerRequestPrepared(let header, _, _, _):
                snapshot.updatedAt = header.createdAt
                snapshot.turnState = .loading(placeholder: TurnProgressState(activeTurnID: header.turnID, isRunning: true))
            case .assistantTextDelta(let header, let text):
                appendAssistantDelta(text, to: &messages)
                snapshot.updatedAt = header.createdAt
                snapshot.transcript = .loaded(messages)
                snapshot.turnState = .loading(placeholder: TurnProgressState(activeTurnID: header.turnID, isRunning: true))
            case .assistantMessageCompleted(let header, let messageID, let text):
                completeAssistantMessage(messageID: messageID, text: text, in: &messages)
                snapshot.updatedAt = header.createdAt
                snapshot.transcript = .loaded(messages)
                snapshot.turnState = .loaded(TurnProgressState(activeTurnID: nil, isRunning: false))
            case .turnCancelled(let header):
                markStreamingAssistantComplete(in: &messages)
                snapshot.updatedAt = header.createdAt
                snapshot.transcript = .loaded(messages)
                snapshot.turnState = .loaded(TurnProgressState(activeTurnID: nil, isRunning: false))
            case .turnFailed(let header, let reason):
                markStreamingAssistantComplete(in: &messages)
                snapshot.updatedAt = header.createdAt
                snapshot.transcript = .loaded(messages)
                snapshot.turnState = .error(TaskSessionError(reason))
            }
        }
        if shouldRefreshSummary {
            onSummaryChanged()
        }
    }

    private func finishActiveTurn() {
        updateSnapshot { snapshot in
            var messages = snapshot.messages
            markStreamingAssistantComplete(in: &messages)
            snapshot.transcript = .loaded(messages)
            snapshot.turnState = .loaded(TurnProgressState(activeTurnID: nil, isRunning: false))
        }
    }

    private func failActiveTurn(_ error: TaskSessionError) {
        updateSnapshot { snapshot in
            var messages = snapshot.messages
            markStreamingAssistantComplete(in: &messages)
            snapshot.transcript = .loaded(messages)
            snapshot.turnState = .error(error)
        }
    }

    private func updateSnapshot(_ update: (inout TaskSessionSnapshot) -> Void) {
        update(&snapshot)
        snapshot.task.title = snapshot.title
        snapshot.task.updatedAt = snapshot.updatedAt
        snapshot.task.activeRunID = snapshot.id
        snapshot.task.status = snapshot.taskStatus
        publishSnapshot()
    }

    private func publishSnapshot() {
        for continuation in snapshotContinuations.values {
            continuation.yield(snapshot)
        }
    }
}

@MainActor
public final class TaskSessionServiceRegistry {
    private let createRun: CreateRunUseCase
    private let streamUserMessage: StreamUserMessageUseCase
    private let loadSession: LoadSessionUseCase?
    private let createSession: CreateSessionUseCase?
    private var services: [UUID: TaskSessionService] = [:]
    private var onServiceSummaryChanged: @MainActor () -> Void = {}

    public init(
        createRun: CreateRunUseCase,
        streamUserMessage: StreamUserMessageUseCase,
        loadSession: LoadSessionUseCase? = nil,
        createSession: CreateSessionUseCase? = nil
    ) {
        self.createRun = createRun
        self.streamUserMessage = streamUserMessage
        self.loadSession = loadSession
        self.createSession = createSession
    }

    public func setOnServiceSummaryChanged(_ onServiceSummaryChanged: @escaping @MainActor () -> Void) {
        self.onServiceSummaryChanged = onServiceSummaryChanged
    }

    public func service(for id: UUID) async throws -> TaskSessionService {
        if let service = services[id] {
            return service
        }

        let service: TaskSessionService
        if let loadSession {
            let session = try await loadSession.loadSession(id: id)
            service = makeService(session: session)
        } else {
            service = makeService(snapshot: TaskSessionSnapshot(id: id, title: "New Task"))
        }
        services[service.id] = service
        return service
    }

    public func createService(title: String? = nil) async throws -> TaskSessionService {
        let service: TaskSessionService
        if let createSession {
            let session = try await createSession.createSession(title: title)
            service = makeService(session: session)
        } else {
            let id = await createRun.createRun()
            service = makeService(snapshot: TaskSessionSnapshot(id: id, title: title ?? "New Task"))
        }

        services[service.id] = service
        return service
    }

    private func makeService(session: PersistedSession) -> TaskSessionService {
        TaskSessionService(
            session: session,
            streamUserMessage: streamUserMessage,
            onSummaryChanged: onServiceSummaryChanged
        )
    }

    private func makeService(snapshot: TaskSessionSnapshot) -> TaskSessionService {
        TaskSessionService(
            snapshot: snapshot,
            streamUserMessage: streamUserMessage,
            onSummaryChanged: onServiceSummaryChanged
        )
    }
}

@MainActor
public final class TaskWorkspaceService {
    public private(set) var snapshot: TaskWorkspaceSnapshot

    private let registry: TaskSessionServiceRegistry
    private let listSessions: ListSessionsUseCase?
    private let router: Router<AnyRouteInput, AnyModalInput>?
    private var selectedService: TaskSessionService?
    private var selectedSnapshotTask: Task<Void, Never>?
    private var snapshotContinuations: [UUID: AsyncStream<TaskWorkspaceSnapshot>.Continuation] = [:]

    public init(
        registry: TaskSessionServiceRegistry,
        listSessions: ListSessionsUseCase? = nil,
        router: Router<AnyRouteInput, AnyModalInput>? = nil,
        snapshot: TaskWorkspaceSnapshot = TaskWorkspaceSnapshot()
    ) {
        self.registry = registry
        self.listSessions = listSessions
        self.router = router
        self.snapshot = snapshot
        registry.setOnServiceSummaryChanged { [weak self] in
            Task { @MainActor in
                await self?.refreshSummaries()
            }
        }
    }

    deinit {
        selectedSnapshotTask?.cancel()
    }

    public func subscribeSnapshots() -> AsyncStream<TaskWorkspaceSnapshot> {
        AsyncStream { continuation in
            let subscriptionID = UUID()
            snapshotContinuations[subscriptionID] = continuation
            continuation.yield(snapshot)
            continuation.onTermination = { @Sendable _ in
                Task { @MainActor in
                    self.snapshotContinuations[subscriptionID] = nil
                }
            }
        }
    }

    @discardableResult
    public func selectTask(_ id: UUID, force: Bool = false) async -> Bool {
        guard force || snapshot.selectedTaskID != id else { return false }
        do {
            let service = try await registry.service(for: id)
            attach(to: service)
            return true
        } catch {
            detachSelection(error: TaskWorkspaceServiceError(error))
            return false
        }
    }

    @discardableResult
    public func createNewTask(title: String? = nil) async -> Bool {
        do {
            let service = try await registry.createService(title: title)
            attach(to: service)
            await refreshSummaries()
            return true
        } catch {
            setSessions(.error(TaskWorkspaceServiceError(error)))
            return false
        }
    }

    public func sendMessage(_ text: String) async -> Bool {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else { return false }

        let service: TaskSessionService
        if let selectedService {
            service = selectedService
        } else {
            do {
                service = try await registry.createService(title: nil)
                attach(to: service)
                await refreshSummaries()
            } catch {
                setSessions(.error(TaskWorkspaceServiceError(error)))
                return false
            }
        }

        service.send(trimmedText)
        applySelectedServiceSnapshot(service.snapshot)
        return true
    }

    public func cancelSelectedTurn() {
        selectedService?.cancelActiveTurn()
        if let selectedService {
            applySelectedServiceSnapshot(selectedService.snapshot)
        }
    }

    public func refreshSummaries() async {
        guard let listSessions else { return }
        setSessions(.loading(placeholder: snapshot.sessions.data))
        do {
            let summaries = try await listSessions.listSessions()
            setSessions(.loaded(summaries.map(TaskSummaryState.init(summary:))))
        } catch {
            setSessions(.error(TaskWorkspaceServiceError(error)))
        }
    }

    private func attach(to service: TaskSessionService) {
        selectedSnapshotTask?.cancel()
        selectedService = service
        updateSnapshot { snapshot in
            snapshot.selectedTaskID = service.id
            snapshot.selectedTask = service.snapshot
            snapshot.selectionError = nil
        }
        syncSelectedRoute(service.id)
        selectedSnapshotTask = Task { [weak self, service] in
            for await snapshot in service.subscribeSnapshots(includeCurrent: false) {
                await MainActor.run {
                    self?.applySelectedServiceSnapshot(snapshot)
                }
            }
        }
    }

    private func detachSelection(error: TaskWorkspaceServiceError) {
        selectedSnapshotTask?.cancel()
        selectedSnapshotTask = nil
        selectedService = nil
        updateSnapshot { snapshot in
            snapshot.selectedTaskID = nil
            snapshot.selectedTask = nil
            snapshot.selectionError = error
        }
    }

    private func syncSelectedRoute(_ id: UUID) {
        guard let router,
              let route = try? AnyRouteInput(TaskWorkspaceRouteInput(taskID: id))
        else { return }
        if let current = router.path.last,
           (try? current.decode(TaskWorkspaceRouteInput.self).taskID) == id {
            return
        }
        router.replaceStack([route])
    }

    private func applySelectedServiceSnapshot(_ serviceSnapshot: TaskSessionSnapshot) {
        guard snapshot.selectedTaskID == serviceSnapshot.id else { return }
        updateSnapshot { snapshot in
            snapshot.selectedTaskID = serviceSnapshot.id
            snapshot.selectedTask = serviceSnapshot
        }
    }

    private func setSessions(_ sessions: StoreState<[TaskSummaryState], TaskWorkspaceServiceError>) {
        updateSnapshot { snapshot in
            snapshot.sessions = sessions
        }
    }

    private func updateSnapshot(_ update: (inout TaskWorkspaceSnapshot) -> Void) {
        update(&snapshot)
        snapshot.revision += 1
        publishSnapshot()
    }

    private func publishSnapshot() {
        for continuation in snapshotContinuations.values {
            continuation.yield(snapshot)
        }
    }
}

private func appendAssistantDelta(_ text: String, to messages: inout [ConversationMessageState]) {
    if let index = messages.lastIndex(where: { $0.role == .assistant && $0.isStreaming }) {
        messages[index].text += text
    } else {
        messages.append(ConversationMessageState(role: .assistant, text: text, isStreaming: true))
    }
}

private func completeAssistantMessage(messageID: UUID, text: String, in messages: inout [ConversationMessageState]) {
    if let index = messages.lastIndex(where: { $0.role == .assistant && $0.isStreaming }) {
        messages[index].id = messageID
        messages[index].text = text
        messages[index].isStreaming = false
    } else {
        messages.append(ConversationMessageState(id: messageID, role: .assistant, text: text))
    }
}

private func markStreamingAssistantComplete(in messages: inout [ConversationMessageState]) {
    if let index = messages.lastIndex(where: { $0.role == .assistant && $0.isStreaming }) {
        messages[index].isStreaming = false
    }
}

private extension String {
    var firstLineTitle: String {
        let firstLine = split(whereSeparator: \.isNewline).first.map(String.init) ?? self
        let trimmed = firstLine.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "New Task" : String(trimmed.prefix(80))
    }
}

private extension TaskSessionSnapshot {
    var taskStatus: TaskStatus {
        switch turnState {
        case .loading:
            return .running
        case .loaded(let progress):
            if progress.isRunning {
                return .running
            }
            return messages.isEmpty ? .draft : .completed
        case .error:
            return .failed
        }
    }
}
