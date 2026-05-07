import Anvil
import Foundation
import HephaestusComposition
import HephaestusKernel
import HephaestusLLM
import HephaestusRuntime
import TaskWorkspaceContracts
import TaskWorkspaceFeature
import Testing

@Suite
struct RuntimeStreamingTests {
  @Test
  func mockRuntimeStreamsMultipleDeltas() async throws {
    let harness = MockRuntimeComposition.make()
    let runID = await harness.createRun.createRun()

    let events = try await collect(
      harness.streamUserMessage.streamUserMessage(runID: runID, text: "hello")
    )

    let deltas = events.compactMap { event -> String? in
      if case .assistantTextDelta(_, let text) = event {
        return text
      }
      return nil
    }
    let completed = events.compactMap { event -> String? in
      if case .assistantMessageCompleted(_, _, let text) = event {
        return text
      }
      return nil
    }

    #expect(deltas.count > 1)
    #expect(deltas.joined() == completed.last)
    #expect(completed.last?.contains("hello") == true)
    #expect(events.map(\.header.runID).allSatisfy { $0 == runID })
    #expect(events.map(\.header.sequence) == Array(1...events.count))
  }

  @Test
  func secondTurnIncludesPriorContextAndCurrentMessageOnce() async throws {
    let harness = MockRuntimeComposition.make()
    let runID = await harness.createRun.createRun()

    _ = try await collect(
      harness.streamUserMessage.streamUserMessage(runID: runID, text: "first")
    )
    _ = try await collect(
      harness.streamUserMessage.streamUserMessage(runID: runID, text: "second")
    )

    let requests = await harness.recorder.allRequests()
    #expect(requests.count == 2)
    #expect(requests[1].messages.contains(ProviderMessage(role: .user, text: "first")))
    #expect(
      requests[1].messages.contains(where: { $0.role == .assistant && $0.text.contains("first") }))
    #expect(requests[1].messages.filter { $0.role == .user && $0.text == "second" }.count == 1)
  }

  @Test
  func finalSubmitApiIsLayeredOverStreamingPath() async throws {
    let harness = MockRuntimeComposition.make()
    let runID = await harness.createRun.createRun()

    let response = try await harness.submitUserMessage.submitUserMessage(
      runID: runID,
      text: "final"
    )

    #expect(response.contains("final"))
    let requests = await harness.recorder.allRequests()
    #expect(requests.count == 1)
  }

  @Test
  func runUsesOneTurnIDAcrossEventsMessagesAndProviderRequest() async throws {
    let recorder = MockProviderRecorder()
    let profile = AgentProfile(
      name: "Identity Agent",
      systemPrompt: "Keep IDs consistent.",
      defaultModel: "mock-model",
      contextPolicyID: "recent"
    )
    let run = Run(
      agent: Agent(name: "Identity Agent", profile: profile),
      contextManager: RecentContextManager(),
      provider: MockProviderClient(recorder: recorder)
    )

    let events = try await collect(run.streamUserMessage("identity"))
    let requests = await recorder.allRequests()

    let accepted = try #require(events.firstUserMessageAccepted)
    let completed = try #require(events.firstAssistantCompleted)
    let request = try #require(requests.first)

    #expect(accepted.header.turnID == accepted.message.turnID)
    #expect(completed.header.turnID == completed.message.turnID)
    #expect(request.turnID == accepted.header.turnID)
    #expect(request.turnID == completed.header.turnID)
  }

  @Test
  func observeRunEventsReceivesSubmittedTurnEvents() async throws {
    let harness = MockRuntimeComposition.make()
    let runID = await harness.createRun.createRun()
    let observedStream = try await harness.observeRunEvents.events(runID: runID)

    async let observedEvents = collectThroughAssistantCompletion(observedStream)

    _ = try await collect(
      harness.streamUserMessage.streamUserMessage(runID: runID, text: "observed")
    )

    let observed = await observedEvents
    #expect(
      observed.contains(where: { event in
        if case .assistantTextDelta = event { return true }
        return false
      }))
    #expect(
      observed.contains(where: { event in
        if case .assistantMessageCompleted(_, _, let text) = event {
          return text.contains("observed")
        }
        return false
      }))
  }

  @Test
  func invalidTaskIDDeepLinkIsRejected() throws {
    let registry = try DestinationRegistry(
      routes: [TaskWorkspaceRoutes.registration],
      modals: []
    )
    let url = try #require(URL(string: "hephaestus://route/hephaestus.task.workspace?taskID=bad"))

    #expect(throws: DestinationRegistryError.unsupportedDeepLink(url)) {
      _ = try registry.decodeDeepLink(url)
    }
  }

  @Test
  @MainActor
  func taskWorkspaceRouteRequiresWorkspaceService() throws {
    let registry = try DestinationRegistry(
      routes: [TaskWorkspaceRoutes.registration],
      modals: []
    )
    let input = try AnyRouteInput(TaskWorkspaceRouteInput(taskID: nil))
    let context = RouteBuildContext(router: Router<AnyRouteInput, AnyModalInput>()) { type in
      throw RouteBuildError.missingDependency(String(describing: type))
    }

    #expect(throws: RouteBuildError.missingDependency("TaskWorkspaceService")) {
      _ = try registry.buildRoute(input, context: context)
    }
  }

  @Test
  @MainActor
  func taskWorkspaceRouteBuildsWithWorkspaceServiceAndNoSessionRegistryDependency() throws {
    let registry = try DestinationRegistry(
      routes: [TaskWorkspaceRoutes.registration],
      modals: []
    )
    let input = try AnyRouteInput(TaskWorkspaceRouteInput(taskID: nil))
    let workspace = TaskWorkspaceService(
      registry: TaskSessionServiceRegistry(
        createRun: BlockingCreateRunUseCase(runID: UUID()),
        streamUserMessage: RecordingStreamUserMessageUseCase()
      )
    )
    let context = RouteBuildContext(router: Router<AnyRouteInput, AnyModalInput>()) { type in
      if type == TaskWorkspaceService.self {
        return workspace
      }
      throw RouteBuildError.missingDependency(String(describing: type))
    }

    _ = try registry.buildRoute(input, context: context)
  }

  @Test
  @MainActor
  func tapSendMarksRunningBeforeAwaitingRunCreation() async throws {
    let runID = UUID()
    let createRun = BlockingCreateRunUseCase(runID: runID)
    let streamUserMessage = RecordingStreamUserMessageUseCase()
    let sessionRegistry = TaskSessionServiceRegistry(
      createRun: createRun,
      streamUserMessage: streamUserMessage
    )
    let workspace = TaskWorkspaceService(registry: sessionRegistry)
    let interactor = TaskWorkspaceInteractor(
      input: TaskWorkspaceRouteInput(taskID: nil),
      workspace: workspace
    )

    await interactor.handleAction(.changeDraft("first"))

    let sendTask = Task {
      await interactor.handleAction(.tapSend)
    }

    await createRun.waitUntilCallCount(1)

    #expect(interactor.state.isRunning)
    #expect(interactor.state.draftText == "")
    #expect(interactor.state.errorMessage == nil)

    await createRun.releaseAll()
    await sendTask.value

    #expect(await streamUserMessage.requests() == [StreamRequest(runID: runID, text: "first")])
  }

  @Test
  @MainActor
  func tapSendIgnoresEmptyDraft() async throws {
    let createRun = BlockingCreateRunUseCase(runID: UUID())
    let streamUserMessage = RecordingStreamUserMessageUseCase()
    let sessionRegistry = TaskSessionServiceRegistry(
      createRun: createRun,
      streamUserMessage: streamUserMessage
    )
    let workspace = TaskWorkspaceService(registry: sessionRegistry)
    let interactor = TaskWorkspaceInteractor(
      input: TaskWorkspaceRouteInput(taskID: nil),
      workspace: workspace
    )

    await interactor.handleAction(.changeDraft(" \n "))
    await interactor.handleAction(.tapSend)

    #expect(!interactor.state.isRunning)
    #expect(interactor.state.draftText == " \n ")
    #expect(await createRun.calls() == 0)
    #expect(await streamUserMessage.requests().isEmpty)
  }

  @Test
  @MainActor
  func tapSendIgnoresSecondSubmitWhileRunning() async throws {
    let runID = UUID()
    let createRun = BlockingCreateRunUseCase(runID: runID)
    let streamUserMessage = RecordingStreamUserMessageUseCase()
    let sessionRegistry = TaskSessionServiceRegistry(
      createRun: createRun,
      streamUserMessage: streamUserMessage
    )
    let workspace = TaskWorkspaceService(registry: sessionRegistry)
    let interactor = TaskWorkspaceInteractor(
      input: TaskWorkspaceRouteInput(taskID: nil),
      workspace: workspace
    )

    await interactor.handleAction(.changeDraft("first"))

    let sendTask = Task {
      await interactor.handleAction(.tapSend)
    }

    await createRun.waitUntilCallCount(1)
    await interactor.handleAction(.changeDraft("second"))
    await interactor.handleAction(.tapSend)

    #expect(await createRun.calls() == 1)
    #expect(await streamUserMessage.requests().isEmpty)

    await createRun.releaseAll()
    await sendTask.value

    #expect(await streamUserMessage.requests() == [StreamRequest(runID: runID, text: "first")])
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

  private func collect(
    _ stream: AsyncThrowingStream<RunEvent, Error>
  ) async throws -> [RunEvent] {
    var events: [RunEvent] = []
    for try await event in stream {
      events.append(event)
    }
    return events
  }

  private func collectThroughAssistantCompletion(
    _ stream: AsyncStream<RuntimeEvent>
  ) async -> [RuntimeEvent] {
    var events: [RuntimeEvent] = []
    for await event in stream {
      events.append(event)
      if case .assistantMessageCompleted = event {
        break
      }
    }
    return events
  }
}
