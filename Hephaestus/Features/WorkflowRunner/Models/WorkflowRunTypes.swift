import Foundation

nonisolated struct ProcessResult: Equatable {
    let exitCode: Int32
    let output: String
    let timeline: String
    let debugLogURL: URL?
    let timedOut: Bool
    let stepRecords: [WorkflowStepRecord]

    nonisolated init(
        exitCode: Int32,
        output: String,
        timeline: String = "",
        debugLogURL: URL? = nil,
        timedOut: Bool = false,
        stepRecords: [WorkflowStepRecord] = []
    ) {
        self.exitCode = exitCode
        self.output = output
        self.timeline = timeline
        self.debugLogURL = debugLogURL
        self.timedOut = timedOut
        self.stepRecords = stepRecords
    }
}

nonisolated struct WorkflowRunProgress: Equatable {
    let timeline: String
    let debugLogURL: URL?
    let stepRecords: [WorkflowStepRecord]

    nonisolated init(timeline: String, debugLogURL: URL?, stepRecords: [WorkflowStepRecord] = []) {
        self.timeline = timeline
        self.debugLogURL = debugLogURL
        self.stepRecords = stepRecords
    }
}

typealias WorkflowProgressHandler = @Sendable (WorkflowRunProgress) async -> Void

nonisolated enum WorkflowStepRecordStatus: String, Equatable {
    case pending
    case inProgress
    case succeeded
    case failed
}

nonisolated enum WorkflowStepRecordCycleOutcome: Equatable {
    case running
    case succeeded
    case needsFix
    case terminalFailed
}

nonisolated struct WorkflowStepRecordHierarchy: Equatable {
    var groupID: String?
    var parentID: String?
    var cycleIndex: Int?
    var depth: Int
    var phaseOrder: Int
    var sequenceOrder: Int
    var cycleOutcome: WorkflowStepRecordCycleOutcome?

    nonisolated init(
        groupID: String? = nil,
        parentID: String? = nil,
        cycleIndex: Int? = nil,
        depth: Int = 0,
        phaseOrder: Int = 0,
        sequenceOrder: Int = 0,
        cycleOutcome: WorkflowStepRecordCycleOutcome? = nil
    ) {
        self.groupID = groupID
        self.parentID = parentID
        self.cycleIndex = cycleIndex
        self.depth = depth
        self.phaseOrder = phaseOrder
        self.sequenceOrder = sequenceOrder
        self.cycleOutcome = cycleOutcome
    }
}

nonisolated struct WorkflowStepRecord: Identifiable, Equatable {
    let id: String
    var title: String
    var status: WorkflowStepRecordStatus
    var summary: String
    var inputPreview: String?
    var outputPreview: String?
    var sortOrder: Int
    var hierarchy: WorkflowStepRecordHierarchy?

    nonisolated init(
        id: String,
        title: String,
        status: WorkflowStepRecordStatus,
        summary: String,
        inputPreview: String? = nil,
        outputPreview: String? = nil,
        sortOrder: Int,
        hierarchy: WorkflowStepRecordHierarchy? = nil
    ) {
        self.id = id
        self.title = title
        self.status = status
        self.summary = summary
        self.inputPreview = inputPreview
        self.outputPreview = outputPreview
        self.sortOrder = sortOrder
        self.hierarchy = hierarchy
    }
}

protocol WorkflowProcessRunning {
    func run(
        executable: URL,
        arguments: [String],
        currentDirectoryURL: URL?,
        timeoutSeconds: TimeInterval?
    ) async -> ProcessResult
}

extension WorkflowProcessRunning {
    func run(executable: URL, arguments: [String]) async -> ProcessResult {
        await run(executable: executable, arguments: arguments, currentDirectoryURL: nil)
    }

    func run(executable: URL, arguments: [String], currentDirectoryURL: URL?) async -> ProcessResult {
        await run(
            executable: executable,
            arguments: arguments,
            currentDirectoryURL: currentDirectoryURL,
            timeoutSeconds: nil
        )
    }
}
