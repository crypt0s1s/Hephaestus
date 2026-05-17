import Foundation

nonisolated struct WorkflowRun: Codable, Equatable, Identifiable {
    let id: String
    let workflowID: String
    var status: WorkflowRunStatus
    let startedAt: Date
    var updatedAt: Date
    var activePause: WorkflowPause?
    var messageIDs: [WorkflowMessage.ID]

    init(
        id: String = UUID().uuidString,
        workflowID: String,
        status: WorkflowRunStatus = .running,
        startedAt: Date = Date(),
        updatedAt: Date = Date(),
        activePause: WorkflowPause? = nil,
        messageIDs: [WorkflowMessage.ID] = []
    ) {
        self.id = id
        self.workflowID = workflowID
        self.status = status
        self.startedAt = startedAt
        self.updatedAt = updatedAt
        self.activePause = activePause
        self.messageIDs = messageIDs
    }
}

nonisolated enum WorkflowRunStatus: String, Codable, Equatable {
    case running
    case paused
    case completed
    case failed
}

nonisolated struct WorkflowPause: Codable, Equatable, Identifiable {
    let id: String
    let runID: WorkflowRun.ID
    let stepID: String
    let reason: WorkflowPauseReason
    let createdAt: Date
    var resumeCommands: [WorkflowResumeCommand]

    init(
        id: String = UUID().uuidString,
        runID: WorkflowRun.ID,
        stepID: String,
        reason: WorkflowPauseReason,
        createdAt: Date = Date(),
        resumeCommands: [WorkflowResumeCommand] = []
    ) {
        self.id = id
        self.runID = runID
        self.stepID = stepID
        self.reason = reason
        self.createdAt = createdAt
        self.resumeCommands = resumeCommands
    }
}

nonisolated enum WorkflowPauseReason: String, Codable, Equatable {
    case interactiveInput
    case userReview
}

nonisolated struct WorkflowResumeCommand: Codable, Equatable, Identifiable {
    let id: String
    let runID: WorkflowRun.ID
    let pauseID: WorkflowPause.ID
    let kind: WorkflowResumeCommandKind
    let label: String
    let createdAt: Date

    init(
        id: String = UUID().uuidString,
        runID: WorkflowRun.ID,
        pauseID: WorkflowPause.ID,
        kind: WorkflowResumeCommandKind,
        label: String,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.runID = runID
        self.pauseID = pauseID
        self.kind = kind
        self.label = label
        self.createdAt = createdAt
    }
}

nonisolated enum WorkflowResumeCommandKind: String, Codable, Equatable {
    case submitInteractiveOutput
    case acceptReviewedOutput
    case continueInteraction
    case requestAutomatedCycle
}
