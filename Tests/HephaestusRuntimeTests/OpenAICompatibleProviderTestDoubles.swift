import Foundation
import HephaestusKernel
import HephaestusLLM
import HephaestusRuntime

final class OpenAISequencedTransport: OpenAICompatibleTransport,
    @unchecked Sendable {
    private let lock = NSLock()
    private var requests: [OpenAICompatibleTransportRequest] = []
    private var eventBatches: [[OpenAICompatibleTransportEvent]]

    init(eventBatches: [[OpenAICompatibleTransportEvent]]) {
        self.eventBatches = eventBatches
    }

    func stream(
        request: OpenAICompatibleTransportRequest
    ) -> AsyncThrowingStream<OpenAICompatibleTransportEvent, Error> {
        let events = lock.withLock {
            requests.append(request)
            if eventBatches.isEmpty {
                return [OpenAICompatibleTransportEvent.response(statusCode: 500)]
            }
            return eventBatches.removeFirst()
        }

        return AsyncThrowingStream { continuation in
            for event in events {
                continuation.yield(event)
            }
            continuation.finish()
        }
    }

    func allRequests() -> [OpenAICompatibleTransportRequest] {
        lock.withLock {
            requests
        }
    }
}

final class OpenAIRecordingTransport: OpenAICompatibleTransport,
    @unchecked Sendable {
    private let lock = NSLock()
    private var requests: [OpenAICompatibleTransportRequest] = []
    private let events: [OpenAICompatibleTransportEvent]

    init(events: [OpenAICompatibleTransportEvent]) {
        self.events = events
    }

    func stream(
        request: OpenAICompatibleTransportRequest
    ) -> AsyncThrowingStream<OpenAICompatibleTransportEvent, Error> {
        lock.withLock {
            requests.append(request)
        }

        return AsyncThrowingStream { continuation in
            for event in events {
                continuation.yield(event)
            }
            continuation.finish()
        }
    }

    func allRequests() -> [OpenAICompatibleTransportRequest] {
        lock.withLock {
            requests
        }
    }
}

struct OpenAIChatCompletionsRequestBody: Decodable, Equatable {
    struct Message: Decodable, Equatable {
        let role: String
        let content: String
    }

    let model: String
    let stream: Bool
    let messages: [Message]
}

extension ProviderResponseChunk {
    var textDelta: String {
        if case .text(let value) = delta {
            return value
        }
        return ""
    }
}

extension Array where Element == RuntimeEvent {
    func containsTurnFailed(containing expected: String) -> Bool {
        contains { event in
            if case .turnFailed(_, let reason) = event {
                return reason.contains(expected)
            }
            return false
        }
    }

    func containsAssistantCompleted(containing expected: String) -> Bool {
        contains { event in
            if case .assistantMessageCompleted(_, _, let text) = event {
                return text.contains(expected)
            }
            return false
        }
    }
}
