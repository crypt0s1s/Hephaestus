import Anvil
import Foundation
import HephaestusDomain
import HephaestusRuntime
import TaskWorkspaceContracts

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
                acceptUserMessage(messageID: messageID, text: text, header: header, snapshot: &snapshot)
                shouldRefreshSummary = true
            case .contextPrepared(let header, _),
                .providerRequestPrepared(let header, _, _, _):
                markTurnRunning(header: header, snapshot: &snapshot)
            case .assistantTextDelta(let header, let text):
                applyAssistantDelta(text, header: header, messages: &messages, snapshot: &snapshot)
            case .assistantMessageCompleted(let header, let messageID, let text):
                finishAssistantMessage(
                    messageID: messageID,
                    text: text,
                    header: header,
                    messages: &messages,
                    snapshot: &snapshot
                )
            case .turnCancelled(let header):
                completeTurn(header: header, messages: &messages, snapshot: &snapshot)
            case .turnFailed(let header, let reason):
                failTurn(reason: reason, header: header, messages: &messages, snapshot: &snapshot)
            }
        }
        if shouldRefreshSummary {
            onSummaryChanged()
        }
    }

    private func acceptUserMessage(
        messageID: UUID,
        text: String,
        header: RuntimeEventHeader,
        snapshot: inout TaskSessionSnapshot
    ) {
        var messages = snapshot.messages
        messages.append(ConversationMessageState(id: messageID, role: .user, text: text))
        snapshot.title = snapshot.title == "New Task" ? text.firstLineTitle : snapshot.title
        snapshot.updatedAt = header.createdAt
        snapshot.transcript = .loaded(messages)
        snapshot.turnState = runningTurnState(header.turnID)
    }

    private func markTurnRunning(header: RuntimeEventHeader, snapshot: inout TaskSessionSnapshot) {
        snapshot.updatedAt = header.createdAt
        snapshot.turnState = runningTurnState(header.turnID)
    }

    private func applyAssistantDelta(
        _ text: String,
        header: RuntimeEventHeader,
        messages: inout [ConversationMessageState],
        snapshot: inout TaskSessionSnapshot
    ) {
        appendAssistantDelta(text, to: &messages)
        snapshot.updatedAt = header.createdAt
        snapshot.transcript = .loaded(messages)
        snapshot.turnState = runningTurnState(header.turnID)
    }

    private func finishAssistantMessage(
        messageID: UUID,
        text: String,
        header: RuntimeEventHeader,
        messages: inout [ConversationMessageState],
        snapshot: inout TaskSessionSnapshot
    ) {
        completeAssistantMessage(messageID: messageID, text: text, in: &messages)
        completeTurn(header: header, messages: &messages, snapshot: &snapshot)
    }

    private func completeTurn(
        header: RuntimeEventHeader,
        messages: inout [ConversationMessageState],
        snapshot: inout TaskSessionSnapshot
    ) {
        markStreamingAssistantComplete(in: &messages)
        snapshot.updatedAt = header.createdAt
        snapshot.transcript = .loaded(messages)
        snapshot.turnState = .loaded(TurnProgressState(activeTurnID: nil, isRunning: false))
    }

    private func failTurn(
        reason: String,
        header: RuntimeEventHeader,
        messages: inout [ConversationMessageState],
        snapshot: inout TaskSessionSnapshot
    ) {
        markStreamingAssistantComplete(in: &messages)
        snapshot.updatedAt = header.createdAt
        snapshot.transcript = .loaded(messages)
        snapshot.turnState = .error(TaskSessionError(reason))
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

private func runningTurnState(_ turnID: UUID?) -> StoreState<TurnProgressState, TaskSessionError> {
    .loading(placeholder: TurnProgressState(activeTurnID: turnID, isRunning: true))
}
