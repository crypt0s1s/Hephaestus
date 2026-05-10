# Interactive Workflow Step Spike

**Status:** Proposed
**Date:** 2026-05-08
**Related PRD:** [PRD-0011. Interactive Planning Review Workflow](../prd/0011-interactive-planning-review-workflow.md)
**Related ADRs:** TBD

## 1. Purpose

PRD-0011 uses a planning-review workflow to prove that Hephaestus can support interactive workflow steps, runtime-owned workflow messages, and cross-session handoff between interactive and automated phases.

This spike should answer the architecture questions well enough to decide whether the next artifact should be an ADR, a technical implementation plan, or a small prototype. It should not implement the full planning-review workflow.

## 2. Questions To Answer

### 2.1 Interactive Pause And Resume

How should Hephaestus represent a workflow step that pauses for user interaction and later resumes?

Options to investigate:

- **Workflow-owned pause state:** the workflow run records `waitingForInput(stepID, expectedMessageKind)` and resumes when the expected runtime message is submitted.
- **Session-owned interaction:** the planner session owns conversation state and the workflow watches for a submitted message from that session.
- **Hybrid:** the workflow owns pause/resume state, while the interactive session owns conversation UI and message drafting.
- **Workflow-attached chat:** provide a chat interface for an interactive workflow step, with the workflow run owning the expected output message and the chat session owning conversation. This may reuse existing chat foundations, but reuse is not required if a cleaner workflow-attached design needs a fresh surface.

The spike should compare these against:

- visibility in the workflow timeline,
- ability to resume after UI navigation,
- fit with external workflow packages,
- testability,
- future workflow-builder compatibility.

### 2.2 Submit-Plan Interaction

How does the user materialize the draft plan into a workflow message?

Known product constraint:

- The user chooses when to submit the plan.
- The planner phase does not need to continuously write a plan file.

Options to investigate:

- explicit UI action, such as `Submit Plan`,
- slash/command message inside the interactive planner session,
- structured draft panel with a submit button,
- selected message or selected text promoted into a submitted-plan message.

The spike should recommend the smallest happy-path interaction and explain how it can evolve.

### 2.2.1 Chat Surface Direction

Hephaestus already has chat/session foundations in the agent harness and task workspace area. The spike should inspect them for reusable lessons, but the goal is not to preserve the existing shape. The goal is a clean workflow-attached chat design that can eventually support its own agent harness.

Inspect:

- `Features/TaskWorkspaceFeature/Sources/TaskWorkspaceFeature/TaskWorkspacePage.swift`
- `Features/TaskWorkspaceFeature/Sources/TaskWorkspaceFeature/ConversationViews.swift`
- `Features/TaskWorkspaceFeature/Sources/TaskWorkspaceFeature/TaskSessionService.swift`
- `Features/TaskWorkspaceFeature/Sources/TaskWorkspaceFeature/TaskSessionServiceRegistry.swift`
- `Features/TaskWorkspaceFeature/Sources/TaskWorkspaceFeature/TaskWorkspaceInteractor.swift`
- `Core/HephaestusRuntime/Sources/HephaestusRuntime/AppStateStorage.swift`
- `Core/HephaestusRuntime/Sources/HephaestusRuntime/PersistentRuntimeUseCases.swift`

The key question is not whether these can run an ordinary chat; they can. The key question is what the workflow-attached chat interface should own:

- the workflow step owns `expectedMessageKind`,
- the chat session owns transcript and turn streaming,
- a submit action promotes conversation output into a runtime-owned `WorkflowMessage`,
- later workflow phases can reopen or reconstruct the planner context.

The spike should be willing to recommend starting from scratch if the existing `TaskWorkspaceFeature` assumptions make workflow ownership, typed message submission, or future agent-harness separation harder.

### 2.3 Planner Continuity

How is planner continuity represented across initial interactive planning, automated planner-response work, and later continued planning?

Options to investigate:

- reuse the same interactive session for planner response,
- spawn a fresh automated planner-response session with summarized context,
- store a planner-state message that later sessions consume,
- hybrid session plus runtime messages.

The spike should identify what continuity means in the first slice:

- same session ID,
- same transcript,
- same role/profile,
- same submitted messages,
- or enough reconstructed context to behave coherently.

### 2.4 Runtime-Owned Workflow Messages

What first-slice message representation should connect submitted plans, reviewer feedback, consolidated reviews, and planner responses?

Product constraints:

- Workflow messages are runtime-owned encoded values.
- Agents do not need file write permission to produce workflow messages.
- `.hephaestus/` may persist/export messages for inspection, but it is not the handoff mechanism.
- The design should preserve a path toward future encodable step outputs and decodable step inputs.

Options to investigate:

