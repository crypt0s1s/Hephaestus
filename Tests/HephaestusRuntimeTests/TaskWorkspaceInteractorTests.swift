import Anvil
import Foundation
import HephaestusKernel
import HephaestusObservation
import HephaestusRuntime
import TaskWorkspaceFeature
import TaskWorkspaceContracts
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

        await streamUserMessage.yield(.userMessageAccepted(
            runtimeHeader(runID: runID, turnID: UUID(), sequence: 1),
            messageID: UUID(),
            text: "plan the slice"
        ))
        await waitUntil {
            interactor.state.messages.count == 1
        }

        await streamUserMessage.yield(.assistantTextDelta(
            runtimeHeader(runID: runID, turnID: UUID(), sequence: 2),
            "First "
        ))
        await waitUntil {
            interactor.state.messages.last?.text == "First "
            && interactor.state.messages.last?.isStreaming == true
        }

        await streamUserMessage.yield(.assistantTextDelta(
            runtimeHeader(runID: runID, turnID: UUID(), sequence: 3),
            "draft"
        ))
        await waitUntil {
            interactor.state.messages.last?.text == "First draft"
        }

        let completedMessageID = UUID()
        await streamUserMessage.yield(.assistantMessageCompleted(
            runtimeHeader(runID: runID, turnID: UUID(), sequence: 4),
            messageID: completedMessageID,
            text: "First draft"
        ))
        await streamUserMessage.finish()
        await sendTask.value
        await waitUntil {
            !interactor.state.isRunning
            && interactor.state.messages.last?.id == completedMessageID
        }

        #expect(interactor.state.messages == [
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
            )
        ])
        #expect(!interactor.state.isRunning)
        #expect(interactor.state.errorMessage == nil)
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
        await streamUserMessage.yield(.userMessageAccepted(
            runtimeHeader(runID: runID, turnID: UUID(), sequence: 1),
            messageID: UUID(),
            text: "first"
        ))
        await streamUserMessage.yield(.assistantTextDelta(
            runtimeHeader(runID: runID, turnID: UUID(), sequence: 2),
            "partial"
        ))
        await waitUntil {
            interactor.state.messages.last?.isStreaming == true
        }

        await streamUserMessage.yield(.turnFailed(
            runtimeHeader(runID: runID, turnID: UUID(), sequence: 3),
            "provider unavailable"
        ))
        await streamUserMessage.finish()
        await failedSend.value
        await waitUntil {
            !interactor.state.isRunning
            && interactor.state.errorMessage == "provider unavailable"
        }

        #expect(interactor.state.errorMessage == "provider unavailable")
        #expect(!interactor.state.isRunning)
        #expect(interactor.state.messages.last?.text == "partial")
        #expect(interactor.state.messages.last?.isStreaming == false)

        await interactor.handleAction(.changeDraft("second"))
        let recoverySend = Task {
            await interactor.handleAction(.tapSend)
        }

        await streamUserMessage.waitUntilRequestCount(2)
        await streamUserMessage.yield(.userMessageAccepted(
            runtimeHeader(runID: runID, turnID: UUID(), sequence: 4),
            messageID: UUID(),
            text: "second"
        ))
        await streamUserMessage.yield(.assistantMessageCompleted(
            runtimeHeader(runID: runID, turnID: UUID(), sequence: 5),
            messageID: UUID(),
            text: "recovered"
        ))
        await streamUserMessage.finish()
        await recoverySend.value
        await waitUntil {
            !interactor.state.isRunning
            && Array(interactor.state.messages.map(\.text).suffix(2)) == ["second", "recovered"]
        }

        #expect(interactor.state.errorMessage == nil)
        #expect(!interactor.state.isRunning)
        #expect(Array(interactor.state.messages.map(\.text).suffix(2)) == ["second", "recovered"])
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
                PersistedSession(id: targetID, title: "Target", messages: [targetMessage])
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

        let turnID = UUID()
        await streamUserMessage.yield(.userMessageAccepted(
            runtimeHeader(runID: originalID, turnID: turnID, sequence: 1),
            messageID: UUID(),
            text: "slow question"
        ))
        await streamUserMessage.yield(.assistantTextDelta(
            runtimeHeader(runID: originalID, turnID: turnID, sequence: 2),
            "wrong task"
        ))
        await streamUserMessage.yield(.assistantMessageCompleted(
            runtimeHeader(runID: originalID, turnID: turnID, sequence: 3),
            messageID: UUID(),
            text: "wrong task"
        ))
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

    @Test
    @MainActor
    func nilInputRunCreatesOnceAndReusesRunForLaterTurns() async throws {
        let runID = UUID()
        let createRun = RecordingCreateRunUseCase(runID: runID)
        let streamUserMessage = ImmediateStreamUserMessageUseCase()
        let interactor = makeInteractor(
            runID: nil,
            createRun: createRun,
            streamUserMessage: streamUserMessage
        )
        interactor.onAppear()

        await interactor.handleAction(.changeDraft("first"))
        await interactor.handleAction(.tapSend)
        await waitUntil {
            !interactor.state.isRunning
            && interactor.state.messages.last?.text == "done first"
        }
        await interactor.handleAction(.changeDraft("second"))
        await interactor.handleAction(.tapSend)
        await waitUntil {
            !interactor.state.isRunning
            && interactor.state.messages.last?.text == "done second"
        }

        #expect(await createRun.calls() == 1)
        #expect(interactor.state.runID == runID)
        #expect(await streamUserMessage.requests() == [
            ConversationStreamRequest(runID: runID, text: "first"),
            ConversationStreamRequest(runID: runID, text: "second")
        ])
    }

    @Test
    @MainActor
    func loadingStateTransitionsAroundControlledStream() async throws {
        let runID = UUID()
        let streamUserMessage = ControlledStreamUserMessageUseCase()
        let interactor = makeInteractor(
            runID: runID,
            streamUserMessage: streamUserMessage
        )
        interactor.onAppear()

        await interactor.handleAction(.changeDraft("loading"))
        #expect(!interactor.state.isRunning)

        let sendTask = Task {
            await interactor.handleAction(.tapSend)
        }

        await streamUserMessage.waitUntilRequestCount(1)
        #expect(interactor.state.isRunning)
        #expect(interactor.state.draftText == "")
        #expect(interactor.state.errorMessage == nil)

        await streamUserMessage.yield(.assistantMessageCompleted(
            runtimeHeader(runID: runID, turnID: UUID(), sequence: 1),
            messageID: UUID(),
            text: "done"
        ))
        await streamUserMessage.finish()
        await sendTask.value
        await waitUntil {
            !interactor.state.isRunning
            && interactor.state.messages.last?.text == "done"
        }

        #expect(!interactor.state.isRunning)
        #expect(interactor.state.messages.last?.text == "done")
    }

    @Test
    @MainActor
    func secondSendWhileRunningDoesNotStartAnotherStream() async throws {
        let runID = UUID()
        let streamUserMessage = ControlledStreamUserMessageUseCase()
        let interactor = makeInteractor(
            runID: runID,
            streamUserMessage: streamUserMessage
        )
        interactor.onAppear()

        await interactor.handleAction(.changeDraft("first"))
        let sendTask = Task {
            await interactor.handleAction(.tapSend)
        }

        await streamUserMessage.waitUntilRequestCount(1)
        await interactor.handleAction(.changeDraft("second"))
        await interactor.handleAction(.tapSend)

        #expect(await streamUserMessage.requests() == [
            ConversationStreamRequest(runID: runID, text: "first")
        ])
        #expect(interactor.state.draftText == "second")

        await streamUserMessage.yield(.assistantMessageCompleted(
            runtimeHeader(runID: runID, turnID: UUID(), sequence: 1),
            messageID: UUID(),
            text: "done"
        ))
        await streamUserMessage.finish()
        await sendTask.value
        await waitUntil {
            !interactor.state.isRunning
        }

        #expect(!interactor.state.isRunning)
    }

    @Test
    @MainActor
    func onAppearLoadsPersistedSessionHistory() async throws {
        let sessionID = UUID()
        let sessions = StubSessionUseCase(
            sessions: [
                PersistedSession(
                    id: sessionID,
                    title: "Prior task",
                    updatedAt: Date(),
                    messages: [
                        RunMessage(role: .user, parts: [.text("hello")], source: .localUser, turnID: UUID())
                    ]
                )
            ]
        )
        let interactor = makeInteractor(
            runID: nil,
            streamUserMessage: ImmediateStreamUserMessageUseCase(),
            listSessions: sessions
        )

        interactor.onAppear()
        await waitUntil {
            interactor.state.sessionSummaries.count == 1
        }

        #expect(interactor.state.sessionSummaries.first?.id == sessionID)
        #expect(interactor.state.sessionSummaries.first?.title == "Prior task")
    }

    @Test
    @MainActor
    func openingPersistedSessionRendersMessages() async throws {
        let sessionID = UUID()
        let turnID = UUID()
        let user = RunMessage(role: .user, parts: [.text("saved question")], source: .localUser, turnID: turnID)
        let assistant = RunMessage(role: .assistant, parts: [.text("saved answer")], source: .provider, turnID: turnID)
        let sessions = StubSessionUseCase(
            sessions: [
                PersistedSession(id: sessionID, title: "Saved", messages: [user, assistant])
            ]
        )
        let interactor = makeInteractor(
            runID: nil,
            streamUserMessage: ImmediateStreamUserMessageUseCase(),
            listSessions: sessions,
            loadSession: sessions
        )

        await interactor.handleAction(.tapTask(sessionID))

        #expect(interactor.state.runID == sessionID)
        #expect(interactor.state.messages.map(\.text) == ["saved question", "saved answer"])
    }

    @Test
    @MainActor
    func openingDifferentSessionDoesNotReloadSidebarList() async throws {
        let currentID = UUID()
        let targetID = UUID()
        let user = RunMessage(role: .user, parts: [.text("target question")], source: .localUser, turnID: UUID())
        let sessions = StubSessionUseCase(
            sessions: [
                PersistedSession(id: currentID, title: "Current"),
                PersistedSession(id: targetID, title: "Target", messages: [user])
            ]
        )
        let interactor = makeInteractor(
            runID: currentID,
            streamUserMessage: ImmediateStreamUserMessageUseCase(),
            listSessions: sessions,
            loadSession: sessions
        )

        await interactor.handleAction(.tapTask(targetID))

        #expect(interactor.state.runID == targetID)
        #expect(interactor.state.messages.map(\.text) == ["target question"])
        #expect(!interactor.state.isLoadingSessions)
        #expect(await sessions.loadedCount() == 1)
        #expect(await sessions.listedCount() == 0)
    }

    @Test
    @MainActor
    func openingCurrentlySelectedSessionDoesNotReload() async throws {
        let sessionID = UUID()
        let sessions = StubSessionUseCase(
            sessions: [
                PersistedSession(
                    id: sessionID,
                    title: "Selected",
                    messages: [
                        RunMessage(role: .user, parts: [.text("original")], source: .localUser, turnID: UUID())
                    ]
                )
            ]
        )
        let interactor = makeInteractor(
            runID: sessionID,
            streamUserMessage: ImmediateStreamUserMessageUseCase(),
            listSessions: sessions,
            loadSession: sessions
        )
        await interactor.handleAction(.changeDraft("keep me"))

        await interactor.handleAction(.tapTask(sessionID))

        #expect(await sessions.loadedCount() == 0)
        #expect(interactor.state.draftText == "keep me")
        #expect(interactor.state.messages.isEmpty)
    }

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
                PersistedSession(id: targetID, title: "Target")
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
                        RunMessage(role: .user, parts: [.text("previous task")], source: .localUser, turnID: UUID())
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

    @Test
    @MainActor
    func inspectorLoadsRunInspectionState() async throws {
        let sessionID = UUID()
        let turnID = UUID()
        let message = RunMessage(role: .user, parts: [.text("inspect me")], source: .localUser, turnID: turnID)
        let inspection = PersistedRunInspection(session: PersistedSession(
            id: sessionID,
            title: "Inspectable",
            messages: [message],
            turns: [Turn(id: turnID, runID: sessionID, status: .failed, userMessageID: message.id)],
            events: [
                PersistedRuntimeEvent(
                    id: UUID(),
                    runID: sessionID,
                    turnID: turnID,
                    sequence: 1,
                    createdAt: Date(),
                    kind: .turnFailed,
                    summary: "Turn failed",
                    error: "network down"
                )
            ],
            contextTraces: [
                PersistedContextTrace(
                    runID: sessionID,
                    turnID: turnID,
                    policyID: "recent",
                    policyName: "Recent messages",
                    messageLimit: 20,
                    includedMessageIDs: [message.id],
                    excludedMessageIDs: [],
                    createdAt: Date()
                )
            ]
        ))
        let inspector = StubLoadRunInspectionUseCase(inspection: RunInspectionSnapshot(inspection: inspection))
        let interactor = makeInteractor(
            runID: sessionID,
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
        await streamUserMessage.yield(.userMessageAccepted(
            runtimeHeader(runID: runID, turnID: UUID(), sequence: 1),
            messageID: UUID(),
            text: "detached question"
        ))
        await streamUserMessage.yield(.assistantMessageCompleted(
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

        await streamUserMessage.yield(.userMessageAccepted(
            runtimeHeader(runID: runID, turnID: UUID(), sequence: 1),
            messageID: UUID(),
            text: "keep running"
        ))
        await streamUserMessage.yield(.assistantMessageCompleted(
            runtimeHeader(runID: runID, turnID: UUID(), sequence: 2),
            messageID: UUID(),
            text: "finished while hidden"
        ))
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
        let user = RunMessage(role: .user, parts: [.text("saved question")], source: .localUser, turnID: turnID)
        let assistant = RunMessage(role: .assistant, parts: [.text("saved answer")], source: .provider, turnID: turnID)
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

@MainActor
private func makeInteractor(
    runID: UUID?,
    createRun: CreateRunUseCase = RecordingCreateRunUseCase(runID: UUID()),
    streamUserMessage: StreamUserMessageUseCase,
    sessionRegistry: TaskSessionServiceRegistry? = nil,
    workspace: TaskWorkspaceService? = nil,
    loadProviderSettings: LoadProviderSettingsUseCase? = nil,
    saveProviderSettings: SaveProviderSettingsUseCase? = nil,
    clearProviderSettings: ClearProviderSettingsUseCase? = nil,
    validateProviderSettings: ValidateProviderSettingsUseCase? = nil,
    listSessions: ListSessionsUseCase? = nil,
    loadSession: LoadSessionUseCase? = nil,
    createSession: CreateSessionUseCase? = nil,
    loadRunInspection: LoadRunInspectionUseCase? = nil,
    router: Router<AnyRouteInput, AnyModalInput>? = nil
) -> TaskWorkspaceInteractor {
    let registry = sessionRegistry ?? TaskSessionServiceRegistry(
        createRun: createRun,
        streamUserMessage: streamUserMessage,
        loadSession: loadSession,
        createSession: createSession
    )
    let workspace = workspace ?? TaskWorkspaceService(
        registry: registry,
        listSessions: listSessions,
        router: router
    )
    return TaskWorkspaceInteractor(
        input: TaskWorkspaceRouteInput(taskID: runID),
        workspace: workspace,
        loadProviderSettings: loadProviderSettings,
        saveProviderSettings: saveProviderSettings,
        clearProviderSettings: clearProviderSettings,
        validateProviderSettings: validateProviderSettings,
        loadRunInspection: loadRunInspection
    )
}

private func runtimeHeader(
    runID: UUID,
    turnID: UUID?,
    sequence: Int
) -> RuntimeEventHeader {
    RuntimeEventHeader(
        id: UUID(),
        runID: runID,
        turnID: turnID,
        sequence: sequence,
        createdAt: Date()
    )
}

@MainActor
private func waitUntil(
    _ predicate: @escaping @MainActor () -> Bool,
    sourceLocation: SourceLocation = #_sourceLocation
) async {
    for _ in 0..<100 {
        if predicate() {
            return
        }
        try? await Task.sleep(nanoseconds: 5_000_000)
    }
    Issue.record("Timed out waiting for state transition", sourceLocation: sourceLocation)
}

private struct ConversationStreamRequest: Equatable, Sendable {
    let runID: UUID
    let text: String
}

private actor RecordingCreateRunUseCase: CreateRunUseCase {
    private let runID: UUID
    private var callCount = 0

    init(runID: UUID) {
        self.runID = runID
    }

    func createRun() async -> UUID {
        callCount += 1
        return runID
    }

    func calls() -> Int {
        callCount
    }
}

private actor ImmediateStreamUserMessageUseCase: StreamUserMessageUseCase {
    private var recordedRequests: [ConversationStreamRequest] = []

    func streamUserMessage(
        runID: UUID,
        text: String
    ) async throws -> AsyncThrowingStream<RuntimeEvent, Error> {
        recordedRequests.append(ConversationStreamRequest(runID: runID, text: text))

        return AsyncThrowingStream { continuation in
            let turnID = UUID()
            continuation.yield(.userMessageAccepted(
                runtimeHeader(runID: runID, turnID: turnID, sequence: 1),
                messageID: UUID(),
                text: text
            ))
            continuation.yield(.assistantMessageCompleted(
                runtimeHeader(runID: runID, turnID: turnID, sequence: 2),
                messageID: UUID(),
                text: "done \(text)"
            ))
            continuation.finish()
        }
    }

    func requests() -> [ConversationStreamRequest] {
        recordedRequests
    }
}

private actor ControlledStreamUserMessageUseCase: StreamUserMessageUseCase {
    private typealias Continuation = AsyncThrowingStream<RuntimeEvent, Error>.Continuation

    private var recordedRequests: [ConversationStreamRequest] = []
    private var continuation: Continuation?
    private var requestWaiters: [CheckedContinuation<Void, Never>] = []
    private var streamWaiters: [CheckedContinuation<Void, Never>] = []
    private var terminationCount = 0
    private var terminationWaiters: [CheckedContinuation<Void, Never>] = []

    func streamUserMessage(
        runID: UUID,
        text: String
    ) async throws -> AsyncThrowingStream<RuntimeEvent, Error> {
        recordedRequests.append(ConversationStreamRequest(runID: runID, text: text))
        resumeRequestWaiters()

        return AsyncThrowingStream { continuation in
            continuation.onTermination = { @Sendable _ in
                Task {
                    await self.recordTermination()
                }
            }
            Task {
                self.setContinuation(continuation)
            }
        }
    }

    func yield(_ event: RuntimeEvent) {
        continuation?.yield(event)
    }

    func finish() {
        continuation?.finish()
        continuation = nil
    }

    func waitUntilRequestCount(_ expectedCount: Int) async {
        if recordedRequests.count < expectedCount {
            await withCheckedContinuation { waiter in
                requestWaiters.append(waiter)
            }
        }

        if continuation == nil {
            await withCheckedContinuation { waiter in
                streamWaiters.append(waiter)
            }
        }
    }

    func waitUntilTerminationCount(_ expectedCount: Int) async {
        if terminationCount >= expectedCount {
            return
        }

        await withCheckedContinuation { waiter in
            terminationWaiters.append(waiter)
        }
    }

    func requests() -> [ConversationStreamRequest] {
        recordedRequests
    }

    private func setContinuation(_ continuation: Continuation) {
        self.continuation = continuation
        let waiters = streamWaiters
        streamWaiters.removeAll()
        for waiter in waiters {
            waiter.resume()
        }
    }

    private func resumeRequestWaiters() {
        let waiters = requestWaiters
        requestWaiters.removeAll()
        for waiter in waiters {
            waiter.resume()
        }
    }

    private func recordTermination() {
        terminationCount += 1
        let waiters = terminationWaiters
        terminationWaiters.removeAll()
        for waiter in waiters {
            waiter.resume()
        }
    }
}

private actor StubSessionUseCase: ListSessionsUseCase, LoadSessionUseCase, CreateSessionUseCase {
    private var sessions: [PersistedSession]
    private let createdSession: PersistedSession
    private var createCalls = 0
    private var loadCalls = 0
    private var listCalls = 0

    init(
        sessions: [PersistedSession],
        createdSession: PersistedSession = PersistedSession(title: "New Task")
    ) {
        self.sessions = sessions
        self.createdSession = createdSession
    }

    func listSessions() async throws -> [PersistedSessionSummary] {
        listCalls += 1
        return sessions.map(\.summary)
    }

    func loadSession(id: UUID) async throws -> PersistedSession {
        loadCalls += 1
        guard let session = sessions.first(where: { $0.id == id }) else {
            throw AppStateStoreFailure.sessionNotFound(id)
        }
        return session
    }

    func createSession(title: String?) async throws -> PersistedSession {
        createCalls += 1
        sessions.append(createdSession)
        return createdSession
    }

    func createdCount() -> Int {
        createCalls
    }

    func loadedCount() -> Int {
        loadCalls
    }

    func listedCount() -> Int {
        listCalls
    }
}

private actor StubProviderSettingsUseCase:
    LoadProviderSettingsUseCase,
    SaveProviderSettingsUseCase,
    ClearProviderSettingsUseCase,
    ValidateProviderSettingsUseCase
{
    private var summary: ProviderSettingsSummary?
    private var saved: ProviderSettingsDraft?
    private var cleared = false
    var validationResult: ProviderSettingsValidationResult = .success

    func loadProviderSettings() async throws -> ProviderSettingsSummary? {
        summary
    }

    func saveProviderSettings(_ draft: ProviderSettingsDraft, validatedAt: Date?) async throws {
        saved = draft
        summary = ProviderSettingsSummary(
            baseURLString: draft.baseURLString,
            model: draft.model,
            hasSavedAPIKey: draft.apiKey?.isEmpty == false,
            validatedAt: validatedAt
        )
    }

    func clearProviderSettings() async throws {
        summary = nil
        saved = nil
        cleared = true
    }

    func validateProviderSettings(_ draft: ProviderSettingsDraft) async -> ProviderSettingsValidationResult {
        validationResult
    }

    func savedDraft() -> ProviderSettingsDraft? {
        saved
    }

    func wasCleared() -> Bool {
        cleared
    }
}

private actor StubLoadRunInspectionUseCase: LoadRunInspectionUseCase {
    private let inspection: RunInspectionSnapshot

    init(inspection: RunInspectionSnapshot) {
        self.inspection = inspection
    }

    func loadRunInspection(runID: UUID) async throws -> RunInspectionSnapshot {
        inspection
    }
}

private struct FailingListSessionsUseCase: ListSessionsUseCase {
    func listSessions() async throws -> [PersistedSessionSummary] {
        throw StubFailure.boom
    }
}

private struct FailingLoadSessionUseCase: LoadSessionUseCase {
    func loadSession(id: UUID) async throws -> PersistedSession {
        throw StubFailure.boom
    }
}

private enum StubFailure: Error, CustomStringConvertible {
    case boom

    var description: String {
        "boom"
    }
}
