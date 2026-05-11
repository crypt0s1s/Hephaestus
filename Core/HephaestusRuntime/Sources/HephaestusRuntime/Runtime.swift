import Foundation
import HephaestusKernel

public enum RuntimeEvent: Sendable, Hashable {
    case runCreated(RuntimeEventHeader, UUID)
    case userMessageAccepted(RuntimeEventHeader, messageID: UUID, text: String)
    case contextPrepared(RuntimeEventHeader, includedMessageCount: Int)
    case providerRequestPrepared(RuntimeEventHeader, requestID: UUID, model: String, messageCount: Int)
    case assistantTextDelta(RuntimeEventHeader, String)
    case assistantMessageCompleted(RuntimeEventHeader, messageID: UUID, text: String)
    case turnCancelled(RuntimeEventHeader)
    case turnFailed(RuntimeEventHeader, String)

    public var header: RuntimeEventHeader {
        switch self {
        case .runCreated(let header, _),
            .userMessageAccepted(let header, _, _),
            .contextPrepared(let header, _),
            .providerRequestPrepared(let header, _, _, _),
            .assistantTextDelta(let header, _),
            .assistantMessageCompleted(let header, _, _),
            .turnCancelled(let header),
            .turnFailed(let header, _):
            return header
        }
    }
}

public struct RuntimeEventHeader: Sendable, Hashable, Identifiable {
    public let id: UUID
    public let runID: UUID
    public let turnID: UUID?
    public let sequence: Int
    public let createdAt: Date

    public init(
        id: UUID,
        runID: UUID,
        turnID: UUID?,
        sequence: Int,
        createdAt: Date
    ) {
        self.id = id
        self.runID = runID
        self.turnID = turnID
        self.sequence = sequence
        self.createdAt = createdAt
    }

    public init(_ header: EventHeader) {
        self.init(
            id: header.id,
            runID: header.runID,
            turnID: header.turnID,
            sequence: header.sequence,
            createdAt: header.createdAt
        )
    }
}

public protocol CreateRunUseCase: Sendable {
    func createRun() async -> UUID
}

public protocol StreamUserMessageUseCase: Sendable {
    func streamUserMessage(
        runID: UUID,
        text: String
    ) async throws -> AsyncThrowingStream<RuntimeEvent, Error>
}

public protocol SubmitUserMessageUseCase: Sendable {
    func submitUserMessage(runID: UUID, text: String) async throws -> String
}

public protocol ObserveRunEventsUseCase: Sendable {
    func events(runID: UUID) async throws -> AsyncStream<RuntimeEvent>
}

public enum RuntimeFailure: Error, Equatable {
    case runNotFound(UUID)
}

extension RuntimeEvent {
    public init(_ event: RunEvent) {
        switch event {
        case .userMessageAccepted(let header, let message):
            self = .userMessageAccepted(RuntimeEventHeader(header), messageID: message.id, text: message.text)
        case .contextPrepared(let header, let trace):
            self = .contextPrepared(RuntimeEventHeader(header), includedMessageCount: trace.includedMessageIDs.count)
        case .providerRequestPrepared(let header, let request):
            self = .providerRequestPrepared(
                RuntimeEventHeader(header),
                requestID: request.id,
                model: request.model,
                messageCount: request.messages.count
            )
        case .providerChunkReceived(let header, _, let text):
            self = .assistantTextDelta(RuntimeEventHeader(header), text)
        case .assistantMessageCompleted(let header, let message):
            self = .assistantMessageCompleted(RuntimeEventHeader(header), messageID: message.id, text: message.text)
        case .turnCancelled(let header):
            self = .turnCancelled(RuntimeEventHeader(header))
        case .turnFailed(let header, let reason):
            self = .turnFailed(RuntimeEventHeader(header), reason)
        }
    }
}

