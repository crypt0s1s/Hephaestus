import Foundation

struct CodexAgentInvocation: Equatable {
    let name: String
    let project: WorkflowProject
    let prompt: String
    let timeoutSeconds: TimeInterval?
    let sandboxMode: String

    init(
        name: String,
        project: WorkflowProject,
        prompt: String,
        timeoutSeconds: TimeInterval? = 300,
        sandboxMode: String = "workspace-write"
    ) {
        self.name = name
        self.project = project
        self.prompt = prompt
        self.timeoutSeconds = timeoutSeconds
        self.sandboxMode = sandboxMode
    }
}

struct CodexAgentStep {
    private let backendAdapter: HarnessBackendAdapter

    init(processRunner: WorkflowProcessRunning) {
        self.backendAdapter = CodexHarnessBackendAdapter(processRunner: processRunner)
    }

    init(backendAdapter: HarnessBackendAdapter) {
        self.backendAdapter = backendAdapter
    }

    func run(_ invocation: CodexAgentInvocation) async -> ProcessResult {
        let result: ProcessResult
        do {
            let session = try await backendAdapter.startSession(
                StartSessionRequest(project: invocation.project, title: invocation.name))
            let stream = try await backendAdapter.startTurn(
                StartTurnRequest(
                    session: session,
                    prompt: invocation.prompt,
                    timeoutSeconds: invocation.timeoutSeconds,
                    sandboxMode: invocation.sandboxMode
                ))
            result = try await collectTurnResult(from: stream)
        } catch {
            result = ProcessResult(exitCode: -1, output: String(describing: error))
        }
        let timeoutNote =
            result.timedOut
            ? """

            Timed out after \(Int(invocation.timeoutSeconds ?? 0)) seconds. \
            Treat this as a failed agent step and inspect the debug log.

            """
            : ""
        return ProcessResult(
            exitCode: result.exitCode,
            output: """
                == \(invocation.name) ==
                \(result.output)
                \(timeoutNote)
                """
        )
    }

    private func collectTurnResult(
        from stream: AsyncThrowingStream<BackendEvent, Error>
    ) async throws -> ProcessResult {
        var output = ""
        for try await event in stream {
            switch event {
            case .outputChunk(let chunk):
                output += chunk
            case .turnCompleted(let result), .turnFailed(let result):
                return result
            case .sessionStarted,
                .turnStarted,
                .approvalRequested,
                .turnCancelled:
                continue
            }
        }
        return ProcessResult(
            exitCode: -1,
            output: output.isEmpty
                ? "Codex turn ended without a completion event."
                : output
        )
    }
}

struct ShellValidationInvocation: Equatable {
    let name: String
    let project: WorkflowProject
    let command: String
    let timeoutSeconds: TimeInterval?

    init(name: String, project: WorkflowProject, command: String, timeoutSeconds: TimeInterval? = 600) {
        self.name = name
        self.project = project
        self.command = command
        self.timeoutSeconds = timeoutSeconds
    }
}

struct ShellValidationStep {
    private let processRunner: WorkflowProcessRunning

    init(processRunner: WorkflowProcessRunning) {
        self.processRunner = processRunner
    }

    func run(_ invocation: ShellValidationInvocation) async -> ProcessResult {
        let result = await processRunner.run(
            executable: URL(fileURLWithPath: "/bin/zsh"),
            arguments: ["-lc", invocation.command],
            currentDirectoryURL: URL(fileURLWithPath: invocation.project.path, isDirectory: true),
            timeoutSeconds: invocation.timeoutSeconds
        )
        let timeoutNote =
            result.timedOut
            ? "\nTimed out after \(Int(invocation.timeoutSeconds ?? 0)) seconds.\n"
            : ""
        return ProcessResult(
            exitCode: result.exitCode,
            output: """
                == \(invocation.name) ==
                Command: \(invocation.command)
                Exit code: \(result.exitCode)
                \(result.output)
                \(timeoutNote)
                """
        )
    }
}
