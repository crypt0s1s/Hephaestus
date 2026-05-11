import Foundation
import HephaestusKernel
import HephaestusRuntime
import TaskWorkspaceFeature
import Testing

extension TaskWorkspaceInteractorTests {
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
        #expect(
            await streamUserMessage.requests() == [
                ConversationStreamRequest(runID: runID, text: "first"),
                ConversationStreamRequest(runID: runID, text: "second"),
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
        #expect(interactor.state.draftText.isEmpty)
        #expect(interactor.state.errorMessage == nil)

        await streamUserMessage.yield(
            .assistantMessageCompleted(
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

        #expect(
            await streamUserMessage.requests() == [
                ConversationStreamRequest(runID: runID, text: "first")
            ])
        #expect(interactor.state.draftText == "second")

        await streamUserMessage.yield(
            .assistantMessageCompleted(
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
        let user = RunMessage(
            role: .user, parts: [.text("saved question")], source: .localUser, turnID: turnID)
        let assistant = RunMessage(
            role: .assistant, parts: [.text("saved answer")], source: .provider, turnID: turnID)
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
        let user = RunMessage(
            role: .user, parts: [.text("target question")], source: .localUser, turnID: UUID())
        let sessions = StubSessionUseCase(
            sessions: [
                PersistedSession(id: currentID, title: "Current"),
                PersistedSession(id: targetID, title: "Target", messages: [user]),
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
}
