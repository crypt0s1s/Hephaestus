import Foundation

struct CodexHarnessBackendAdapter: HarnessBackendAdapter {
  private let processRunner: WorkflowProcessRunning

  init(processRunner: WorkflowProcessRunning) {
    self.processRunner = processRunner
  }

  func startSession(_ request: StartSessionRequest) async throws -> BackendSession {
    BackendSession(
      id: UUID().uuidString,
      backendName: "codex",
      project: request.project
    )
  }

  func resumeSession(_ request: ResumeSessionRequest) async throws -> BackendSession {
    request.session
  }

  func startTurn(_ request: StartTurnRequest) async throws -> AsyncThrowingStream<BackendEvent, Error> {
    AsyncThrowingStream { continuation in
      let sessionID = request.session.id
      continuation.yield(.turnStarted(sessionID: sessionID))
      Task {
        let result = await runCodexExecTurn(request)
        continuation.yield(.outputChunk(result.output))
        if result.exitCode == 0 {
          continuation.yield(.turnCompleted(result))
        } else {
          continuation.yield(.turnFailed(result))
        }
        continuation.finish()
      }
    }
  }

  func respondToApproval(_ response: ApprovalResponse) async throws {
    // Codex exec does not expose app-owned approvals in this first adapter slice.
  }

  func cancelTurn(_ request: CancelTurnRequest) async throws {
    // Cancellation is currently owned by the process timeout path.
  }

  private func runCodexExecTurn(_ request: StartTurnRequest) async -> ProcessResult {
    await processRunner.run(
      executable: Self.codexExecutableURL,
      arguments: [
        "exec",
        "--cd", request.session.project.path,
        "--skip-git-repo-check",
        "--sandbox", "workspace-write",
        request.prompt,
      ],
      currentDirectoryURL: nil,
      timeoutSeconds: request.timeoutSeconds
    )
  }

  private static var codexExecutableURL: URL {
    let appBundledCodex = URL(fileURLWithPath: "/Applications/Codex.app/Contents/Resources/codex")
    if FileManager.default.isExecutableFile(atPath: appBundledCodex.path) {
      return appBundledCodex
    }
    return URL(fileURLWithPath: "/usr/bin/env")
  }
}
