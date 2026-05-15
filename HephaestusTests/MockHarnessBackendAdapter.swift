import Foundation

@testable import Hephaestus

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
            let plan = Self.planningPlan(for: request.prompt)
            let output = Self.output(for: request.prompt, plan: plan)
            continuation.yield(.turnStarted(sessionID: request.session.id))
            continuation.yield(.outputChunk(output))
            continuation.yield(.turnCompleted(ProcessResult(exitCode: 0, output: output)))
            continuation.finish()
        }
    }

    func respondToApproval(_ response: ApprovalResponse) async throws {}

    func cancelTurn(_ request: CancelTurnRequest) async throws {}

    private static func planningPlan(for prompt: String) -> String {
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

    static func planningPlanForTests(for prompt: String) -> String {
        planningPlan(for: prompt)
    }

    private static func output(for prompt: String, plan: String) -> String {
        if prompt.isPlannerResponsePrompt {
            return plan
        }
        if prompt.isReviewerPrompt {
            return "pass"
        }
        return plan
    }
}

struct AllFailingReviewersHarnessBackendAdapter: HarnessBackendAdapter {
    func startSession(_ request: StartSessionRequest) async throws -> BackendSession {
        BackendSession(
            id: UUID().uuidString,
            backendName: "all-failing-reviewers",
            project: request.project
        )
    }

    func resumeSession(_ request: ResumeSessionRequest) async throws -> BackendSession {
        request.session
    }

    func startTurn(_ request: StartTurnRequest) async throws -> AsyncThrowingStream<BackendEvent, Error> {
        AsyncThrowingStream { continuation in
            if request.prompt.isReviewerPrompt {
                let output = "Reviewer could not inspect the plan."
                continuation.yield(.turnStarted(sessionID: request.session.id))
                continuation.yield(.outputChunk(output))
                continuation.yield(.turnCompleted(ProcessResult(exitCode: 1, output: output)))
            } else {
                let output = MockHarnessBackendAdapter.planningPlanForTests(for: request.prompt)
                continuation.yield(.turnStarted(sessionID: request.session.id))
                continuation.yield(.outputChunk(output))
                continuation.yield(.turnCompleted(ProcessResult(exitCode: 0, output: output)))
            }
            continuation.finish()
        }
    }

    func respondToApproval(_ response: ApprovalResponse) async throws {}

    func cancelTurn(_ request: CancelTurnRequest) async throws {}
}

struct UniqueReviewerOutputHarnessBackendAdapter: HarnessBackendAdapter {
    func startSession(_ request: StartSessionRequest) async throws -> BackendSession {
        BackendSession(
            id: UUID().uuidString,
            backendName: "unique-reviewer-output",
            project: request.project
        )
    }

    func resumeSession(_ request: ResumeSessionRequest) async throws -> BackendSession {
        request.session
    }

    func startTurn(_ request: StartTurnRequest) async throws -> AsyncThrowingStream<BackendEvent, Error> {
        AsyncThrowingStream { continuation in
            let output: String
            if request.prompt.isReviewerPrompt, request.prompt.contains("Reviewer A") {
                output = "Reviewer A unique feedback"
            } else if request.prompt.isReviewerPrompt, request.prompt.contains("Reviewer B") {
                output = "Reviewer B unique feedback"
            } else {
                output = MockHarnessBackendAdapter.planningPlanForTests(for: request.prompt)
            }
            continuation.yield(.turnStarted(sessionID: request.session.id))
            continuation.yield(.outputChunk(output))
            continuation.yield(.turnCompleted(ProcessResult(exitCode: 0, output: output)))
            continuation.finish()
        }
    }

    func respondToApproval(_ response: ApprovalResponse) async throws {}

    func cancelTurn(_ request: CancelTurnRequest) async throws {}
}

struct FailingPlannerResponseHarnessBackendAdapter: HarnessBackendAdapter {
    func startSession(_ request: StartSessionRequest) async throws -> BackendSession {
        BackendSession(
            id: UUID().uuidString,
            backendName: "failing-planner-response",
            project: request.project
        )
    }

    func resumeSession(_ request: ResumeSessionRequest) async throws -> BackendSession {
        request.session
    }

    func startTurn(_ request: StartTurnRequest) async throws -> AsyncThrowingStream<BackendEvent, Error> {
        AsyncThrowingStream { continuation in
            if request.prompt.isPlannerResponsePrompt {
                let output = "Planner response failed."
                continuation.yield(.turnStarted(sessionID: request.session.id))
                continuation.yield(.outputChunk(output))
                continuation.yield(.turnCompleted(ProcessResult(exitCode: 1, output: output)))
            } else if request.prompt.isReviewerPrompt {
                continuation.yield(.turnStarted(sessionID: request.session.id))
                continuation.yield(.outputChunk("pass"))
                continuation.yield(.turnCompleted(ProcessResult(exitCode: 0, output: "pass")))
            } else {
                let output = MockHarnessBackendAdapter.planningPlanForTests(for: request.prompt)
                continuation.yield(.turnStarted(sessionID: request.session.id))
                continuation.yield(.outputChunk(output))
                continuation.yield(.turnCompleted(ProcessResult(exitCode: 0, output: output)))
            }
            continuation.finish()
        }
    }

    func respondToApproval(_ response: ApprovalResponse) async throws {}

    func cancelTurn(_ request: CancelTurnRequest) async throws {}
}

final class FailingSecondPlannerResponseHarnessBackendAdapter: HarnessBackendAdapter {
    private let lock = NSLock()
    private var plannerResponseCount = 0

