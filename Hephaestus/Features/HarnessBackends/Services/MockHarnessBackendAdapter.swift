import Foundation

struct MockHarnessBackendAdapter: HarnessBackendAdapter {
  func startSession(_ request: StartSessionRequest) async throws -> BackendSession {
    BackendSession(
      id: UUID().uuidString,
      backendName: "mock",
      project: request.project
    )
  }

  func resumeSession(_ request: ResumeSessionRequest) async throws -> BackendSession {
    request.session
  }

  func startTurn(_ request: StartTurnRequest) async throws -> AsyncThrowingStream<BackendEvent, Error> {
    AsyncThrowingStream { continuation in
      let output = Self.planningResponse(for: request.prompt)
      continuation.yield(.turnStarted(sessionID: request.session.id))
      continuation.yield(.outputChunk(output))
      continuation.yield(.turnCompleted(ProcessResult(exitCode: 0, output: output)))
      continuation.finish()
    }
  }

  func respondToApproval(_ response: ApprovalResponse) async throws {}

  func cancelTurn(_ request: CancelTurnRequest) async throws {}

  private static func planningResponse(for prompt: String) -> String {
    """
    # Plan

    ## Summary
    \(prompt.firstLineForPromptSummary)

    ## Scope
    - Implement the requested interactive planning workflow slice.

    ## Non-Goals
    - Do not broaden into a general workflow builder in this pass.

    ## Implementation Approach
    - Keep the planner interaction Codex-backed through the harness backend.
    - Materialize the selected draft into a markdown artifact.
    - Validate the artifact before automated review begins.

    ## Validation
    - Run focused model tests and the Hephaestus macOS build.

    ## Open Questions
    - Confirm the long-term pause/resume message envelope.
    """
  }
}

private extension String {
  var firstLineForPromptSummary: String {
    split(separator: "\n")
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .first { !$0.isEmpty }
      ?? "Draft the requested plan."
  }
}
