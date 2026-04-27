import Anvil
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

    public func subscribeSnapshots() -> AsyncStream<ChatSessionSnapshot> {
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
    public private(set) var summaries: StoreState<[ChatSessionSummaryState], ChatSessionError> = .loaded([])

    private let createRun: CreateRunUseCase
    private let streamUserMessage: StreamUserMessageUseCase
    private let listSessions: ListSessionsUseCase?
    private let loadSession: LoadSessionUseCase?
    private let createSession: CreateSessionUseCase?
    private var services: [UUID: ChatSessionService] = [:]
    private var summaryContinuations: [UUID: AsyncStream<StoreState<[ChatSessionSummaryState], ChatSessionError>>.Continuation] = [:]

    public init(
        createRun: CreateRunUseCase,
        streamUserMessage: StreamUserMessageUseCase,
        listSessions: ListSessionsUseCase? = nil,
        loadSession: LoadSessionUseCase? = nil,
        createSession: CreateSessionUseCase? = nil
    ) {
        self.createRun = createRun
        self.streamUserMessage = streamUserMessage
        self.listSessions = listSessions
        self.loadSession = loadSession
        self.createSession = createSession
    }

    public func subscribeSummaries() -> AsyncStream<StoreState<[ChatSessionSummaryState], ChatSessionError>> {
        AsyncStream { continuation in
            let subscriptionID = UUID()
            summaryContinuations[subscriptionID] = continuation
            continuation.yield(summaries)
            continuation.onTermination = { @Sendable _ in
                Task { @MainActor in
                    self.summaryContinuations[subscriptionID] = nil
                }
            }
        }
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
        await refreshSummaries()
        return service
    }

    public func refreshSummaries() async {
        guard let listSessions else { return }
        setSummaries(.loading(placeholder: summaries.data))
        do {
            let summaries = try await listSessions.listSessions()
            setSummaries(.loaded(summaries.map(ChatSessionSummaryState.init(summary:))))
        } catch {
            setSummaries(.error(ChatSessionError(error)))
        }
    }

    private func makeService(session: PersistedSession) -> ChatSessionService {
        ChatSessionService(
            session: session,
            streamUserMessage: streamUserMessage,
            onSummaryChanged: { [weak self] in
                Task { @MainActor in
                    await self?.refreshSummaries()
                }
            }
        )
    }

    private func makeService(snapshot: ChatSessionSnapshot) -> ChatSessionService {
        ChatSessionService(
            snapshot: snapshot,
            streamUserMessage: streamUserMessage,
            onSummaryChanged: { [weak self] in
                Task { @MainActor in
                    await self?.refreshSummaries()
                }
            }
        )
    }

    private func setSummaries(_ next: StoreState<[ChatSessionSummaryState], ChatSessionError>) {
        summaries = next
        for continuation in summaryContinuations.values {
            continuation.yield(next)
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
