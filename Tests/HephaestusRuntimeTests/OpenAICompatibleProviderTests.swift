import Foundation
import HephaestusComposition
import HephaestusKernel
import HephaestusLLM
import HephaestusRuntime
import Testing

@Suite
struct OpenAICompatibleProviderTests {
    @Test
    func providerConfigurationDefaultsToMock() throws {
        let selection = try RuntimeProviderConfiguration.resolve(environment: [:])

        #expect(selection == .mock)
    }

    @Test
    func providerConfigurationUsesLiveDefaultsFromEnvironment() throws {
        let selection = try RuntimeProviderConfiguration.resolve(environment: [
            "HEPHAESTUS_PROVIDER": "openai-compatible"
        ])

        guard case .openAICompatible(let configuration) = selection else {
            Issue.record("Expected openai-compatible provider selection.")
            return
        }

        #expect(configuration.baseURLString == "https://api.openai.com/v1")
        #expect(configuration.model == "gpt-4.1-mini")
        #expect(configuration.apiKey == nil)
    }

    @Test
    func providerConfigurationRejectsUnknownProviderMode() {
        #expect(throws: RuntimeProviderConfigurationError.self) {
            _ = try RuntimeProviderConfiguration.resolve(environment: [
                "HEPHAESTUS_PROVIDER": "anthropic"
            ])
        }
    }

    @Test
    func explicitProviderOverrideRejectsUnknownModeInsteadOfFallingBack() throws {
        #expect(try RuntimeProviderConfiguration.resolveExplicitOverride(environment: [:]) == nil)
        #expect(try RuntimeProviderConfiguration.resolveExplicitOverride(environment: [
            "HEPHAESTUS_PROVIDER": " "
        ]) == nil)
        #expect(try RuntimeProviderConfiguration.resolveExplicitOverride(environment: [
            "HEPHAESTUS_PROVIDER": "mock"
        ]) == .mock)
        #expect(throws: RuntimeProviderConfigurationError.self) {
            _ = try RuntimeProviderConfiguration.resolveExplicitOverride(environment: [
                "HEPHAESTUS_PROVIDER": "anthropic"
            ])
        }
    }

    @Test
    func chatCompletionsURLJoinsBaseURLPredictably() throws {
        let trailingSlashBase = try #require(URL(string: "https://example.com/api/v1/"))
        let noSlashBase = try #require(URL(string: "https://example.com/api/v1"))
        let queryBase = try #require(URL(string: "https://example.com/api/v1?ignored=true"))

        #expect(OpenAICompatibleProviderClient.chatCompletionsURL(baseURL: trailingSlashBase).absoluteString == "https://example.com/api/v1/chat/completions")
        #expect(OpenAICompatibleProviderClient.chatCompletionsURL(baseURL: noSlashBase).absoluteString == "https://example.com/api/v1/chat/completions")
        #expect(OpenAICompatibleProviderClient.chatCompletionsURL(baseURL: queryBase).absoluteString == "https://example.com/api/v1/chat/completions")
    }

    @Test
    func providerBuildsAuthorizedStreamingChatCompletionsRequest() async throws {
        let transport = RecordingOpenAICompatibleTransport(events: [
            .response(statusCode: 200),
            .data(Data("""
            data: {"choices":[{"delta":{"content":"Hel"}}]}
            data: {"choices":[{"delta":{"content":"lo"}}]}
            data: [DONE]

            """.utf8))
        ])
        let provider = OpenAICompatibleProviderClient(
            configuration: OpenAICompatibleClientConfiguration(
                baseURL: try #require(URL(string: "https://provider.test/api/v1/")),
                apiKey: "secret-token",
                model: "unused-client-model"
            ),
            transport: transport
        )
        let providerRequest = ProviderRequest(
            runID: UUID(),
            turnID: UUID(),
            model: "request-model",
            messages: [
                ProviderMessage(role: .system, text: "system"),
                ProviderMessage(role: .user, text: "hello")
            ],
            stream: true
        )

        let chunks = try await collect(provider.stream(request: providerRequest))
        let request = try #require(transport.allRequests().first)
        let body = try JSONDecoder().decode(ChatCompletionsRequestBody.self, from: request.body)

        #expect(request.url.absoluteString == "https://provider.test/api/v1/chat/completions")
        #expect(request.method == "POST")
        #expect(request.headers["Authorization"] == "Bearer secret-token")
        #expect(request.headers["Accept"] == "text/event-stream")
        #expect(request.headers["Content-Type"] == "application/json")
        #expect(body.model == "request-model")
        #expect(body.stream)
        #expect(body.messages == [
            ChatCompletionsRequestBody.Message(role: "system", content: "system"),
            ChatCompletionsRequestBody.Message(role: "user", content: "hello")
        ])
        #expect(chunks.map(\.textDelta).joined() == "Hello")
    }

    @Test
    func providerParsesNonStreamingChatCompletionsResponse() async throws {
        let transport = RecordingOpenAICompatibleTransport(events: [
            .response(statusCode: 200),
            .data(Data("""
            {"choices":[{"finish_reason":"stop","message":{"content":"ok"}}]}
            """.utf8))
        ])
        let provider = OpenAICompatibleProviderClient(
            configuration: OpenAICompatibleClientConfiguration(
                baseURL: try #require(URL(string: "http://127.0.0.1:8000/v1")),
                apiKey: "anything",
                model: "unused-client-model"
            ),
            transport: transport
        )
        let providerRequest = ProviderRequest(
            runID: UUID(),
            turnID: UUID(),
            model: "gpt-5.4",
            messages: [ProviderMessage(role: .user, text: "Reply with ok.")],
            stream: false
        )

        let chunks = try await collect(provider.stream(request: providerRequest))
        let request = try #require(transport.allRequests().first)
        let body = try JSONDecoder().decode(ChatCompletionsRequestBody.self, from: request.body)

        #expect(request.url.absoluteString == "http://127.0.0.1:8000/v1/chat/completions")
        #expect(request.headers["Accept"] == "application/json")
        #expect(body.model == "gpt-5.4")
        #expect(!body.stream)
        #expect(chunks.map(\.textDelta).joined() == "ok")
        #expect(chunks.first?.finishReason == .stop)
    }

    @Test
    func providerSettingsValidationUsesNonStreamingProbe() async throws {
        let transport = RecordingOpenAICompatibleTransport(events: [
            .response(statusCode: 200),
            .data(Data("""
            {"choices":[{"finish_reason":"stop","message":{"content":"ok"}}]}
            """.utf8))
        ])
        let validator = OpenAICompatibleProviderSettingsValidator(transport: transport)

        let result = await validator.validateProviderSettings(ProviderSettingsDraft(
            baseURLString: "http://127.0.0.1:8000/v1",
            apiKey: "anything",
            model: "gpt-5.4"
        ))
        let request = try #require(transport.allRequests().first)
        let body = try JSONDecoder().decode(ChatCompletionsRequestBody.self, from: request.body)

        #expect(result == .success)
        #expect(request.url.absoluteString == "http://127.0.0.1:8000/v1/chat/completions")
        #expect(request.headers["Accept"] == "application/json")
        #expect(body.model == "gpt-5.4")
        #expect(!body.stream)
    }

    @Test
    func sseParserExtractsChoicesDeltaContentAcrossDataBoundaries() throws {
        let providerRequestID = UUID()
        var parser = OpenAICompatibleSSEParser(providerRequestID: providerRequestID)

        let first = try parser.parse(Data("data: {\"choices\":[{\"delta\":{\"content\":\"Hel".utf8))
        let second = try parser.parse(Data("lo \"}}]}\n: ignored\ndata: {\"choices\":[{\"delta\":{\"content\":\"world\"}}]}\ndata: [DONE]\n".utf8))
        let finished = try parser.finish()

        #expect(first.isEmpty)
        #expect((second + finished).map(\.providerRequestID).allSatisfy { $0 == providerRequestID })
        #expect((second + finished).map(\.textDelta) == ["Hello ", "world"])
    }

    @Test
    func providerPreservesMultibyteUTF8SplitAcrossByteBoundaries() async throws {
        let text = "Héllo 🔥"
        let sseData = Data("data: {\"choices\":[{\"delta\":{\"content\":\"\(text)\"}}]}\ndata: [DONE]\n".utf8)
        let byteEvents = sseData.map { OpenAICompatibleTransportEvent.data(Data([$0])) }
        let transport = RecordingOpenAICompatibleTransport(events: [.response(statusCode: 200)] + byteEvents)
        let provider = OpenAICompatibleProviderClient(
            configuration: OpenAICompatibleClientConfiguration(
                baseURL: try #require(URL(string: "https://provider.test/v1")),
                apiKey: "token",
                model: "model"
            ),
            transport: transport
        )
        let request = ProviderRequest(
            runID: UUID(),
            turnID: UUID(),
            model: "model",
            messages: [ProviderMessage(role: .user, text: "hello")],
            stream: true
        )

        let chunks = try await collect(provider.stream(request: request))

        #expect(chunks.map(\.textDelta).joined() == text)
    }

    @Test
    func openAICompatibleCompositionUsesConfiguredModelInRuntimeRequest() async throws {
        let transport = RecordingOpenAICompatibleTransport(events: successfulSSEEvents("ok"))
        let harness = RuntimeComposition.makeOpenAICompatible(
            configuration: OpenAICompatibleEnvironmentConfiguration(
                baseURLString: "https://provider.test/v1",
                apiKey: "token",
                model: "custom-model"
            ),
            transport: transport
        )
        let runID = await harness.createRun.createRun()

        _ = try await collect(
            harness.streamUserMessage.streamUserMessage(runID: runID, text: "compose this")
        )

        let request = try #require(transport.allRequests().first)
        let body = try JSONDecoder().decode(ChatCompletionsRequestBody.self, from: request.body)

        #expect(body.model == "custom-model")
        #expect(body.stream)
        #expect(body.messages.contains(ChatCompletionsRequestBody.Message(
            role: "system",
            content: "You are a helpful assistant in the Hephaestus harness."
        )))
        #expect(body.messages.contains(ChatCompletionsRequestBody.Message(
            role: "user",
            content: "compose this"
        )))
    }

    @Test
    func missingAPIKeyFlowsThroughTurnFailedEvent() async throws {
        let harness = try RuntimeComposition.make(environment: [
            "HEPHAESTUS_PROVIDER": "openai-compatible"
        ])
        let runID = await harness.createRun.createRun()

        let result = await collectCatching(
            try await harness.streamUserMessage.streamUserMessage(runID: runID, text: "hello")
        )

        #expect(result.events.containsTurnFailed(containing: "Missing HEPHAESTUS_OPENAI_API_KEY"))
        #expect(String(describing: result.error).contains("Missing HEPHAESTUS_OPENAI_API_KEY"))
    }

    @Test
    func invalidBaseURLFlowsThroughTurnFailedEvent() async throws {
        let harness = try RuntimeComposition.make(environment: [
            "HEPHAESTUS_PROVIDER": "openai-compatible",
            "HEPHAESTUS_OPENAI_BASE_URL": "not a url",
            "HEPHAESTUS_OPENAI_API_KEY": "token"
        ])
        let runID = await harness.createRun.createRun()

        let result = await collectCatching(
            try await harness.streamUserMessage.streamUserMessage(runID: runID, text: "hello")
        )

        #expect(result.events.containsTurnFailed(containing: "Invalid HEPHAESTUS_OPENAI_BASE_URL"))
        #expect(String(describing: result.error).contains("Invalid HEPHAESTUS_OPENAI_BASE_URL"))
    }

    @Test
    func providerHTTPErrorFlowsThroughTurnFailedEvent() async throws {
        let transport = RecordingOpenAICompatibleTransport(events: [
            .response(statusCode: 401),
            .data(Data("bad token".utf8))
        ])
        let harness = RuntimeComposition.makeOpenAICompatible(
            configuration: OpenAICompatibleEnvironmentConfiguration(
                baseURLString: "https://provider.test/v1",
                apiKey: "token",
                model: "custom-model"
            ),
            transport: transport
        )
        let runID = await harness.createRun.createRun()

        let result = await collectCatching(
            try await harness.streamUserMessage.streamUserMessage(runID: runID, text: "hello")
        )

        #expect(result.events.containsTurnFailed(containing: "HTTP 401"))
        #expect(String(describing: result.error).contains("bad token"))
    }

    @Test
    func failedProviderTurnCanRecoverWithSecondSendInSameRun() async throws {
        let transport = SequencedOpenAICompatibleTransport(eventBatches: [
            [
                .response(statusCode: 500),
                .data(Data("temporary outage".utf8))
            ],
            successfulSSEEvents("recovered")
        ])
        let harness = RuntimeComposition.makeOpenAICompatible(
            configuration: OpenAICompatibleEnvironmentConfiguration(
                baseURLString: "https://provider.test/v1",
                apiKey: "token",
                model: "custom-model"
            ),
            transport: transport
        )
        let runID = await harness.createRun.createRun()

        let failed = await collectCatching(
            try await harness.streamUserMessage.streamUserMessage(runID: runID, text: "first")
        )
        let recovered = try await collect(
            harness.streamUserMessage.streamUserMessage(runID: runID, text: "second")
        )

        #expect(failed.events.containsTurnFailed(containing: "HTTP 500"))
        #expect(String(describing: failed.error).contains("temporary outage"))
        #expect(recovered.containsAssistantCompleted(containing: "recovered"))
        #expect(transport.allRequests().count == 2)
    }

    private func successfulSSEEvents(_ text: String) -> [OpenAICompatibleTransportEvent] {
        [
            .response(statusCode: 200),
            .data(Data("data: {\"choices\":[{\"delta\":{\"content\":\"\(text)\"}}]}\ndata: [DONE]\n".utf8))
        ]
    }

    private func collect(
        _ stream: AsyncThrowingStream<ProviderResponseChunk, Error>
    ) async throws -> [ProviderResponseChunk] {
        var chunks: [ProviderResponseChunk] = []
        for try await chunk in stream {
            chunks.append(chunk)
        }
        return chunks
    }

    private func collect(
        _ stream: AsyncThrowingStream<RuntimeEvent, Error>
    ) async throws -> [RuntimeEvent] {
        var events: [RuntimeEvent] = []
        for try await event in stream {
            events.append(event)
        }
        return events
    }

    private func collectCatching(
        _ stream: AsyncThrowingStream<RuntimeEvent, Error>
    ) async -> (events: [RuntimeEvent], error: Error?) {
        var events: [RuntimeEvent] = []
        do {
            for try await event in stream {
                events.append(event)
            }
            return (events, nil)
        } catch {
            return (events, error)
        }
    }
}

private final class SequencedOpenAICompatibleTransport: OpenAICompatibleTransport, @unchecked Sendable {
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

private final class RecordingOpenAICompatibleTransport: OpenAICompatibleTransport, @unchecked Sendable {
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

private struct ChatCompletionsRequestBody: Decodable, Equatable {
    struct Message: Decodable, Equatable {
        let role: String
        let content: String
    }

    let model: String
    let stream: Bool
    let messages: [Message]
}

private extension ProviderResponseChunk {
    var textDelta: String {
        if case .text(let value) = delta {
            return value
        }
        return ""
    }
}

private extension Array where Element == RuntimeEvent {
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
