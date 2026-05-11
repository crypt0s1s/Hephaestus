import Foundation
import HephaestusComposition
import HephaestusDomain
import HephaestusHarness
import HephaestusKernel
import HephaestusObservation
import HephaestusRuntime
import Testing

@Suite
struct MetaHarnessFoundationTests {
    @Test
    func persistedSessionSummaryProjectsToDefaultProjectTask() {
        let id = UUID()
        let createdAt = Date(timeIntervalSince1970: 100)
        let updatedAt = Date(timeIntervalSince1970: 200)
        let summary = PersistedSessionSummary(
            id: id,
            title: "Refactor slice",
            createdAt: createdAt,
            updatedAt: updatedAt,
            messageCount: 2
        )

        let task = AgentTask(sessionSummary: summary)

        #expect(task.id == TaskID(rawValue: id))
        #expect(task.projectID == DefaultProject.id)
        #expect(task.title == "Refactor slice")
        #expect(task.status == .completed)
        #expect(task.activeRunID == id)
        #expect(task.createdAt == createdAt)
        #expect(task.updatedAt == updatedAt)
    }

    @Test
    func persistedSessionProjectsRunningAndFailedTaskStatuses() {
        let runID = UUID()
        let userMessage = RunMessage(
            role: .user,
            parts: [.text("Work on this")],
            source: .localUser,
            turnID: UUID()
        )
        let runningSession = PersistedSession(
            id: runID,
            title: "Running",
            messages: [userMessage],
            turns: [
                Turn(
                    id: userMessage.turnID ?? UUID(),
                    runID: runID,
                    status: .streaming,
                    userMessageID: userMessage.id
                )
            ]
        )
        var failedSession = runningSession
        failedSession.title = "Failed"
        failedSession.turns[0].status = .failed

        #expect(AgentTask(session: runningSession).status == .running)
        #expect(AgentTask(session: failedSession).status == .failed)
    }

    @Test
    func runInspectionMapsToObservationSnapshot() {
        let fixture = makeRunInspectionFixture()
        let snapshot = RunInspectionSnapshot(inspection: fixture.inspection)

        #expect(snapshot.runID == fixture.runID)
        #expect(snapshot.taskID == TaskID(rawValue: fixture.runID))
        #expect(snapshot.events.map(\.id) == [fixture.eventID])
        #expect(snapshot.events.first?.kind == .error)
        #expect(snapshot.events.first?.error == "network down")
        #expect(snapshot.turns.first?.status == .failed)
        #expect(snapshot.contextTraces.first?.messageLimit == 20)
    }

    @Test
    func nativeBackendDescriptorIdentifiesFoundryOnly() {
        let descriptor = RuntimeComposition.nativeBackendDescriptor

        #expect(descriptor.id == FoundryBackend.id)
        #expect(descriptor.displayName == "Foundry")
        #expect(descriptor.availability == .available)
        #expect(descriptor.capabilities.contains(.conversation))
        #expect(descriptor.capabilities.contains(.liveEvents))
    }
}

private func makeRunInspectionFixture() -> (
    runID: UUID,
    eventID: UUID,
    inspection: PersistedRunInspection
) {
    let runID = UUID()
    let turnID = UUID()
    let eventID = UUID()
    let createdAt = Date(timeIntervalSince1970: 300)
    let inspection = PersistedRunInspection(
        session: PersistedSession(
            id: runID,
            title: "Inspectable",
            turns: [
                Turn(
                    id: turnID,
                    runID: runID,
                    status: .failed,
                    userMessageID: UUID()
                )
            ],
            events: [failedRuntimeEvent(id: eventID, runID: runID, turnID: turnID, createdAt: createdAt)],
            contextTraces: [emptyContextTrace(runID: runID, turnID: turnID, createdAt: createdAt)]
        ))

    return (runID, eventID, inspection)
}

private func failedRuntimeEvent(
    id: UUID,
    runID: UUID,
    turnID: UUID,
    createdAt: Date
) -> PersistedRuntimeEvent {
    PersistedRuntimeEvent(
        id: id,
        runID: runID,
        turnID: turnID,
        sequence: 4,
        createdAt: createdAt,
        kind: .turnFailed,
        summary: "Turn failed",
        error: "network down"
    )
}

private func emptyContextTrace(
    runID: UUID,
    turnID: UUID,
    createdAt: Date
) -> PersistedContextTrace {
    PersistedContextTrace(
        runID: runID,
        turnID: turnID,
        policyID: "recent",
        policyName: "Recent messages",
        messageLimit: 20,
        includedMessageIDs: [],
        excludedMessageIDs: [],
        createdAt: createdAt
    )
}
