import Foundation
import HephaestusComposition
import HephaestusKernel
import HephaestusLLM
import HephaestusRuntime
import Testing

extension OpenAICompatibleProviderTests {
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
      "HEPHAESTUS_OPENAI_API_KEY": "token",
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
    let transport = OpenAIRecordingTransport(events: [
      .response(statusCode: 401),
      .data(Data("bad token".utf8)),
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
    let transport = OpenAISequencedTransport(eventBatches: [
      [
        .response(statusCode: 500),
        .data(Data("temporary outage".utf8)),
      ],
      successfulSSEEvents("recovered"),
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

  func successfulSSEEvents(_ text: String) -> [OpenAICompatibleTransportEvent] {
    [
      .response(statusCode: 200),
      .data(
        Data("data: {\"choices\":[{\"delta\":{\"content\":\"\(text)\"}}]}\ndata: [DONE]\n".utf8)),
    ]
  }

  func collect(
    _ stream: AsyncThrowingStream<ProviderResponseChunk, Error>
  ) async throws -> [ProviderResponseChunk] {
    var chunks: [ProviderResponseChunk] = []
    for try await chunk in stream {
      chunks.append(chunk)
    }
    return chunks
  }

  func collect(
    _ stream: AsyncThrowingStream<RuntimeEvent, Error>
  ) async throws -> [RuntimeEvent] {
    var events: [RuntimeEvent] = []
    for try await event in stream {
      events.append(event)
    }
    return events
  }

  func collectCatching(
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
