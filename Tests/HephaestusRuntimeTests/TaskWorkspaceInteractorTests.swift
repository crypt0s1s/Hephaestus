import Anvil
import Foundation
import HephaestusKernel
import HephaestusObservation
import HephaestusRuntime
import TaskWorkspaceContracts
import TaskWorkspaceFeature
import Testing

@Suite
struct TaskWorkspaceInteractorTests {
  @Test
  @MainActor
  func progressiveStreamingBuildsAssistantBubbleThenCompletesIt() async throws {
    let runID = UUID()
    let streamUserMessage = ControlledStreamUserMessageUseCase()
    let interactor = makeInteractor(
      runID: runID,
      streamUserMessage: streamUserMessage
    )
    interactor.onAppear()

    await interactor.handleAction(.changeDraft("plan the slice"))
    let sendTask = Task {
      await interactor.handleAction(.tapSend)
    }

    await streamUserMessage.waitUntilRequestCount(1)
    #expect(interactor.state.isRunning)
    #expect(interactor.state.draftText == "")

    let completedMessageID = await yieldProgressiveDraft(
      runID: runID,
      streamUserMessage: streamUserMessage,
      interactor: interactor
    )
    await streamUserMessage.finish()
    await sendTask.value
    await waitUntil {
      !interactor.state.isRunning
        && interactor.state.messages.last?.id == completedMessageID
    }

    assertProgressiveDraftCompleted(interactor, completedMessageID: completedMessageID)
  }

  @Test
  @MainActor
  func failedTurnShowsErrorStopsStreamingAndNextSendRecovers() async throws {
    let runID = UUID()
    let streamUserMessage = ControlledStreamUserMessageUseCase()
    let interactor = makeInteractor(
      runID: runID,
      streamUserMessage: streamUserMessage
    )
    interactor.onAppear()

    await interactor.handleAction(.changeDraft("first"))
    let failedSend = Task {
      await interactor.handleAction(.tapSend)
    }

    await streamUserMessage.waitUntilRequestCount(1)
    await yieldFailedTurn(
      runID: runID,
      streamUserMessage: streamUserMessage,
      interactor: interactor
    )
    await streamUserMessage.finish()
    await failedSend.value
    await waitUntil {
      !interactor.state.isRunning
        && interactor.state.errorMessage == "provider unavailable"
    }

    assertFailedTurnStoppedStreaming(interactor)

    await interactor.handleAction(.changeDraft("second"))
    let recoverySend = Task {
      await interactor.handleAction(.tapSend)
    }

    await streamUserMessage.waitUntilRequestCount(2)
    await yieldRecoveredTurn(runID: runID, streamUserMessage: streamUserMessage)
    await streamUserMessage.finish()
    await recoverySend.value
    await waitUntil {
      !interactor.state.isRunning
        && Array(interactor.state.messages.map(\.text).suffix(2)) == ["second", "recovered"]
    }

    assertRecoveredTurnCompleted(interactor)
  }

  @Test
  @MainActor
  func inFlightResponseDoesNotAppendToNewlySelectedTask() async throws {
    let originalID = UUID()
    let targetID = UUID()
    let targetMessage = RunMessage(
      role: .user,
      parts: [.text("target question")],
      source: .localUser,
      turnID: UUID()
    )
    let streamUserMessage = ControlledStreamUserMessageUseCase()
    let sessions = StubSessionUseCase(
      sessions: [
        PersistedSession(id: originalID, title: "Original"),
        PersistedSession(id: targetID, title: "Target", messages: [targetMessage]),
      ]
    )
    let interactor = makeInteractor(
      runID: originalID,
      streamUserMessage: streamUserMessage,
      loadSession: sessions
    )
    interactor.onAppear()

    await interactor.handleAction(.changeDraft("slow question"))
    let sendTask = Task {
      await interactor.handleAction(.tapSend)
    }

    await streamUserMessage.waitUntilRequestCount(1)
    await interactor.handleAction(.tapTask(targetID))

    #expect(interactor.state.runID == targetID)
    #expect(interactor.state.messages.map(\.text) == ["target question"])
    #expect(!interactor.state.isRunning)

    await yieldOriginalTaskResponse(runID: originalID, streamUserMessage: streamUserMessage)
    await streamUserMessage.finish()
    await sendTask.value
    await waitUntil {
      !interactor.state.isRunning
    }

    #expect(interactor.state.runID == targetID)
    #expect(interactor.state.messages.map(\.text) == ["target question"])
    #expect(interactor.state.errorMessage == nil)
    #expect(!interactor.state.isRunning)
  }
}

