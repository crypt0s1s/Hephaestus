import Darwin
import Foundation

struct ExternalWorkflowRunner {
    private let timeoutSeconds: Int
    private let processFactory: (String, String, URL) -> Process

    init(
        timeoutSeconds: Int = 120,
        processFactory: @escaping (String, String, URL) -> Process = ExternalWorkflowRunner.makeDefaultProcess
    ) {
        self.timeoutSeconds = timeoutSeconds
        self.processFactory = processFactory
    }

    init(
        environment: [String: String],
        processFactory: @escaping (String, String, URL) -> Process = ExternalWorkflowRunner.makeDefaultProcess
    ) {
        self.init(timeoutSeconds: Self.timeoutSeconds(from: environment), processFactory: processFactory)
    }

    func run(
        workflow: WorkflowDefinition,
        project: WorkflowProject,
        inputValues: [String: String] = [:],
        progress: WorkflowProgressHandler? = nil
    ) async -> ProcessResult {
        guard let packagePath = workflow.externalPackagePath else {
            return ProcessResult(exitCode: 1, output: "External workflow is missing a package path.")
        }

        let debugLog = WorkflowDebugLog(projectName: "\(project.name)-external-workflow")
        let runInput = WorkflowRunInput(projectPath: project.path, values: inputValues)
        guard let inputURL = try? writeRunInput(runInput) else {
            return ProcessResult(exitCode: 1, output: "Could not write workflow run input.")
        }

        let recorder = ExternalWorkflowProgressRecorder(debugLogURL: debugLog.directoryURL)
        await recorder.record(
            ExternalWorkflowEvent(
                type: .workflowStarted,
                stepID: nil,
                title: workflow.title,
                status: .inProgress,
                summary: "Starting external Swift workflow.",
                inputPreview: nil,
                outputPreview: nil
            )
        )
        if let progress {
            let snapshot = await recorder.progress
            await progress(snapshot)
        }

        let result = await runProcess(
            packagePath: packagePath,
            entry: workflow.externalEntryName ?? "ImplementationReviewWorkflow",
            inputURL: inputURL,
            debugLog: debugLog,
            recorder: recorder,
            progress: progress,
            timeoutSeconds: timeoutSeconds
        )

        try? FileManager.default.removeItem(at: inputURL)
        return result
    }

    private func writeRunInput(_ input: WorkflowRunInput) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("hephaestus-workflow-input-\(UUID().uuidString).json")
        let data = try JSONEncoder().encode(input)
        try data.write(to: url)
        return url
    }

    private func runProcess(
        packagePath: String,
        entry: String,
        inputURL: URL,
        debugLog: WorkflowDebugLog,
        recorder: ExternalWorkflowProgressRecorder,
        progress: WorkflowProgressHandler?,
        timeoutSeconds: Int
    ) async -> ProcessResult {
        await withCheckedContinuation { continuation in
            let process = processFactory(packagePath, entry, inputURL)
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe
            let state = ExternalWorkflowProcessState(
                process: process,
                pipe: pipe,
                debugLog: debugLog,
                recorder: recorder,
                progress: progress,
                timeoutSeconds: timeoutSeconds,
                continuation: continuation
            )

            process.terminationHandler = { process in
                state.finish(exitCode: process.terminationStatus)
            }

            pipe.fileHandleForReading.readabilityHandler = { handle in
                state.consumeAvailableData(from: handle)
            }

            do {
                try process.run()
                try? pipe.fileHandleForWriting.close()
                Task {
                    try? await Task.sleep(for: .seconds(timeoutSeconds))
                    state.timeout()
                }
            } catch {
                try? pipe.fileHandleForWriting.close()
                state.finish(exitCode: 1, errorOutput: String(describing: error))
            }
        }
    }

    private nonisolated static func makeDefaultProcess(
        packagePath: String,
        entry: String,
        inputURL: URL
    ) -> Process {
        let packageURL = URL(fileURLWithPath: packagePath, isDirectory: true)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/swift")
        process.arguments = [
            "run",
            "--package-path", packagePath,
            "--scratch-path", SwiftPackageScratchPath.url(for: packageURL).path,
            entry,
            "run",
            "--input", inputURL.path,
        ]
        process.currentDirectoryURL = packageURL
        return process
    }

    private nonisolated static func timeoutSeconds(from environment: [String: String]) -> Int {
        guard let rawValue = environment["HEPHAESTUS_EXTERNAL_WORKFLOW_TIMEOUT_SECONDS"],
            let timeoutSeconds = Int(rawValue),
            timeoutSeconds > 0
        else {
            return 120
        }
        return timeoutSeconds
    }
}

