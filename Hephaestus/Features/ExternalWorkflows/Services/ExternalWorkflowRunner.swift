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
                let data = handle.availableData
                if !data.isEmpty {
                    state.consume(data)
                }
            }

            do {
                try process.run()
                Task {
                    try? await Task.sleep(for: .seconds(timeoutSeconds))
                    state.timeout()
                }
            } catch {
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

private actor ExternalWorkflowProgressRecorder {
    private(set) var timeline = ""
    private(set) var stepRecords: [WorkflowStepRecord] = []
    private var recordedEventKeys: Set<String> = []
    let debugLogURL: URL?

    init(debugLogURL: URL?) {
        self.debugLogURL = debugLogURL
    }

    var progress: WorkflowRunProgress {
        WorkflowRunProgress(timeline: timeline, debugLogURL: debugLogURL, stepRecords: stepRecords)
    }

    func record(_ event: ExternalWorkflowEvent) {
        let key = [
            event.type.rawValue,
            event.stepID ?? "",
            event.title ?? "",
            event.status?.rawValue ?? "",
            event.summary ?? "",
        ].joined(separator: "|")
        guard recordedEventKeys.insert(key).inserted else { return }

        timeline.append(timelineLine(for: event))
        timeline.append("\n")

        guard let stepID = event.stepID else { return }
        let status = WorkflowStepRecordStatus(eventStatus: event.status)
        let title = event.title ?? stepID
        let summary = event.summary ?? status.rawValue

        if let index = stepRecords.firstIndex(where: { $0.id == stepID }) {
            stepRecords[index].title = title
            stepRecords[index].status = status
            stepRecords[index].summary = summary
            if let inputPreview = event.inputPreview {
                stepRecords[index].inputPreview = inputPreview
            }
            stepRecords[index].outputPreview = event.outputPreview ?? event.summary
        } else {
            stepRecords.append(
                WorkflowStepRecord(
                    id: stepID,
                    title: title,
                    status: status,
                    summary: summary,
                    inputPreview: event.inputPreview,
                    outputPreview: event.outputPreview ?? event.summary,
                    sortOrder: stepRecords.count
                ))
        }
    }

    private func timelineLine(for event: ExternalWorkflowEvent) -> String {
        let title = event.title ?? event.stepID ?? "External workflow"
        let summary = event.summary.map { " - \($0)" } ?? ""
        switch event.type {
        case .workflowStarted:
            return "External workflow started: \(title)\(summary)"
        case .workflowFinished:
            return "External workflow finished: \(title)\(summary)"
        case .stepStarted:
            return "\(title) started\(summary)"
        case .stepFinished:
            return "\(title) finished\(summary)"
        case .logChunk:
            return summary.isEmpty ? title : summary
        }
    }
}

extension WorkflowStepRecordStatus {
    fileprivate nonisolated init(eventStatus: ExternalWorkflowEventStatus?) {
        switch eventStatus {
        case .pending:
            self = .pending
        case .inProgress:
            self = .inProgress
        case .succeeded:
            self = .succeeded
        case .failed:
            self = .failed
        case nil:
            self = .pending
        }
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

    func consume(_ data: Data) {
        guard let chunk = String(data: data, encoding: .utf8) else { return }
        let completedLines = lock.withLock {
            output.append(chunk)
            lineBuffer.append(chunk)
            return takeCompletedLines()
        }
        Task {
            await debugLog.append(chunk)
            await debugLog.append(chunk, to: "raw-process.log")
            for line in completedLines {
                guard let event = lineInterpreter.event(from: line) else { continue }
                await recorder.record(event)
                if let progress {
                    let snapshot = await recorder.progress
                    await progress(snapshot)
                }
            }
        }
    }

    func finish(
        exitCode: Int32,
        errorOutput: String? = nil,
        failureEvent: ExternalWorkflowEvent? = nil
    ) {
        let result: ProcessResult? = lock.withLock {
            guard !didResume else { return nil }
            didResume = true
            pipe.fileHandleForReading.readabilityHandler = nil
            if let errorOutput {
                output.append(errorOutput)
            }
            return ProcessResult(exitCode: exitCode, output: output)
        }

        if let result {
            Task {
                if let errorOutput {
                    await debugLog.append(errorOutput)
                    await debugLog.append(errorOutput, to: "raw-process.log")
                }
                await replayEventLines(from: result.output)
                if result.exitCode != 0 {
                    await recorder.record(failureEvent ?? .processExitFailure(exitCode: result.exitCode))
                }
                let finalProgress = await recorder.progress
                continuation.resume(
                    returning: ProcessResult(
                        exitCode: result.exitCode,
                        output: result.output,
                        timeline: finalProgress.timeline,
                        debugLogURL: finalProgress.debugLogURL,
                        stepRecords: finalProgress.stepRecords
                    ))
            }
        }
    }

    func timeout() {
        lock.withLock {
            guard !didResume, process.isRunning else { return }
            process.terminate()
        }
        let message = "\n\(ExternalWorkflowEvent.timeoutSummary(seconds: timeoutSeconds))"
        finish(exitCode: 124, errorOutput: message, failureEvent: .processTimeout(seconds: timeoutSeconds))
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
}