@MainActor
private func assertProgressiveDraftCompleted(
  _ interactor: TaskWorkspaceInteractor,
  completedMessageID: UUID
) {
  #expect(
    interactor.state.messages == [
      ConversationMessageState(
        id: interactor.state.messages[0].id,
        role: .user,
        text: "plan the slice"
      ),
      ConversationMessageState(
        id: completedMessageID,
        role: .assistant,
        text: "First draft",
        isStreaming: false
      ),
    ])
  #expect(!interactor.state.isRunning)
  #expect(interactor.state.errorMessage == nil)
}

@MainActor
private func assertFailedTurnStoppedStreaming(_ interactor: TaskWorkspaceInteractor) {
  #expect(interactor.state.errorMessage == "provider unavailable")
  #expect(!interactor.state.isRunning)
  #expect(interactor.state.messages.last?.text == "partial")
  #expect(interactor.state.messages.last?.isStreaming == false)
}

@MainActor
private func assertRecoveredTurnCompleted(_ interactor: TaskWorkspaceInteractor) {
  #expect(interactor.state.errorMessage == nil)
  #expect(!interactor.state.isRunning)
  #expect(Array(interactor.state.messages.map(\.text).suffix(2)) == ["second", "recovered"])
}

@MainActor
private func yieldOriginalTaskResponse(
  runID: UUID,
  streamUserMessage: ControlledStreamUserMessageUseCase
) async {
  let turnID = UUID()
  await streamUserMessage.yield(
    .userMessageAccepted(
      runtimeHeader(runID: runID, turnID: turnID, sequence: 1),
      messageID: UUID(),
      text: "slow question"
    ))
  await streamUserMessage.yield(
    .assistantTextDelta(
      runtimeHeader(runID: runID, turnID: turnID, sequence: 2),
      "wrong task"
    ))
  await streamUserMessage.yield(
    .assistantMessageCompleted(
      runtimeHeader(runID: runID, turnID: turnID, sequence: 3),
      messageID: UUID(),
      text: "wrong task"
    ))
}

@MainActor
private func yieldProgressiveDraft(
  runID: UUID,
  streamUserMessage: ControlledStreamUserMessageUseCase,
  interactor: TaskWorkspaceInteractor
) async -> UUID {
  await streamUserMessage.yield(
    .userMessageAccepted(
      runtimeHeader(runID: runID, turnID: UUID(), sequence: 1),
      messageID: UUID(),
      text: "plan the slice"
    ))
  await waitUntil { interactor.state.messages.count == 1 }
  await streamUserMessage.yield(
    .assistantTextDelta(runtimeHeader(runID: runID, turnID: UUID(), sequence: 2), "First "))
  await waitUntil {
    interactor.state.messages.last?.text == "First "
      && interactor.state.messages.last?.isStreaming == true
  }
  await streamUserMessage.yield(
    .assistantTextDelta(runtimeHeader(runID: runID, turnID: UUID(), sequence: 3), "draft"))
  await waitUntil { interactor.state.messages.last?.text == "First draft" }
  let completedMessageID = UUID()
  await streamUserMessage.yield(
    .assistantMessageCompleted(
      runtimeHeader(runID: runID, turnID: UUID(), sequence: 4),
      messageID: completedMessageID,
      text: "First draft"
    ))
  return completedMessageID
}

@MainActor
private func yieldFailedTurn(
  runID: UUID,
  streamUserMessage: ControlledStreamUserMessageUseCase,
  interactor: TaskWorkspaceInteractor
) async {
  await streamUserMessage.yield(
    .userMessageAccepted(
      runtimeHeader(runID: runID, turnID: UUID(), sequence: 1),
      messageID: UUID(),
      text: "first"
    ))
  await streamUserMessage.yield(
    .assistantTextDelta(runtimeHeader(runID: runID, turnID: UUID(), sequence: 2), "partial"))
  await waitUntil { interactor.state.messages.last?.isStreaming == true }
  await streamUserMessage.yield(
    .turnFailed(
      runtimeHeader(runID: runID, turnID: UUID(), sequence: 3),
      "provider unavailable"
    ))
}

private func yieldRecoveredTurn(
  runID: UUID,
  streamUserMessage: ControlledStreamUserMessageUseCase
) async {
  await streamUserMessage.yield(
    .userMessageAccepted(
      runtimeHeader(runID: runID, turnID: UUID(), sequence: 4),
      messageID: UUID(),
      text: "second"
    ))
  await streamUserMessage.yield(
    .assistantMessageCompleted(
      runtimeHeader(runID: runID, turnID: UUID(), sequence: 5),
      messageID: UUID(),
      text: "recovered"
    ))
}