```swift
struct WorkflowMessage: Codable, Identifiable {
  let id: String
  let kind: WorkflowMessageKind
  let producerStepID: String
  let createdAt: Date
  let payload: WorkflowMessagePayload
  let summary: String?
}

enum WorkflowMessagePayload: Codable {
  case submittedPlan(SubmittedPlanPayload)
  case reviewerFeedback(ReviewerFeedbackPayload)
  case consolidatedReview(ConsolidatedReviewPayload)
  case plannerResponse(PlannerResponsePayload)
}
```

The spike should compare:

- typed enum payloads,
- schema-tagged JSON payloads,
- type-erased Codable payload envelopes,
- file references as optional exports only.

### 2.5 `.hephaestus/` Persistence And Export

What should the first-slice `.hephaestus/` layout be if messages are runtime-owned?

Options to investigate:

- run-scoped `messages.jsonl` plus exported markdown summaries,
- one JSON file per message plus optional markdown exports,
- cycle-oriented folders with runtime messages and exports grouped by cycle.

The spike should recommend:

- layout,
- whether message persistence is required for the first implementation,
- what is debug/export only,
- cleanup/lifetime expectations.

### 2.6 Message Links

How should the UI and prompts refer to persisted/exported message content?

Current product leaning:

- Prefer project-relative links for files inside the selected project.
- Absolute paths are acceptable for local execution or external process handoff.
- App routes can be deferred unless needed for inspector deep links.

The spike should separate:

- runtime message identity used for workflow routing,
- optional file/export links used for UI, prompts, or debugging.

## 3. Suggested Investigation Method

1. Read the current workflow runner and implementation-review loop boundaries.
2. Identify where a pause state could live without blocking a subprocess.
3. Identify where runtime-owned messages could be stored in memory during a run.
4. Sketch how the planner submit action would flow through model state, runtime messages, and resumed automation.
5. Define the first-slice harness adapter boundary for workflow-attached chat and automated turns.
6. Compare at least two planner-continuity options.
7. Recommend a first-slice `.hephaestus/` persistence/export layout.
8. Decide whether the recommended pause/resume and harness-adapter model is durable enough for an ADR.

## 3.1 External Harness Research Findings

Initial research across Claude Code, Codex, OpenCode, ACP, Aider, and generic PTY wrappers points toward one strong pattern:

**Use semantic backend adapters as the primary integration. Keep PTY/terminal wrapping as an escape hatch or debug console, not as the source of truth for workflow state.**

Patterns to carry into the spike:

- Prefer SDK, app-server, JSON-RPC, JSONL, or `stream-json` modes when a CLI exposes them.
- Normalize backend-native events into Hephaestus workflow events while preserving raw backend payloads for debugging.
- Treat CLIs and SDK sessions as backend adapters, not as the workflow state model.
- Keep user-visible messages, normalized runtime events, and backend-native session metadata as separate layers.
- Track backend session IDs explicitly; do not rely on "continue latest session" semantics in product code.
- Make permissions app-owned: backend approval events should become Hephaestus approval requests and logged workflow events.
- Use PTY only for raw console mode, interactive auth, or tools that do not expose a semantic API.
- Do not require agents to write files to pass messages; the runtime owns message creation, routing, persistence, and optional export.

Reference examples:

- Claude Code Agent SDK / headless mode: `claude -p`, `--output-format json|stream-json`, resume/continue, tool allowlists, permission modes.
- Codex App Server and Codex `exec`: persistent child-process/app-server shape for rich UI, plus JSONL one-shot mode for automation.
- Agent Client Protocol: JSON-RPC/stdio protocol for editor-to-agent communication.
- OpenCode: TUI, `run`, `serve`, and `acp` modes as examples of multiple integration layers.
- Aider: scripting/message-file style as a simpler transcript-oriented contrast.
- PTY wrappers such as `node-pty`, `xterm.js`, and `SwiftTerm`: useful for terminal fidelity, weaker for semantic workflow state.

Implication for Hephaestus:

```text
Workflow owns orchestration state.
HarnessBackendAdapter owns backend launch/session/turn IO.
Runtime owns WorkflowMessage creation and routing.
UI renders normalized messages/events.
PTY is optional raw-console attachment.
```

## 3.2 First Implementation Direction

The first implementation should support Codex only, but it should introduce the adapter boundary now so workflow state does not become Codex-shaped by accident.

The spike should define the smallest useful host-side contract, roughly:

```swift
protocol HarnessBackendAdapter {
  func startSession(_ request: StartSessionRequest) async throws -> BackendSession
  func resumeSession(_ request: ResumeSessionRequest) async throws -> BackendSession
  func startTurn(_ request: StartTurnRequest) async throws -> AsyncThrowingStream<BackendEvent, Error>
  func respondToApproval(_ response: ApprovalResponse) async throws
  func cancelTurn(_ request: CancelTurnRequest) async throws
}
```

The exact names belong in the technical design. The important boundary is:

