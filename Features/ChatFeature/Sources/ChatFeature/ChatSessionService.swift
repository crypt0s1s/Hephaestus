import Anvil
import ChatContracts
import Foundation
import HephaestusRuntime

public struct ChatSessionError: Error, Equatable, Sendable, CustomStringConvertible {
    public let description: String

    public init(_ description: String) {
        self.description = description
    }

    public init(_ error: Error) {
        self.init(String(describing: error))
    }
}

public struct ChatWorkspaceError: Error, Equatable, Sendable, CustomStringConvertible {
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

public struct ChatSessionSnapshot: Equatable, Sendable {
    public var id: UUID
    public var title: String
    public var transcript: StoreState<[ChatMessageState], ChatSessionError>
    public var turnState: StoreState<TurnProgressState, ChatSessionError>
    public var updatedAt: Date

    public init(
        id: UUID,
        title: String,
        transcript: StoreState<[ChatMessageState], ChatSessionError> = .loaded([]),
        turnState: StoreState<TurnProgressState, ChatSessionError> = .loaded(TurnProgressState()),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.transcript = transcript
        self.turnState = turnState
        self.updatedAt = updatedAt
    }

    public var messages: [ChatMessageState] {
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

public struct ChatWorkspaceSnapshot: Equatable, Sendable {
    public var revision: Int
    public var selectedChatID: UUID?
    public var selectedChat: ChatSessionSnapshot?
    public var selectionError: ChatWorkspaceError?
    public var sessions: StoreState<[ChatSessionSummaryState], ChatWorkspaceError>

    public init(
        revision: Int = 0,
        selectedChatID: UUID? = nil,
        selectedChat: ChatSessionSnapshot? = nil,
        selectionError: ChatWorkspaceError? = nil,
        sessions: StoreState<[ChatSessionSummaryState], ChatWorkspaceError> = .loaded([])
    ) {
        self.revision = revision
        self.selectedChatID = selectedChatID
        self.selectedChat = selectedChat
        self.selectionError = selectionError
        self.sessions = sessions
    }
}

@MainActor
public final class ChatSessionService {
    public private(set) var snapshot: ChatSessionSnapshot

    private let streamUserMessage: StreamUserMessageUseCase
    private let onSummaryChanged: @MainActor () -> Void
    private var snapshotContinuations: [UUID: AsyncStream<ChatSessionSnapshot>.Continuation] = [:]
    private var sendTask: Task<Void, Never>?

    public init(
        snapshot: ChatSessionSnapshot,
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
            snapshot: ChatSessionSnapshot(
                id: session.id,
                title: session.title,
                transcript: .loaded(session.messages.compactMap(ChatMessageState.init(message:))),
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

    public func subscribeSnapshots(includeCurrent: Bool = true) -> AsyncStream<ChatSessionSnapshot> {
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
                    self.failActiveTurn(ChatSessionError(error))
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
                messages.append(ChatMessageState(id: messageID, role: .user, text: text))
                snapshot.title = snapshot.title == "New Chat" ? text.firstLineTitle : snapshot.title
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
                snapshot.turnState = .error(ChatSessionError(reason))
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

    private func failActiveTurn(_ error: ChatSessionError) {
        updateSnapshot { snapshot in
            var messages = snapshot.messages
            markStreamingAssistantComplete(in: &messages)
            snapshot.transcript = .loaded(messages)
            snapshot.turnState = .error(error)
        }
    }

    private func updateSnapshot(_ update: (inout ChatSessionSnapshot) -> Void) {
        update(&snapshot)
        publishSnapshot()
    }

    private func publishSnapshot() {
        for continuation in snapshotContinuations.values {
            continuation.yield(snapshot)
        }
    }
}

@MainActor
public final class ChatSessionServiceRegistry {
    private let createRun: CreateRunUseCase
    private let streamUserMessage: StreamUserMessageUseCase
    private let loadSession: LoadSessionUseCase?
    private let createSession: CreateSessionUseCase?
    private var services: [UUID: ChatSessionService] = [:]
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

    public func service(for id: UUID) async throws -> ChatSessionService {
        if let service = services[id] {
            return service
        }

        let service: ChatSessionService
        if let loadSession {
            let session = try await loadSession.loadSession(id: id)
            service = makeService(session: session)
        } else {
            service = makeService(snapshot: ChatSessionSnapshot(id: id, title: "New Chat"))
        }
        services[service.id] = service
        return service
    }

    public func createService(title: String? = nil) async throws -> ChatSessionService {
        let service: ChatSessionService
        if let createSession {
            let session = try await createSession.createSession(title: title)
            service = makeService(session: session)
        } else {
            let id = await createRun.createRun()
            service = makeService(snapshot: ChatSessionSnapshot(id: id, title: title ?? "New Chat"))
        }

        services[service.id] = service
        return service
    }

    private func makeService(session: PersistedSession) -> ChatSessionService {
        ChatSessionService(
            session: session,
            streamUserMessage: streamUserMessage,
            onSummaryChanged: onServiceSummaryChanged
        )
    }

    private func makeService(snapshot: ChatSessionSnapshot) -> ChatSessionService {
        ChatSessionService(
            snapshot: snapshot,
            streamUserMessage: streamUserMessage,
            onSummaryChanged: onServiceSummaryChanged
        )
    }
}

@MainActor
public final class ChatWorkspaceService {
    public private(set) var snapshot: ChatWorkspaceSnapshot

    private let registry: ChatSessionServiceRegistry
    private let listSessions: ListSessionsUseCase?
    private let router: Router<AnyRouteInput, AnyModalInput>?
    private var selectedService: ChatSessionService?
    private var selectedSnapshotTask: Task<Void, Never>?
    private var snapshotContinuations: [UUID: AsyncStream<ChatWorkspaceSnapshot>.Continuation] = [:]

    public init(
        registry: ChatSessionServiceRegistry,
        listSessions: ListSessionsUseCase? = nil,
        router: Router<AnyRouteInput, AnyModalInput>? = nil,
        snapshot: ChatWorkspaceSnapshot = ChatWorkspaceSnapshot()
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

    public func subscribeSnapshots() -> AsyncStream<ChatWorkspaceSnapshot> {
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
    public func selectChat(_ id: UUID, force: Bool = false) async -> Bool {
        guard force || snapshot.selectedChatID != id else { return false }
        do {
            let service = try await registry.service(for: id)
            attach(to: service)
            return true
        } catch {
            detachSelection(error: ChatWorkspaceError(error))
            return false
        }
    }

    @discardableResult
    public func createNewChat(title: String? = nil) async -> Bool {
        do {
            let service = try await registry.createService(title: title)
            attach(to: service)
            await refreshSummaries()
            return true
        } catch {
            setSessions(.error(ChatWorkspaceError(error)))
            return false
        }
    }

    public func sendMessage(_ text: String) async -> Bool {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else { return false }

        let service: ChatSessionService
        if let selectedService {
            service = selectedService
        } else {
            do {
                service = try await registry.createService(title: nil)
                attach(to: service)
                await refreshSummaries()
            } catch {
                setSessions(.error(ChatWorkspaceError(error)))
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
            setSessions(.loaded(summaries.map(ChatSessionSummaryState.init(summary:))))
        } catch {
            setSessions(.error(ChatWorkspaceError(error)))
        }
    }

    private func attach(to service: ChatSessionService) {
        selectedSnapshotTask?.cancel()
        selectedService = service
        updateSnapshot { snapshot in
            snapshot.selectedChatID = service.id
            snapshot.selectedChat = service.snapshot
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

    private func detachSelection(error: ChatWorkspaceError) {
        selectedSnapshotTask?.cancel()
        selectedSnapshotTask = nil
        selectedService = nil
        updateSnapshot { snapshot in
            snapshot.selectedChatID = nil
            snapshot.selectedChat = nil
            snapshot.selectionError = error
        }
    }

    private func syncSelectedRoute(_ id: UUID) {
        guard let router,
              let route = try? AnyRouteInput(ChatRouteInput(runID: id))
        else { return }
        if let current = router.path.last,
           (try? current.decode(ChatRouteInput.self).runID) == id {
            return
        }
        router.replaceStack([route])
    }

    private func applySelectedServiceSnapshot(_ serviceSnapshot: ChatSessionSnapshot) {
        guard snapshot.selectedChatID == serviceSnapshot.id else { return }
        updateSnapshot { snapshot in
            snapshot.selectedChatID = serviceSnapshot.id
            snapshot.selectedChat = serviceSnapshot
        }
    }

    private func setSessions(_ sessions: StoreState<[ChatSessionSummaryState], ChatWorkspaceError>) {
        updateSnapshot { snapshot in
            snapshot.sessions = sessions
        }
    }

    private func updateSnapshot(_ update: (inout ChatWorkspaceSnapshot) -> Void) {
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

private func appendAssistantDelta(_ text: String, to messages: inout [ChatMessageState]) {
    if let index = messages.lastIndex(where: { $0.role == .assistant && $0.isStreaming }) {
        messages[index].text += text
    } else {
        messages.append(ChatMessageState(role: .assistant, text: text, isStreaming: true))
    }
}

private func completeAssistantMessage(messageID: UUID, text: String, in messages: inout [ChatMessageState]) {
    if let index = messages.lastIndex(where: { $0.role == .assistant && $0.isStreaming }) {
        messages[index].id = messageID
        messages[index].text = text
        messages[index].isStreaming = false
    } else {
        messages.append(ChatMessageState(id: messageID, role: .assistant, text: text))
    }
}

private func markStreamingAssistantComplete(in messages: inout [ChatMessageState]) {
    if let index = messages.lastIndex(where: { $0.role == .assistant && $0.isStreaming }) {
        messages[index].isStreaming = false
    }
}

private extension String {
    var firstLineTitle: String {
        let firstLine = split(whereSeparator: \.isNewline).first.map(String.init) ?? self
        let trimmed = firstLine.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "New Chat" : String(trimmed.prefix(80))
    }
}