    func startSession(_ request: StartSessionRequest) async throws -> BackendSession {
        BackendSession(
            id: UUID().uuidString,
            backendName: "failing-second-planner-response",
            project: request.project
        )
    }

    func resumeSession(_ request: ResumeSessionRequest) async throws -> BackendSession {
        request.session
    }

    func startTurn(_ request: StartTurnRequest) async throws -> AsyncThrowingStream<BackendEvent, Error> {
        AsyncThrowingStream { continuation in
            let output = self.output(for: request.prompt)
            let exitCode = output.exitCode
            continuation.yield(.turnStarted(sessionID: request.session.id))
            continuation.yield(.outputChunk(output.text))
            continuation.yield(.turnCompleted(ProcessResult(exitCode: exitCode, output: output.text)))
            continuation.finish()
        }
    }

    func respondToApproval(_ response: ApprovalResponse) async throws {}

    func cancelTurn(_ request: CancelTurnRequest) async throws {}

    private func output(for prompt: String) -> (text: String, exitCode: Int32) {
        guard prompt.isPlannerResponsePrompt else {
            return prompt.isReviewerPrompt
                ? ("pass", 0)
                : (MockHarnessBackendAdapter.planningPlanForTests(for: prompt), 0)
        }
        lock.lock()
        plannerResponseCount += 1
        let currentCount = plannerResponseCount
        lock.unlock()
        return currentCount == 1
            ? (alternateValidPlanMarkdown, 0)
            : ("Second planner response failed.", 1)
    }
}

struct NoPlanPlannerResponseHarnessBackendAdapter: HarnessBackendAdapter {
    func startSession(_ request: StartSessionRequest) async throws -> BackendSession {
        BackendSession(
            id: UUID().uuidString,
            backendName: "no-plan-planner-response",
            project: request.project
        )
    }

    func resumeSession(_ request: ResumeSessionRequest) async throws -> BackendSession {
        request.session
    }

    func startTurn(_ request: StartTurnRequest) async throws -> AsyncThrowingStream<BackendEvent, Error> {
        AsyncThrowingStream { continuation in
            let output: String
            if request.prompt.isPlannerResponsePrompt {
                output = "I recommend keeping the plan unchanged."
            } else if request.prompt.isReviewerPrompt {
                output = "pass"
            } else {
                output = MockHarnessBackendAdapter.planningPlanForTests(for: request.prompt)
            }
            continuation.yield(.turnStarted(sessionID: request.session.id))
            continuation.yield(.outputChunk(output))
            continuation.yield(.turnCompleted(ProcessResult(exitCode: 0, output: output)))
            continuation.finish()
        }
    }

    func respondToApproval(_ response: ApprovalResponse) async throws {}

    func cancelTurn(_ request: CancelTurnRequest) async throws {}
}

struct FailingPlanningArtifactMaterializer: PlanningPlanArtifactMaterializing {
    enum Failure {
        case consolidatedFeedback
        case plannerResponsePlan
    }

    let failure: Failure
    private let store = PlanningPlanArtifactStore()

    func prepareDraftArtifact(project: WorkflowProject, sessionID: String) throws -> PlanningDraftArtifact {
        try store.prepareDraftArtifact(project: project, sessionID: sessionID)
    }

    func loadDraftArtifact(_ artifact: PlanningDraftArtifact) throws -> PlanningLoadedDraftArtifact {
        try store.loadDraftArtifact(artifact)
    }

    func materializeDraftArtifact(
        project: WorkflowProject,
        sessionID: String,
        content: String
    ) throws -> PlanningLoadedDraftArtifact {
        try store.materializeDraftArtifact(project: project, sessionID: sessionID, content: content)
    }

    func acceptDraftForReview(
        project: WorkflowProject,
        sessionID: String,
        producerStepID: String,
        request: PlanningDraftAcceptanceRequest
    ) throws -> PlanningDraftAcceptance {
        try store.acceptDraftForReview(
            project: project,
            sessionID: sessionID,
            producerStepID: producerStepID,
            request: request
        )
    }

    func materializeConsolidatedFeedback(
        project: WorkflowProject,
        sessionID: String,
        cycle: Int,
        content: String
    ) throws -> InteractiveStepOutput {
        if failure == .consolidatedFeedback {
            throw TestArtifactMaterializerError.requestedFailure
        }
        return try store.materializeConsolidatedFeedback(
            project: project,
            sessionID: sessionID,
            cycle: cycle,
            content: content
        )
    }

    func materializePlannerResponsePlan(
        project: WorkflowProject,
        sessionID: String,
        cycle: Int,
        content: String
    ) throws -> InteractiveStepOutput {
        if failure == .plannerResponsePlan {
            throw TestArtifactMaterializerError.requestedFailure
        }
        return try store.materializePlannerResponsePlan(
            project: project,
            sessionID: sessionID,
            cycle: cycle,
            content: content
        )
    }

    func finalizeReviewedPlan(
        project: WorkflowProject,
        sessionID: String,
        output: InteractiveStepOutput
    ) throws -> InteractiveStepOutput {
        try store.finalizeReviewedPlan(project: project, sessionID: sessionID, output: output)
    }
}

enum TestArtifactMaterializerError: LocalizedError {
    case requestedFailure

    var errorDescription: String? {
        "Requested artifact materializer failure."
    }
}

extension String {
    fileprivate var isPlannerResponsePrompt: Bool {
        contains("planner agent responding to automated review feedback")
    }

    fileprivate var isReviewerPrompt: Bool {
        contains("review-only planning agent")
    }

    fileprivate var firstLineForPromptSummary: String {
        split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
            ?? "Draft the requested plan."
    }

}
