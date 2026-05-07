import Anvil
import Foundation
import HephaestusKernel
import HephaestusObservation
import HephaestusRuntime
import TaskWorkspaceContracts
import TaskWorkspaceFeature
import Testing

extension TaskWorkspaceInteractorTests {
  @Test
  @MainActor
  func inspectorLoadsRunInspectionState() async throws {
    let fixture = makeInspectableRunFixture()
    let inspector = StubLoadRunInspectionUseCase(
      inspection: RunInspectionSnapshot(inspection: fixture.inspection))
    let interactor = makeInteractor(
      runID: fixture.sessionID,
      streamUserMessage: ImmediateStreamUserMessageUseCase(),
      loadRunInspection: inspector
    )

    await interactor.handleAction(.tapInspector)

    #expect(interactor.state.inspector.isPresented)
    #expect(!interactor.state.inspector.isLoading)
    #expect(interactor.state.inspector.inspection?.events.first?.error == "network down")
    #expect(interactor.state.inspector.inspection?.contextTraces.first?.messageLimit == 20)
  }

  @Test
  @MainActor
  func persistenceErrorIsSurfacedWhenHistoryLoadFails() async throws {
    let sessions = FailingListSessionsUseCase()
    let interactor = makeInteractor(
      runID: nil,
      streamUserMessage: ImmediateStreamUserMessageUseCase(),
      listSessions: sessions
    )

    interactor.onAppear()
    await waitUntil {
      interactor.state.persistenceErrorMessage != nil
    }

    #expect(interactor.state.persistenceErrorMessage?.contains("boom") == true)
  }

  @Test
  @MainActor
  func serviceContinuesResponseWithoutSnapshotSubscriber() async throws {
    let runID = UUID()
    let streamUserMessage = ControlledStreamUserMessageUseCase()
    let service = TaskSessionService(
      snapshot: TaskSessionSnapshot(id: runID, title: "Detached"),
      streamUserMessage: streamUserMessage
    )

    service.send("detached question")

    await streamUserMessage.waitUntilRequestCount(1)
    await streamUserMessage.yield(
      .userMessageAccepted(
        runtimeHeader(runID: runID, turnID: UUID(), sequence: 1),
        messageID: UUID(),
        text: "detached question"
      ))
    await streamUserMessage.yield(
      .assistantMessageCompleted(
        runtimeHeader(runID: runID, turnID: UUID(), sequence: 2),
        messageID: UUID(),
        text: "detached answer"
      ))
    await streamUserMessage.finish()

    await waitUntil {
      !service.snapshot.isRunning
        && service.snapshot.messages.map(\.text) == ["detached question", "detached answer"]
    }
  }

  @Test
  @MainActor
  func pageDisappearDetachesWithoutCancellingSelectedService() async throws {
    let runID = UUID()
    let streamUserMessage = ControlledStreamUserMessageUseCase()
    let registry = TaskSessionServiceRegistry(
      createRun: RecordingCreateRunUseCase(runID: runID),
      streamUserMessage: streamUserMessage
    )
    let interactor = makeInteractor(
      runID: runID,
      streamUserMessage: streamUserMessage,
      sessionRegistry: registry
    )

    interactor.onAppear()
    await interactor.handleAction(.changeDraft("keep running"))
    await interactor.handleAction(.tapSend)
    await streamUserMessage.waitUntilRequestCount(1)
    #expect(interactor.state.isRunning)

    interactor.onDisappear()
    let service = try await registry.service(for: runID)

    await yieldDetachedCompletion(runID: runID, streamUserMessage: streamUserMessage)
    await streamUserMessage.finish()

    await waitUntil {
      !service.snapshot.isRunning
        && service.snapshot.messages.map(\.text) == ["keep running", "finished while hidden"]
    }
    #expect(interactor.state.isRunning)

    interactor.onAppear()
    await waitUntil {
      !interactor.state.isRunning
        && interactor.state.messages.map(\.text) == ["keep running", "finished while hidden"]
    }
  }

