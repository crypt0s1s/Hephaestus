import Foundation
import HephaestusKernel

public actor MockProviderRecorder {
    private var requests: [ProviderRequest] = []

    public init() {}

    public func record(_ request: ProviderRequest) {
        requests.append(request)
    }

    public func allRequests() -> [ProviderRequest] {
        requests
    }
}

public struct MockProviderClient: ProviderClient {
    private let recorder: MockProviderRecorder
    private let delayNanoseconds: UInt64

    public init(recorder: MockProviderRecorder, delayNanoseconds: UInt64 = 0) {
        self.recorder = recorder
        self.delayNanoseconds = delayNanoseconds
    }

    public func stream(request: ProviderRequest) -> AsyncThrowingStream<ProviderResponseChunk, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                await recorder.record(request)
                let lastUser = request.messages.last(where: { $0.role == .user })?.text ?? ""
                let response = "Mock response after \(request.messages.count) messages: \(lastUser)"
                let chunks = response.split(separator: " ", omittingEmptySubsequences: false).map { String($0) }

                for index in chunks.indices {
                    if delayNanoseconds > 0 {
                        do {
                            try await Task.sleep(nanoseconds: delayNanoseconds)
                        } catch {
                            continuation.finish(throwing: error)
                            return
                        }
                    }
                    guard !Task.isCancelled else {
                        continuation.finish(throwing: CancellationError())
                        return
                    }
                    let suffix = index == chunks.index(before: chunks.endIndex) ? "" : " "
                    continuation.yield(
                        ProviderResponseChunk(
                            providerRequestID: request.id,
                            delta: .text(chunks[index] + suffix),
                            finishReason: nil
                        )
                    )
                }

                continuation.finish()
            }
            continuation.onTermination = { @Sendable _ in
                task.cancel()
            }
        }
    }
}