public actor RuntimeEventHub {
    private var continuations: [UUID: [UUID: AsyncStream<RuntimeEvent>.Continuation]] = [:]

    public init() {}

    public func stream(runID: UUID) -> AsyncStream<RuntimeEvent> {
        AsyncStream { continuation in
            let subscriptionID = UUID()
            continuations[runID, default: [:]][subscriptionID] = continuation
            continuation.onTermination = { @Sendable _ in
                Task {
                    await self.remove(subscriptionID: subscriptionID, runID: runID)
                }
            }
        }
    }

    public func publish(_ event: RuntimeEvent, runID: UUID) {
        guard let runSubscriptions = continuations[runID] else { return }
        let runContinuations = Array(runSubscriptions.values)
        for continuation in runContinuations {
            continuation.yield(event)
        }
    }

    private func remove(subscriptionID: UUID, runID: UUID) {
        continuations[runID]?[subscriptionID] = nil
        if continuations[runID]?.isEmpty == true {
            continuations[runID] = nil
        }
    }
}

public actor InMemoryRunStore {
    private let makeRun: @Sendable () -> Run
    private var runs: [UUID: Run] = [:]

    public init(makeRun: @escaping @Sendable () -> Run) {
        self.makeRun = makeRun
    }

    public func createRun() -> UUID {
        let run = makeRun()
        runs[run.id] = run
        return run.id
    }

    public func run(id: UUID) throws -> Run {
        guard let run = runs[id] else {
            throw RuntimeFailure.runNotFound(id)
        }
        return run
    }

    public func contains(id: UUID) -> Bool {
        runs[id] != nil
    }

    public func insert(_ run: Run) {
        runs[run.id] = run
    }
}

public struct DefaultCreateRunUseCase: CreateRunUseCase {
    private let runStore: InMemoryRunStore

    public init(runStore: InMemoryRunStore) {
        self.runStore = runStore
    }

    public func createRun() async -> UUID {
        await runStore.createRun()
    }
}

public struct DefaultStreamUserMessageUseCase: StreamUserMessageUseCase {
    private let runStore: InMemoryRunStore
    private let eventHub: RuntimeEventHub

    public init(runStore: InMemoryRunStore, eventHub: RuntimeEventHub) {
        self.runStore = runStore
        self.eventHub = eventHub
    }

    public func streamUserMessage(
        runID: UUID,
        text: String
    ) async throws -> AsyncThrowingStream<RuntimeEvent, Error> {
        let run = try await runStore.run(id: runID)
        let runEvents = await run.streamUserMessage(text)

        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    for try await event in runEvents {
                        let runtimeEvent = RuntimeEvent(event)
                        await eventHub.publish(runtimeEvent, runID: runID)
                        continuation.yield(runtimeEvent)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { @Sendable _ in
                task.cancel()
            }
        }
    }

}

public struct DefaultSubmitUserMessageUseCase: SubmitUserMessageUseCase {
    private let streamUserMessage: StreamUserMessageUseCase

    public init(streamUserMessage: StreamUserMessageUseCase) {
        self.streamUserMessage = streamUserMessage
    }

    public func submitUserMessage(runID: UUID, text: String) async throws -> String {
        let stream = try await streamUserMessage.streamUserMessage(runID: runID, text: text)
        var finalText = ""
        for try await event in stream {
            if case .assistantMessageCompleted(_, _, let text) = event {
                finalText = text
            }
        }
        return finalText
    }
}

public struct DefaultObserveRunEventsUseCase: ObserveRunEventsUseCase {
    private let runStore: InMemoryRunStore
    private let eventHub: RuntimeEventHub

    public init(runStore: InMemoryRunStore, eventHub: RuntimeEventHub) {
        self.runStore = runStore
        self.eventHub = eventHub
    }

    public func events(runID: UUID) async throws -> AsyncStream<RuntimeEvent> {
        _ = try await runStore.run(id: runID)
        return await eventHub.stream(runID: runID)
    }
}
