import Foundation

struct DefaultProcessRunner: WorkflowProcessRunning {
    func run(
        executable: URL,
        arguments: [String],
        currentDirectoryURL: URL? = nil,
        timeoutSeconds: TimeInterval? = nil
    ) async -> ProcessResult {
        await withCheckedContinuation { continuation in
            let process = Process()
            process.executableURL = executable
            process.arguments = executable.lastPathComponent == "env" && arguments.first != "git"
                ? ["codex"] + arguments
                : arguments
            process.currentDirectoryURL = currentDirectoryURL

            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe
            let runState = ProcessRunState(
                process: process,
                pipe: pipe,
                continuation: continuation
            )

            process.terminationHandler = { process in
                runState.finish(exitCode: process.terminationStatus, timedOut: false)
            }

            pipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                if !data.isEmpty {
                    runState.append(data)
                }
            }

            do {
                try process.run()
                if let timeoutSeconds {
                    Task {
                        try? await Task.sleep(for: .seconds(timeoutSeconds))
                        runState.timeout()
                    }
                }
            } catch {
                runState.finish(exitCode: -1, timedOut: false, errorOutput: String(describing: error))
            }
        }
    }
}

private final class ProcessRunState: @unchecked Sendable {
    private let process: Process
    private let pipe: Pipe
    private let continuation: CheckedContinuation<ProcessResult, Never>
    private let lock = NSLock()
    private var outputData = Data()
    private var didResume = false

    init(process: Process, pipe: Pipe, continuation: CheckedContinuation<ProcessResult, Never>) {
        self.process = process
        self.pipe = pipe
        self.continuation = continuation
    }

    func append(_ data: Data) {
        lock.withLock {
            outputData.append(data)
        }
    }

    func timeout() {
        lock.withLock {
            guard !didResume, process.isRunning else { return }
            process.terminate()
        }
        finish(exitCode: 124, timedOut: true)
    }

    func finish(exitCode: Int32, timedOut: Bool, errorOutput: String? = nil) {
        let result: ProcessResult? = lock.withLock {
            guard !didResume else { return nil }
            didResume = true
            pipe.fileHandleForReading.readabilityHandler = nil
            if let errorOutput, let data = errorOutput.data(using: .utf8) {
                outputData.append(data)
            }
            let output = String(data: outputData, encoding: .utf8) ?? ""
            return ProcessResult(exitCode: exitCode, output: output, timedOut: timedOut)
        }

        if let result {
            continuation.resume(returning: result)
        }
    }
}
