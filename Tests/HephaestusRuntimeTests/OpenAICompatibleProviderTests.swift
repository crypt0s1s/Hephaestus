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
    #expect(
      try RuntimeProviderConfiguration.resolveExplicitOverride(environment: [
        "HEPHAESTUS_PROVIDER": " "
      ]) == nil)
    #expect(
      try RuntimeProviderConfiguration.resolveExplicitOverride(environment: [
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

    #expect(
      OpenAICompatibleProviderClient.chatCompletionsURL(baseURL: trailingSlashBase).absoluteString
        == "https://example.com/api/v1/chat/completions")
    #expect(
      OpenAICompatibleProviderClient.chatCompletionsURL(baseURL: noSlashBase).absoluteString
        == "https://example.com/api/v1/chat/completions")
    #expect(
      OpenAICompatibleProviderClient.chatCompletionsURL(baseURL: queryBase).absoluteString
        == "https://example.com/api/v1/chat/completions")
  }

  @Test
  func providerBuildsAuthorizedStreamingChatCompletionsRequest() async throws {
    let fixture = try makeAuthorizedStreamingRequestFixture()

    let chunks = try await collect(fixture.provider.stream(request: fixture.providerRequest))
    let request = try #require(fixture.transport.allRequests().first)
    let body = try JSONDecoder().decode(OpenAIChatCompletionsRequestBody.self, from: request.body)

    assertAuthorizedStreamingRequest(request, body: body)
    #expect(chunks.map(\.textDelta).joined() == "Hello")
  }

  @Test
  func providerParsesNonStreamingChatCompletionsResponse() async throws {
    let transport = OpenAIRecordingTransport(events: [
      .response(statusCode: 200),
      .data(
        Data(
          """
          {"choices":[{"finish_reason":"stop","message":{"content":"ok"}}]}
          """.utf8)),
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
    let body = try JSONDecoder().decode(OpenAIChatCompletionsRequestBody.self, from: request.body)

    #expect(request.url.absoluteString == "http://127.0.0.1:8000/v1/chat/completions")
    #expect(request.headers["Accept"] == "application/json")
    #expect(body.model == "gpt-5.4")
    #expect(!body.stream)
    #expect(chunks.map(\.textDelta).joined() == "ok")
    #expect(chunks.first?.finishReason == .stop)
  }

  @Test
  func providerSettingsValidationUsesNonStreamingProbe() async throws {
    let transport = OpenAIRecordingTransport(events: [
      .response(statusCode: 200),
      .data(
        Data(
          """
          {"choices":[{"finish_reason":"stop","message":{"content":"ok"}}]}
          """.utf8)),
    ])
    let validator = OpenAICompatibleProviderSettingsValidator(transport: transport)

    let result = await validator.validateProviderSettings(
      ProviderSettingsDraft(
        baseURLString: "http://127.0.0.1:8000/v1",
        apiKey: "anything",
        model: "gpt-5.4"
      ))
    let request = try #require(transport.allRequests().first)
    let body = try JSONDecoder().decode(OpenAIChatCompletionsRequestBody.self, from: request.body)

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
    let second = try parser.parse(
      Data(
        "lo \"}}]}\n: ignored\ndata: {\"choices\":[{\"delta\":{\"content\":\"world\"}}]}\ndata: [DONE]\n"
          .utf8))
    let finished = try parser.finish()

    #expect(first.isEmpty)
    #expect((second + finished).map(\.providerRequestID).allSatisfy { $0 == providerRequestID })
    #expect((second + finished).map(\.textDelta) == ["Hello ", "world"])
  }

  @Test
  func providerPreservesMultibyteUTF8SplitAcrossByteBoundaries() async throws {
    let text = "Héllo 🔥"
    let sseData = Data(
      "data: {\"choices\":[{\"delta\":{\"content\":\"\(text)\"}}]}\ndata: [DONE]\n".utf8)
    let byteEvents = sseData.map { OpenAICompatibleTransportEvent.data(Data([$0])) }
    let transport = OpenAIRecordingTransport(
      events: [.response(statusCode: 200)] + byteEvents)
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
    let transport = OpenAIRecordingTransport(events: successfulSSEEvents("ok"))
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
    let body = try JSONDecoder().decode(OpenAIChatCompletionsRequestBody.self, from: request.body)

    #expect(body.model == "custom-model")
    #expect(body.stream)
    #expect(
      body.messages.contains(
        OpenAIChatCompletionsRequestBody.Message(
          role: "system",
          content: "You are a helpful assistant in the Hephaestus harness."
        )))
    #expect(
      body.messages.contains(
        OpenAIChatCompletionsRequestBody.Message(
          role: "user",
          content: "compose this"
        )))
  }
}

private func makeAuthorizedStreamingRequestFixture() throws -> (
  transport: OpenAIRecordingTransport,
  provider: OpenAICompatibleProviderClient,
  providerRequest: ProviderRequest
) {
  let transport = OpenAIRecordingTransport(events: [
    .response(statusCode: 200),
    .data(
      Data(
        """
        data: {"choices":[{"delta":{"content":"Hel"}}]}
        data: {"choices":[{"delta":{"content":"lo"}}]}
        data: [DONE]

        """.utf8)),
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
      ProviderMessage(role: .user, text: "hello"),
    ],
    stream: true
  )
  return (transport, provider, providerRequest)
}

private func assertAuthorizedStreamingRequest(
  _ request: OpenAICompatibleTransportRequest,
  body: OpenAIChatCompletionsRequestBody
) {
  #expect(request.url.absoluteString == "https://provider.test/api/v1/chat/completions")
  #expect(request.method == "POST")
  #expect(request.headers["Authorization"] == "Bearer secret-token")
  #expect(request.headers["Accept"] == "text/event-stream")
  #expect(request.headers["Content-Type"] == "application/json")
  #expect(body.model == "request-model")
  #expect(body.stream)
  #expect(
    body.messages == [
      OpenAIChatCompletionsRequestBody.Message(role: "system", content: "system"),
      OpenAIChatCompletionsRequestBody.Message(role: "user", content: "hello"),
    ])
}