- Hephaestus owns workflow run state, pause/resume semantics, runtime messages, normalized events, approvals, and UI rendering.
- The adapter owns backend launch details, backend session IDs, backend-native event decoding, turn IO, resume mechanics, and cancellation mechanics.
- Workflow definitions depend on normalized `BackendEvent` and `WorkflowMessage` values, not Codex-specific event shapes.
- Backend-specific support decisions live inside adapters. Claude, OpenCode, Gemini, or ACP support should be future adapter additions, not workflow rewrites.

For the first Codex adapter:

- Prefer the Codex app-server style integration for workflow-attached interactive chat because it preserves rich turn/session/event semantics.
- Treat `codex exec --json` as a later or parallel one-shot automation path, useful for non-interactive workflow steps but not the primary shape for interactive planning.
- Persist backend session metadata separately from user-visible transcript and workflow messages.
- Preserve raw Codex events for debugging, but route the app from normalized events.
- Make app-owned approval handling part of the adapter contract instead of letting an embedded CLI own the product decision.

### 3.2.1 Implementation Status

Started in the first implementation slice:

- Added `HarnessBackendAdapter` and first-slice backend request/event/session types under `Hephaestus/Features/HarnessBackends`.
- Added `CodexHarnessBackendAdapter` as the only concrete backend.
- Refactored `CodexAgentStep` to run through the adapter boundary while preserving current `codex exec` workflow behavior.

Still pending:

- Workflow-attached interactive chat UI.
- Codex app-server integration for long-lived interactive sessions.
- Runtime-owned `WorkflowMessage` persistence and submit-plan flow.
- App-owned approval handling beyond the adapter contract.

## 4. Current Code Areas To Inspect

- `Features/TaskWorkspaceFeature/Sources/TaskWorkspaceFeature/TaskWorkspacePage.swift`
- `Features/TaskWorkspaceFeature/Sources/TaskWorkspaceFeature/ConversationViews.swift`
- `Features/TaskWorkspaceFeature/Sources/TaskWorkspaceFeature/TaskSessionService.swift`
- `Features/TaskWorkspaceFeature/Sources/TaskWorkspaceFeature/TaskSessionServiceRegistry.swift`
- `Features/TaskWorkspaceFeature/Sources/TaskWorkspaceFeature/TaskWorkspaceInteractor.swift`
- `Hephaestus/Features/WorkflowRunner/Interactors/WorkflowRunnerModel.swift`
- `Hephaestus/Features/WorkflowRunner/Models/WorkflowRunTypes.swift`
- `Hephaestus/Features/WorkflowRunner/Models/WorkflowRunnerState.swift`
- `Hephaestus/Features/WorkflowRunner/Views/WorkflowRunnerView.swift`
- `Hephaestus/Features/WorkflowRunner/Views/WorkflowRunOutputView.swift`
- `Hephaestus/Features/ImplementationReviewLoop/Runtime/WorkflowExecutor.swift`
- `Hephaestus/Features/ImplementationReviewLoop/Runtime/WorkflowRunState.swift`
- `Hephaestus/Features/ImplementationReviewLoop/Runtime/HeadlessCodexWorkflowRunner.swift`
- `Hephaestus/Features/ExternalWorkflows/Services/ExternalWorkflowRunner.swift`
- `Core/HephaestusRuntime/Sources/HephaestusRuntime/AppStateStorage.swift`
- `Core/HephaestusRuntime/Sources/HephaestusRuntime/PersistentRuntimeUseCases.swift`
- `ExampleWorkflows/ImplementationReviewExample/`

## 5. Deliverables

The spike should produce a short written result, either as a new doc or an update to this one, containing:

- recommended interactive pause/resume model,
- recommendation on the workflow-attached chat design, including which existing chat/session lessons to reuse and where starting from scratch is cleaner,
- minimal `HarnessBackendAdapter` contract and first-slice Codex adapter scope,
- recommended submit-plan interaction,
- planner-continuity options and first-slice recommendation,
- first-slice `WorkflowMessage` representation,
- `.hephaestus/` persistence/export recommendation,
- risks and unresolved questions,
- whether to write an ADR before implementation.

## 6. Non-Goals

- Do not implement the full planning-review workflow.
- Do not build a workflow builder UI.
- Do not design arbitrary generic Codable workflow IO completely.
- Do not implement Claude, OpenCode, Gemini, or ACP adapters in the first slice.
- Do not make `.hephaestus/` a durable artifact system.
- Do not solve broad recovery/retry semantics.

## 7. Exit Criteria

- We can explain how an interactive workflow step pauses and resumes.
- We can explain how `submit-plan` creates a runtime-owned workflow message.
- We can explain how reviewer feedback returns to the runtime without file write permission.
- We can explain how planner-response work receives consolidated feedback.
- We can explain how later interactive review receives the latest plan and feedback trail.
- We can explain the minimal harness adapter boundary and why the first implementation is Codex-only behind that boundary.
- We know whether an ADR is needed before implementation.
