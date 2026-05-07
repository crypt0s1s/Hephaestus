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
  func newTaskCreatesPersistedSessionAndClearsTranscript() async throws {
    let existingID = UUID()
    let newID = UUID()
    let sessions = StubSessionUseCase(
      sessions: [
        PersistedSession(id: existingID, title: "Existing")
      ],
      createdSession: PersistedSession(id: newID, title: "New Task")
    )
    let interactor = makeInteractor(
      runID: existingID,
      streamUserMessage: ImmediateStreamUserMessageUseCase(),
      listSessions: sessions,
      createSession: sessions
    )
    await interactor.handleAction(.changeDraft("stale"))

    await interactor.handleAction(.tapNewTask)

    #expect(interactor.state.runID == newID)
    #expect(interactor.state.messages.isEmpty)
    #expect(interactor.state.draftText.isEmpty)
    #expect(await sessions.createdCount() == 1)
  }

  @Test
  @MainActor
  func selectingTaskUpdatesNavigationRoute() async throws {
    let currentID = UUID()
    let targetID = UUID()
    let router = Router<AnyRouteInput, AnyModalInput>()
    let sessions = StubSessionUseCase(
      sessions: [
        PersistedSession(id: currentID, title: "Current"),
        PersistedSession(id: targetID, title: "Target"),
      ]
    )
    let interactor = makeInteractor(
      runID: currentID,
      streamUserMessage: ImmediateStreamUserMessageUseCase(),
      loadSession: sessions,
      router: router
    )

    await interactor.handleAction(.tapTask(targetID))

    let route = try #require(try router.path.last?.decode(TaskWorkspaceRouteInput.self))
    #expect(route.taskID == targetID)
  }

  @Test
  @MainActor
  func newTaskUpdatesNavigationRoute() async throws {
    let existingID = UUID()
    let newID = UUID()
    let router = Router<AnyRouteInput, AnyModalInput>()
    let sessions = StubSessionUseCase(
      sessions: [
        PersistedSession(id: existingID, title: "Existing")
      ],
      createdSession: PersistedSession(id: newID, title: "New Task")
    )
    let interactor = makeInteractor(
      runID: existingID,
      streamUserMessage: ImmediateStreamUserMessageUseCase(),
      createSession: sessions,
      router: router
    )

    await interactor.handleAction(.tapNewTask)

    let route = try #require(try router.path.last?.decode(TaskWorkspaceRouteInput.self))
    #expect(route.taskID == newID)
  }

  @Test
  @MainActor
  func sendFromUnloadableSelectedTaskSurfacesErrorWithoutCreatingNewTask() async throws {
    let missingID = UUID()
    let createRun = RecordingCreateRunUseCase(runID: UUID())
    let streamUserMessage = ImmediateStreamUserMessageUseCase()
    let interactor = makeInteractor(
      runID: missingID,
      createRun: createRun,
      streamUserMessage: streamUserMessage,
      loadSession: FailingLoadSessionUseCase()
    )

    await interactor.handleAction(.changeDraft("do not create"))
    await interactor.handleAction(.tapSend)

    #expect(!interactor.state.isRunning)
    #expect(interactor.state.draftText == "do not create")
    #expect(interactor.state.persistenceErrorMessage == nil)
    #expect(interactor.state.errorMessage?.contains("boom") == true)
    #expect(await createRun.calls() == 0)
    #expect(await streamUserMessage.requests().isEmpty)
  }

  @Test
  @MainActor
  func failedSelectedTaskLoadPreservesLoadedSidebarSummaries() async throws {
    let missingID = UUID()
    let listedID = UUID()
    let sessions = StubSessionUseCase(
      sessions: [
        PersistedSession(id: listedID, title: "Visible summary")
      ]
    )
    let interactor = makeInteractor(
      runID: missingID,
      streamUserMessage: ImmediateStreamUserMessageUseCase(),
      listSessions: sessions,
      loadSession: FailingLoadSessionUseCase()
    )

    interactor.onAppear()
    await waitUntil {
      interactor.state.sessionSummaries.count == 1
    }

    await interactor.handleAction(.changeDraft("keep sidebar"))
    await interactor.handleAction(.tapSend)

    #expect(interactor.state.sessionSummaries.map(\.title) == ["Visible summary"])
    #expect(!interactor.state.isLoadingSessions)
    #expect(interactor.state.persistenceErrorMessage == nil)
    #expect(interactor.state.errorMessage?.contains("boom") == true)
    #expect(interactor.state.draftText == "keep sidebar")
  }

  @Test
  @MainActor
  func failedRouteSendDoesNotUsePreviouslySelectedWorkspaceTask() async throws {
    let selectedID = UUID()
    let missingID = UUID()
    let sessions = StubSessionUseCase(
      sessions: [
        PersistedSession(id: selectedID, title: "Selected")
      ]
    )
    let streamUserMessage = ImmediateStreamUserMessageUseCase()
    let registry = TaskSessionServiceRegistry(
      createRun: RecordingCreateRunUseCase(runID: UUID()),
      streamUserMessage: streamUserMessage,
      loadSession: sessions
    )
    let workspace = TaskWorkspaceService(registry: registry, listSessions: sessions)
    await workspace.selectTask(selectedID, force: true)
    let interactor = makeInteractor(
      runID: missingID,
      streamUserMessage: streamUserMessage,
      workspace: workspace
    )

    await interactor.handleAction(.changeDraft("must not go to selected"))
    await interactor.handleAction(.tapSend)

    #expect(workspace.snapshot.selectedTaskID == nil)
    #expect(interactor.state.runID == missingID)
    #expect(interactor.state.draftText == "must not go to selected")
    #expect(interactor.state.errorMessage != nil)
    #expect(await streamUserMessage.requests().isEmpty)
  }

  @Test
  @MainActor
  func routePageDoesNotApplyPreviousWorkspaceSelectionBeforeInitialSelection() async throws {
    let selectedID = UUID()
    let missingID = UUID()
    let sessions = StubSessionUseCase(
      sessions: [
        PersistedSession(
          id: selectedID,
          title: "Selected",
          messages: [
            RunMessage(
              role: .user, parts: [.text("previous task")], source: .localUser, turnID: UUID())
          ]
        )
      ]
    )
    let streamUserMessage = ImmediateStreamUserMessageUseCase()
    let registry = TaskSessionServiceRegistry(
      createRun: RecordingCreateRunUseCase(runID: UUID()),
      streamUserMessage: streamUserMessage,
      loadSession: sessions
    )
    let workspace = TaskWorkspaceService(registry: registry, listSessions: sessions)
    await workspace.selectTask(selectedID, force: true)
    let interactor = makeInteractor(
      runID: missingID,
      streamUserMessage: streamUserMessage,
      workspace: workspace
    )

    interactor.onAppear()
    await waitUntil {
      interactor.state.errorMessage != nil
    }

    #expect(interactor.state.runID == missingID)
    #expect(interactor.state.messages.isEmpty)
    #expect(interactor.state.errorMessage != nil)
    #expect(workspace.snapshot.selectedTaskID == nil)
  }

  @Test
  @MainActor
  func providerSettingsValidateSaveAndClearUpdateState() async throws {
    let settings = StubProviderSettingsUseCase()
    let interactor = makeInteractor(
      runID: nil,
      streamUserMessage: ImmediateStreamUserMessageUseCase(),
      loadProviderSettings: settings,
      saveProviderSettings: settings,
      clearProviderSettings: settings,
      validateProviderSettings: settings
    )

    await interactor.handleAction(.tapSettings)
    await interactor.handleAction(.changeProviderBaseURL("https://example.test/v1"))
    await interactor.handleAction(.changeProviderAPIKey("secret"))
    await interactor.handleAction(.changeProviderModel("test-model"))
    await interactor.handleAction(.validateProviderSettings)
    #expect(interactor.state.providerSettings.validation == .success("Provider validated."))
    await interactor.handleAction(.saveProviderSettings)
    #expect(!interactor.state.providerSettings.isPresented)
    #expect(interactor.state.providerSettings.hasSavedAPIKey)
    #expect(await settings.savedDraft()?.model == "test-model")

    await interactor.handleAction(.tapSettings)
    await interactor.handleAction(.clearProviderSettings)
    #expect(!interactor.state.providerSettings.hasSavedAPIKey)
    #expect(await settings.wasCleared())
  }
}