  @Test
  @MainActor
  func explicitCancelStopsSelectedServiceActiveTurn() async throws {
    let runID = UUID()
    let streamUserMessage = ControlledStreamUserMessageUseCase()
    let registry = TaskSessionServiceRegistry(
      createRun: RecordingCreateRunUseCase(runID: runID),
      streamUserMessage: streamUserMessage
    )
    let interactor = makeInteractor(
      runID: runID,
      streamUserMessage: streamUserMessage,
      sessionRegistry: registry
    )

    await interactor.handleAction(.changeDraft("cancel me"))
    await interactor.handleAction(.tapSend)
    await streamUserMessage.waitUntilRequestCount(1)
    #expect(interactor.state.isRunning)

    await interactor.handleAction(.tapCancel)
    let service = try await registry.service(for: runID)

    await waitUntil {
      !interactor.state.isRunning
        && !service.snapshot.isRunning
    }
    await streamUserMessage.waitUntilTerminationCount(1)
  }

  @Test
  @MainActor
  func registryReloadsPersistedSessionSnapshotIntoService() async throws {
    let sessionID = UUID()
    let turnID = UUID()
    let user = RunMessage(
      role: .user, parts: [.text("saved question")], source: .localUser, turnID: turnID)
    let assistant = RunMessage(
      role: .assistant, parts: [.text("saved answer")], source: .provider, turnID: turnID)
    let sessions = StubSessionUseCase(
      sessions: [
        PersistedSession(id: sessionID, title: "Saved", messages: [user, assistant])
      ]
    )
    let registry = TaskSessionServiceRegistry(
      createRun: RecordingCreateRunUseCase(runID: UUID()),
      streamUserMessage: ImmediateStreamUserMessageUseCase(),
      loadSession: sessions
    )

    let service = try await registry.service(for: sessionID)

    #expect(service.snapshot.id == sessionID)
    #expect(service.snapshot.title == "Saved")
    #expect(service.snapshot.messages.map(\.text) == ["saved question", "saved answer"])
    #expect(await sessions.loadedCount() == 1)
  }
}

private func makeInspectableRunFixture() -> (
  sessionID: UUID,
  inspection: PersistedRunInspection
) {
  let sessionID = UUID()
  let turnID = UUID()
  let message = RunMessage(
    role: .user,
    parts: [.text("inspect me")],
    source: .localUser,
    turnID: turnID
  )
  let inspection = PersistedRunInspection(
    session: PersistedSession(
      id: sessionID,
      title: "Inspectable",
      messages: [message],
      turns: [Turn(id: turnID, runID: sessionID, status: .failed, userMessageID: message.id)],
      events: [failedInspectionEvent(runID: sessionID, turnID: turnID)],
      contextTraces: [inspectionContextTrace(runID: sessionID, turnID: turnID, messageID: message.id)]
    ))
  return (sessionID, inspection)
}

private func failedInspectionEvent(runID: UUID, turnID: UUID) -> PersistedRuntimeEvent {
  PersistedRuntimeEvent(
    id: UUID(),
    runID: runID,
    turnID: turnID,
    sequence: 1,
    createdAt: Date(),
    kind: .turnFailed,
    summary: "Turn failed",
    error: "network down"
  )
}

private func inspectionContextTrace(
  runID: UUID,
  turnID: UUID,
  messageID: UUID
) -> PersistedContextTrace {
  PersistedContextTrace(
    runID: runID,
    turnID: turnID,
    policyID: "recent",
    policyName: "Recent messages",
    messageLimit: 20,
    includedMessageIDs: [messageID],
    excludedMessageIDs: [],
    createdAt: Date()
  )
}

@MainActor
private func yieldDetachedCompletion(
  runID: UUID,
  streamUserMessage: ControlledStreamUserMessageUseCase
) async {
  await streamUserMessage.yield(
    .userMessageAccepted(
      runtimeHeader(runID: runID, turnID: UUID(), sequence: 1),
      messageID: UUID(),
      text: "keep running"
    ))
  await streamUserMessage.yield(
    .assistantMessageCompleted(
      runtimeHeader(runID: runID, turnID: UUID(), sequence: 2),
      messageID: UUID(),
      text: "finished while hidden"
    ))
}
