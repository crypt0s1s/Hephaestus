import Foundation
import HephaestusKernel
import HephaestusRuntime

struct StreamRequest: Equatable, Sendable {
    let runID: UUID
    let text: String
}

actor BlockingCreateRunUseCase: CreateRunUseCase {
    private let runID: UUID
    private var callCount = 0
    private var callWaiters: [CheckedContinuation<Void, Never>] = []
    private var continuations: [CheckedContinuation<UUID, Never>] = []

    init(runID: UUID) {
        self.runID = runID
    }

    func createRun() async -> UUID {
        callCount += 1
        let waiters = callWaiters
        callWaiters.removeAll()
        for waiter in waiters {
            waiter.resume()
        }

        return await withCheckedContinuation { continuation in
            continuations.append(continuation)
        }
    }

    func waitUntilCallCount(_ expectedCallCount: Int) async {
        if callCount >= expectedCallCount {
            return
        }

        await withCheckedContinuation { continuation in
            callWaiters.append(continuation)
        }
    }

    func calls() -> Int {
        callCount
    }

    func releaseAll() {
        let pendingContinuations = continuations
        continuations.removeAll()
        for continuation in pendingContinuations {
            continuation.resume(returning: runID)
        }
    }
}

actor RecordingStreamUserMessageUseCase: StreamUserMessageUseCase {
    private var recordedRequests: [StreamRequest] = []

    func streamUserMessage(
        runID: UUID,
        text: String
    ) async throws -> AsyncThrowingStream<RuntimeEvent, Error> {
        recordedRequests.append(StreamRequest(runID: runID, text: text))

        return AsyncThrowingStream { continuation in
            let turnID = UUID()
            continuation.yield(
                .userMessageAccepted(
                    RuntimeEventHeader(
                        id: UUID(), runID: runID, turnID: turnID, sequence: 1, createdAt: Date()),
                    messageID: UUID(),
                    text: text
                ))
            continuation.yield(
                .assistantMessageCompleted(
                    RuntimeEventHeader(
                        id: UUID(), runID: runID, turnID: turnID, sequence: 2, createdAt: Date()),
                    messageID: UUID(),
                    text: "done"
                ))
            continuation.finish()
        }
    }

    func requests() -> [StreamRequest] {
        recordedRequests
    }
}

extension Array where Element == RunEvent {
    var firstUserMessageAccepted: (header: EventHeader, message: RunMessage)? {
        for event in self {
            if case .userMessageAccepted(let header, let message) = event {
                return (header, message)
            }
        }
        return nil
    }

    var firstAssistantCompleted: (header: EventHeader, message: RunMessage)? {
        for event in self {
            if case .assistantMessageCompleted(let header, let message) = event {
                return (header, message)
            }
        }
        return nil
    }
}
