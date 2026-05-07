import Foundation
import HephaestusComposition
import HephaestusKernel
import HephaestusLLM
import HephaestusRuntime
import Testing

@Suite
struct PersistentRuntimeTests {
  @Test
  func providerSettingsSaveLoadAndClearUseRedactedSummary() async throws {
    let store = InMemoryAppStateStore()
    let useCase = DefaultProviderSettingsUseCase(store: store)
    let validatedAt = Date()

    try await useCase.saveProviderSettings(
      ProviderSettingsDraft(
        baseURLString: "https://provider.test/v1",
        apiKey: "secret-key",
        model: "test-model"
      ),
      validatedAt: validatedAt
    )

    let summary = try #require(try await useCase.loadProviderSettings())
    let rawSettings = try #require(try await store.load().providerSettings)

    #expect(summary.baseURLString == "https://provider.test/v1")
    #expect(summary.model == "test-model")
    #expect(summary.hasSavedAPIKey)
    #expect(summary.validatedAt == validatedAt)
    #expect(rawSettings.apiKey == "secret-key")

    try await useCase.clearProviderSettings()

    #expect(try await useCase.loadProviderSettings() == nil)
  }

  @Test
  func providerValidationUsesInjectedTransportForSuccessAndFailure() async throws {
    let successTransport = RecordingOpenAICompatibleTransport(events: successfulJSONEvents("ok"))
    let successValidator = OpenAICompatibleProviderSettingsValidator(transport: successTransport)

    let success = await successValidator.validateProviderSettings(
      ProviderSettingsDraft(
        baseURLString: "https://provider.test/v1",
        apiKey: "token",
        model: "model"
      ))

    #expect(success == .success)
    #expect(successTransport.allRequests().count == 1)

    let failureTransport = RecordingOpenAICompatibleTransport(events: [
      .response(statusCode: 401),
      .data(Data("bad key".utf8)),
    ])
    let failureValidator = OpenAICompatibleProviderSettingsValidator(transport: failureTransport)

    let failure = await failureValidator.validateProviderSettings(
      ProviderSettingsDraft(
        baseURLString: "https://provider.test/v1",
        apiKey: "token",
        model: "model"
      ))

    guard case .failure(let reason) = failure else {
      Issue.record("Expected validation failure.")
      return
    }
    #expect(reason.contains("HTTP 401"))
    #expect(reason.contains("bad key"))
  }

  @Test
  func providerValidationAcceptsLocalOpenAICompatibleJSONResponse() async throws {
    let transport = RecordingOpenAICompatibleTransport(events: successfulJSONEvents("ok"))
    let validator = OpenAICompatibleProviderSettingsValidator(transport: transport)

    let result = await validator.validateProviderSettings(
      ProviderSettingsDraft(
        baseURLString: "http://127.0.0.1:8000/v1",
        apiKey: "anything",
        model: "gpt-5.4"
      ))
    let request = try #require(transport.allRequests().first)
    let body = try JSONDecoder().decode(ChatCompletionsRequestBody.self, from: request.body)

    #expect(result == .success)
    #expect(request.url.absoluteString == "http://127.0.0.1:8000/v1/chat/completions")
    #expect(request.headers["Authorization"] == "Bearer anything")
    #expect(request.headers["Accept"] == "application/json")
    #expect(body.model == "gpt-5.4")
    #expect(!body.stream)
  }

  @Test
  func persistedSessionSurvivesFileStoreReload() async throws {
    let fileURL = temporaryStateFileURL()
    let store = FileAppStateStore(fileURL: fileURL)
    let harness = RuntimeComposition.makePersistentMock(store: store)
    let session = try await harness.createSession.createSession(title: "Durable")

    _ = try await collect(
      harness.streamUserMessage.streamUserMessage(runID: session.id, text: "remember this")
    )

    let reloadedStore = FileAppStateStore(fileURL: fileURL)
    let reloadedState = try await reloadedStore.load()
    let reloadedSession = try #require(reloadedState.sessions.first)

    #expect(reloadedSession.id == session.id)
    #expect(reloadedSession.messages.map(\.text).contains("remember this"))
    #expect(reloadedSession.messages.contains(where: { $0.role == .assistant }))
    #expect(!reloadedSession.events.isEmpty)
  }

  @Test
  func reopenedSessionContinuesWithPriorMessagesAsContext() async throws {
    let store = InMemoryAppStateStore()
    let firstHarness = RuntimeComposition.makePersistentMock(store: store)
    let session = try await firstHarness.createSession.createSession(title: nil)

    _ = try await collect(
      firstHarness.streamUserMessage.streamUserMessage(runID: session.id, text: "first")
    )

    let secondHarness = RuntimeComposition.makePersistentMock(store: store)
    _ = try await secondHarness.loadSession.loadSession(id: session.id)
    _ = try await collect(
      secondHarness.streamUserMessage.streamUserMessage(runID: session.id, text: "second")
    )

    let inspection = try await secondHarness.inspectRun.inspectRun(sessionID: session.id)
    let secondProviderSummary = try #require(inspection.session.providerRequests.last)

    #expect(inspection.session.messages.map(\.text).contains("first"))
    #expect(inspection.session.messages.map(\.text).contains("second"))
    #expect(secondProviderSummary.messageCount >= 4)
  }