private nonisolated final class ExternalWorkflowProcessState: @unchecked Sendable {
    private let process: Process
    private let pipe: Pipe
    private let debugLog: WorkflowDebugLog
    private let recorder: ExternalWorkflowProgressRecorder
    private let progress: WorkflowProgressHandler?
    private let timeoutSeconds: Int
    private let continuation: CheckedContinuation<ProcessResult, Never>
    private let lineInterpreter = ExternalWorkflowEventLineInterpreter()
    private let lock = NSLock()
    private var output = ""
    private var lineBuffer = ""
    private var didResume = false
    private var didRequestTimeout = false

    init(
        process: Process,
        pipe: Pipe,
        debugLog: WorkflowDebugLog,
        recorder: ExternalWorkflowProgressRecorder,
        progress: WorkflowProgressHandler?,
        timeoutSeconds: Int,
        continuation: CheckedContinuation<ProcessResult, Never>
    ) {
        self.process = process
        self.pipe = pipe
        self.debugLog = debugLog
        self.recorder = recorder
        self.progress = progress
        self.timeoutSeconds = timeoutSeconds
        self.continuation = continuation
    }

    func consumeAvailableData(from handle: FileHandle) {
        let drain = lock.withLock {
            guard !didResume else { return PipeDrain() }
            return drainAvailableData(from: handle)
        }
        record(drain)
    }

    func consume(_ data: Data) {
        let drain = lock.withLock {
            guard !didResume else { return PipeDrain() }
            return append(data)
        }
        record(drain)
    }

    private func record(_ drain: PipeDrain) {
        guard !drain.chunks.isEmpty || !drain.completedLines.isEmpty else { return }
        Task {
            for chunk in drain.chunks {
                await debugLog.append(chunk)
            }
            for line in drain.completedLines {
                await recordEventLine(line)
            }
        }
    }

    private func recordEventLine(_ line: String) async {
        guard let event = lineInterpreter.event(from: line) else { return }
        await recorder.record(event)
        if let progress {
            let snapshot = await recorder.progress
            await progress(snapshot)
        }
    }

    func finish(
        exitCode: Int32,
        errorOutput: String? = nil,
        failureEvent: ExternalWorkflowEvent? = nil
    ) {
        let finishData = processCompletion(exitCode: exitCode, errorOutput: errorOutput, failureEvent: failureEvent)
        if let finishData {
            Task {
                await debugLog.replace(finishData.result.output, in: "raw-process.log")
                await replayEventLines(from: finishData.result.output)
                await recordFailureIfNeeded(finishData)
                let finalProgress = await recorder.progress
                continuation.resume(returning: resolvedResult(from: finishData.result, progress: finalProgress))
            }
        }
    }

    private func processCompletion(
        exitCode: Int32, errorOutput: String?, failureEvent: ExternalWorkflowEvent?
    ) -> (result: ProcessResult, failureEvent: ExternalWorkflowEvent?)? {
        lock.withLock {
            guard !didResume else { return nil }
            pipe.fileHandleForReading.readabilityHandler = nil
            _ = drainAvailableData(from: pipe.fileHandleForReading)
            didResume = true
            let resolvedExitCode = didRequestTimeout ? 124 : exitCode
            let resolvedFailureEvent = didRequestTimeout
                ? ExternalWorkflowEvent.processTimeout(seconds: timeoutSeconds)
                : failureEvent
            let resolvedErrorOutput = didRequestTimeout
                ? "\n\(ExternalWorkflowEvent.timeoutSummary(seconds: timeoutSeconds))"
                : errorOutput
            if let errorOutput {
                output.append(errorOutput)
            }
            if didRequestTimeout, let resolvedErrorOutput {
                output.append(resolvedErrorOutput)
            }
            return (ProcessResult(exitCode: resolvedExitCode, output: output), resolvedFailureEvent)
        }
    }

    private func recordFailureIfNeeded(_ finishData: (result: ProcessResult, failureEvent: ExternalWorkflowEvent?)) async {
        guard finishData.result.exitCode != 0 else { return }
        await recorder.record(
            finishData.failureEvent ?? .processExitFailure(exitCode: finishData.result.exitCode)
        )
    }

    private func resolvedResult(from result: ProcessResult, progress finalProgress: WorkflowRunProgress) -> ProcessResult {
        ProcessResult(
            exitCode: result.exitCode,
            output: result.output,
            timeline: finalProgress.timeline,
            debugLogURL: finalProgress.debugLogURL,
            stepRecords: finalProgress.stepRecords
        )
    }

    func timeout() {
        let shouldTerminate = lock.withLock {
            guard !didResume, !didRequestTimeout, process.isRunning else { return false }
            didRequestTimeout = true
            return true
        }
        guard shouldTerminate else { return }
        process.terminate()
        Task {
            try? await Task.sleep(for: .seconds(2))
            forceKillIfStillRunning()
        }
    }

    private func forceKillIfStillRunning() {
        lock.withLock {
            guard !didResume, didRequestTimeout, process.isRunning else { return }
            kill(process.processIdentifier, SIGKILL)
        }
    }

    private func replayEventLines(from output: String) async {
        for line in output.split(separator: "\n") {
            guard let event = lineInterpreter.event(from: String(line)) else { continue }
            await recorder.record(event)
        }
    }

    private func takeCompletedLines() -> [String] {
        var lines: [String] = []
        while let newlineIndex = lineBuffer.firstIndex(of: "\n") {
            lines.append(String(lineBuffer[..<newlineIndex]))
            lineBuffer.removeSubrange(...newlineIndex)
        }
        return lines
    }

    private func drainAvailableData(from handle: FileHandle) -> PipeDrain {
        let fileDescriptor = handle.fileDescriptor
        let flags = fcntl(fileDescriptor, F_GETFL)
        if flags >= 0 {
            _ = fcntl(fileDescriptor, F_SETFL, flags | O_NONBLOCK)
        }
        defer {
            if flags >= 0 {
                _ = fcntl(fileDescriptor, F_SETFL, flags)
            }
        }

        var drain = PipeDrain()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while true {
            let count = read(fileDescriptor, &buffer, buffer.count)
            guard count >= 1 else { break }
            drain.append(append(Data(buffer.prefix(count))))
        }
        return drain
    }

    private func append(_ data: Data) -> PipeDrain {
        guard let chunk = String(data: data, encoding: .utf8), !chunk.isEmpty else {
            return PipeDrain()
        }
        output.append(chunk)
        lineBuffer.append(chunk)
        return PipeDrain(chunks: [chunk], completedLines: takeCompletedLines())
    }
}
