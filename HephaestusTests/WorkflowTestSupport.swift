import Foundation

@testable import Hephaestus

struct RecordedProcessCall: Equatable {
    let executable: URL
    let arguments: [String]
    let currentDirectoryURL: URL?
    let timeoutSeconds: TimeInterval?
}

final class RecordingProcessRunner: WorkflowProcessRunning {
    private let lock = NSLock()
    private var results: [ProcessResult]
    private var calls: [RecordedProcessCall] = []

    init(results: [ProcessResult]) {
        self.results = results
    }

    func run(
        executable: URL,
        arguments: [String],
        currentDirectoryURL: URL?,
        timeoutSeconds: TimeInterval?
    ) async -> ProcessResult {
        lock.withLock {
            calls.append(
                RecordedProcessCall(
                    executable: executable,
                    arguments: arguments,
                    currentDirectoryURL: currentDirectoryURL,
                    timeoutSeconds: timeoutSeconds
                ))
            guard !results.isEmpty else {
                return ProcessResult(exitCode: 0, output: "")
            }
            return results.removeFirst()
        }
    }

    func recordedCalls() -> [RecordedProcessCall] {
        lock.withLock { calls }
    }
}

actor ProgressRecorder {
    private var recordedEvents: [WorkflowRunProgress] = []

    func record(_ progress: WorkflowRunProgress) {
        recordedEvents.append(progress)
    }

    func events() -> [WorkflowRunProgress] {
        recordedEvents
    }
}

extension NSLock {
    func withLock<T>(_ operation: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try operation()
    }
}