  @Test
  func contextTraceRecordsIncludedAndExcludedMessagesWithSmallLimit() async throws {
    let store = InMemoryAppStateStore()
    let harness = RuntimeComposition.makePersistentMock(store: store, messageLimit: 2)
    let session = try await harness.createSession.createSession(title: nil)

    _ = try await collect(
      harness.streamUserMessage.streamUserMessage(runID: session.id, text: "one"))
    _ = try await collect(
      harness.streamUserMessage.streamUserMessage(runID: session.id, text: "two"))
    _ = try await collect(
      harness.streamUserMessage.streamUserMessage(runID: session.id, text: "three"))

    let inspection = try await harness.inspectRun.inspectRun(sessionID: session.id)
    let lastTrace = try #require(inspection.session.contextTraces.last)

    #expect(lastTrace.policyID == "recent")
    #expect(lastTrace.policyName == "Recent messages")
    #expect(lastTrace.messageLimit == 2)
    #expect(lastTrace.includedMessageIDs.count == 2)
    #expect(!lastTrace.excludedMessageIDs.isEmpty)
  }

  @Test
  func runInspectionContainsOrderedEventsProviderSummaryContextAndFailure() async throws {
    let store = InMemoryAppStateStore()
    let transport = RecordingOpenAICompatibleTransport(events: [
      .response(statusCode: 500),
      .data(Data("provider down".utf8)),
    ])
    let harness = RuntimeComposition.makePersistentOpenAICompatible(
      store: store,
      configuration: OpenAICompatibleEnvironmentConfiguration(
        baseURLString: "https://provider.test/v1",
        apiKey: "token",
        model: "debug-model"
      ),
      transport: transport
    )
    let session = try await harness.createSession.createSession(title: "Failure")

    let result = await collectCatching(
      try await harness.streamUserMessage.streamUserMessage(runID: session.id, text: "fail visibly")
    )
    let inspection = try await harness.inspectRun.inspectRun(sessionID: session.id)

    #expect(result.error != nil)
    #expect(
      inspection.orderedEvents.map(\.sequence) == inspection.orderedEvents.map(\.sequence).sorted())
    #expect(
      inspection.orderedEvents.contains(where: {
        $0.kind == .turnFailed && $0.error?.contains("HTTP 500") == true
      }))
    #expect(
      inspection.session.providerRequests.contains(where: {
        $0.model == "debug-model" && $0.messageCount == 2 && $0.systemPromptIncluded
      }))
    #expect(inspection.session.contextTraces.count == 1)
    #expect(inspection.session.turns.last?.status == .failed)
  }

  @Test
  func cancellingPersistentStreamPersistsCancelledTurnAndEvent() async throws {
    let store = InMemoryAppStateStore()
    let harness = RuntimeComposition.makePersistentMock(
      store: store,
      delayNanoseconds: 200_000_000
    )
    let session = try await harness.createSession.createSession(title: nil)
    let stream = try await harness.streamUserMessage.streamUserMessage(
      runID: session.id,
      text: "cancel persistently"
    )
    let collector = Task {
      await collectCatching(stream)
    }

    await waitUntil {
      let state = try? await store.load()
      return state?.sessions.first?.providerRequests.isEmpty == false
    }

    collector.cancel()
    _ = await collector.value

    await waitUntil {
      let inspection = try? await harness.inspectRun.inspectRun(sessionID: session.id)
      return inspection?.orderedEvents.contains(where: { $0.kind == .turnCancelled }) == true
        && inspection?.session.turns.last?.status == .cancelled
    }

    let inspection = try await harness.inspectRun.inspectRun(sessionID: session.id)
    #expect(inspection.orderedEvents.contains(where: { $0.kind == .turnCancelled }))
    #expect(inspection.session.turns.last?.status == .cancelled)
  }

  private func temporaryStateFileURL() -> URL {
    FileManager.default.temporaryDirectory
      .appendingPathComponent("hephaestus-\(UUID().uuidString)", isDirectory: true)
      .appendingPathComponent("state.json")
  }

  private func successfulSSEEvents(_ text: String) -> [OpenAICompatibleTransportEvent] {
    [
      .response(statusCode: 200),
      .data(
        Data("data: {\"choices\":[{\"delta\":{\"content\":\"\(text)\"}}]}\ndata: [DONE]\n".utf8)),
    ]
  }

  private func successfulJSONEvents(_ text: String) -> [OpenAICompatibleTransportEvent] {
    [
      .response(statusCode: 200),
      .data(
        Data(
          """
          {"choices":[{"message":{"content":"\(text)"},"finish_reason":"stop"}]}
          """.utf8)),
    ]
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

  private func waitUntil(
    _ predicate: @escaping () async -> Bool,
    sourceLocation: SourceLocation = #_sourceLocation
  ) async {
    for _ in 0..<100 {
      if await predicate() {
        return
      }
      try? await Task.sleep(nanoseconds: 5_000_000)
    }
    Issue.record("Timed out waiting for state transition", sourceLocation: sourceLocation)
  }
}

private final class RecordingOpenAICompatibleTransport: OpenAICompatibleTransport,
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

private struct ChatCompletionsRequestBody: Decodable, Equatable {
  let model: String
  let stream: Bool
}
