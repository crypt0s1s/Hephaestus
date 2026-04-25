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

    public init(recorder: MockProviderRecorder) {
        self.recorder = recorder
    }

    public func stream(request: ProviderRequest) -> AsyncThrowingStream<ProviderResponseChunk, Error> {
        AsyncThrowingStream { continuation in
            Task {
                await recorder.record(request)
                let lastUser = request.messages.last(where: { $0.role == .user })?.text ?? ""
                let response = "Mock response after \(request.messages.count) messages: \(lastUser)"
                continuation.yield(
                    ProviderResponseChunk(
                        providerRequestID: request.id,
                        delta: .text(response),
                        finishReason: .stop
                    )
                )
                continuation.finish()
            }
        }
    }
}
