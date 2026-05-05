import Foundation

struct ProcessResult: Equatable {
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

struct WorkflowRunProgress: Equatable {
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

enum WorkflowStepRecordStatus: String, Equatable {
    case pending
    case inProgress
    case succeeded
    case failed
}

struct WorkflowStepRecord: Identifiable, Equatable {
    let id: String
    var title: String
    var status: WorkflowStepRecordStatus
    var summary: String
    var inputPreview: String?
    var outputPreview: String?
    var sortOrder: Int
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
