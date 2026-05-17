import Foundation

#if DEBUG
struct UITestHarnessBackendAdapter: HarnessBackendAdapter {
    func startSession(_ request: StartSessionRequest) async throws -> BackendSession {
        BackendSession(
            id: UUID().uuidString,
            backendName: "ui-test",
            project: request.project
        )
    }

    func resumeSession(_ request: ResumeSessionRequest) async throws -> BackendSession {
        request.session
    }

    func startTurn(_ request: StartTurnRequest) async throws -> AsyncThrowingStream<BackendEvent, Error> {
        AsyncThrowingStream { continuation in
            let output = Self.output(for: request.prompt)
            continuation.yield(.turnStarted(sessionID: request.session.id))
            continuation.yield(.outputChunk(output))
            continuation.yield(.turnCompleted(ProcessResult(exitCode: 0, output: output)))
            continuation.finish()
        }
    }

    func respondToApproval(_ response: ApprovalResponse) async throws {}

    func cancelTurn(_ request: CancelTurnRequest) async throws {}

    fileprivate static func output(for prompt: String) -> String {
        if prompt.contains("planner agent responding to automated review feedback") {
            return planningPlan(for: prompt)
        }
        if prompt.contains("review-only planning agent") {
            return "pass"
        }
        return planningPlan(for: prompt)
    }

    private static func planningPlan(for prompt: String) -> String {
        """
        # Plan

        ## Summary
        \(prompt.firstLineForUITestSummary)

        ## Scope
        - Implement the requested interactive planning workflow slice.

        ## Non-Goals
        - Do not broaden into a general workflow builder in this pass.

        ## Implementation Approach
        - Keep the planner interaction behind the harness backend adapter.
        - Materialize the reviewed draft into a markdown artifact.
        - Validate the artifact before automated review begins.

        ## Validation
        - Run focused model tests and the Hephaestus macOS UI flow.

        ## Open Questions
        - Confirm the long-term pause and resume envelope.
        """
    }
}

struct UITestPlanningAgentRunner: PlanningAgentRunning {
    func run(_ invocation: PlanningAgentInvocation) async -> ProcessResult {
        let output = UITestHarnessBackendAdapter.output(for: invocation.prompt)
        return ProcessResult(
            exitCode: 0,
            output: """
                == \(invocation.name) ==
                \(output)
                """
        )
    }
}

private extension String {
    var firstLineForUITestSummary: String {
        split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
            ?? "Draft the requested plan."
    }
}
#endif
