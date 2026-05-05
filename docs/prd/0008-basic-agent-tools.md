# PRD-0008. Basic Agent Tools

**Status:** Draft
**Date:** 2026-04-28
**Owner:** Joshua Sumskas
**Related ADRs:** [ADR-0010. Tool Execution Context And Permission Boundary](../adr/0010-tool-execution-context-and-permission-boundary.md)
**Related Plans:** [Basic Agent Tools Technical Design](../plans/0007-basic-agent-tools-technical-design.md)

---

## Summary

Add basic agent-triggered tools to Hephaestus so a single-agent run can safely create and edit files inside the session's current working directory. The first tool set should be intentionally narrow: one write capability and one edit capability, with observable execution and clear permission boundaries for anything outside the current directory.

## Problem

Hephaestus can currently run chat turns, persist sessions, and inspect runtime events, but the agent cannot affect workspace state. That makes the harness useful for conversation and planning, but not yet useful as a working development assistant.

Before adding broader coding-agent behavior, Hephaestus needs a small, auditable tool model that proves how an agent asks for a tool, how the runtime authorizes it, how results return to the model, and how users can inspect what happened.

### Background

The roadmap calls for a stronger tool model with permissions and structured results before multi-agent workflows. Write and edit tools are the smallest useful step because they let the agent produce durable artifacts while keeping safety, inspection, and sandboxing requirements concrete.

### Users And Jobs

| User | Job To Be Done | Current Pain | Usage Context |
| --- | --- | --- | --- |
| App builder | Let the agent create or update files during a run | Agent output must be copied manually from chat | Developing Hephaestus and validating harness behavior |
| Power user | Understand what workspace changes the agent attempted | Tool behavior would be opaque without inspection | Reviewing an agent run before trusting changes |

## Product Outcome

A user can run a single-agent chat inside an opened workspace group. New chats in that group inherit the group's canonical workspace directory as their workspace root and session current directory. The agent may request a file write or file edit inside that directory by default. If the agent tries to write or edit outside that directory, including an explicit absolute path outside the workspace, the runtime creates an elevated permission request before execution. The result is returned to the agent, and the run record shows the tool request, authorization result, execution result, and affected path. Users can also customize the descriptions Hephaestus sends to the model for its core tools, so teams can tune tool guidance without changing tool implementation.

### Success Metrics

| Metric | Baseline | Target | Measurement Method |
| --- | --- | --- | --- |
| Tool capability | No agent tools | Agent can complete one write and one edit flow in a local workspace | Automated tests and manual CLI/app validation |
| Tool observability | No tool events | Tool request, permission result, and execution result are inspectable | Run inspection data review |
| Tool safety | No tool sandbox | File tools auto-allow only inside the session current directory and request elevation outside it, including explicit outside-workspace absolute paths | Path scope tests |
| Tool guidance control | Tool descriptions fixed in code | Core tool descriptions can be customized without code changes | Settings/state validation |

## Scope Boundaries

### In Scope

- Agent-requested `write_file` capability for complete text-file creation or overwrite.
- Agent-requested `edit_file` capability for basic text replacement.
- Current-directory scoped default grant for `write_file` and `edit_file`.
- Elevated permission request for write/edit attempts outside the session current directory, including explicit outside-workspace absolute paths.
- Canonical path restriction for file tools so path traversal or symlink escapes cannot bypass the grant boundary.
- User-customizable descriptions for core tools before they are exposed to the model.
- Structured runtime events for tool request, authorization, execution, success, and failure.
- Persisted tool execution summaries for run inspection.
- Mock-provider flow for deterministic validation.

### Out Of Scope

- Shell commands.
- File deletion.
- Binary file editing.
- Directory-wide rewrites.
- Multi-agent tool sharing.
- Background or long-running tools.
- Language-server, AST-aware, or semantic editing.
- Automatic merge conflict handling.

### Deferred

- Workspace picker in the macOS UI.
- Artifact browser with file hashes, previews, and snapshots.
- Unified-diff or patch-based editing.
- Tool execution visualization beyond inspector-ready data.
- Additional tools such as read, list, search, shell, or test-runner tools.
- Rich approval preferences such as remember-for-session, remember-for-path, or batch approval.

### Scope Creep Watchlist

- Turning this into a complete coding-agent environment.
- Adding shell execution before file-tool permissions and inspection are solid.
- Building multi-agent workflows on top of tools before the single-agent path is reliable.

## User Experience

### Primary Flow

1. User opens a workspace group rooted at a canonical directory.
2. User starts or opens a chat in that workspace group; the chat inherits the group directory as its workspace root and session current directory.
3. User asks the agent to create or edit a text file.
4. Agent requests the relevant tool.
5. Runtime resolves the tool path and canonicalizes the target or nearest existing parent.
6. If a workspace-relative path is inside the session current directory, runtime executes the tool under the default scoped grant and records the result.
7. If a workspace-relative path is outside the session current directory, runtime shows an elevated permission request that describes the tool, target path, and intended operation.
8. If an explicit absolute path is outside the workspace root, runtime also shows an elevated permission request for that exact resolved path.
9. User approves or denies the elevated request.
10. Runtime executes the approved elevated tool and records the result, or records a denied result.
11. Agent receives the tool result and responds with a final summary.
12. User can inspect the run and see the tool request, permission decision, result, and affected path.

### Tool Description Customization Flow

1. User opens tool settings.
2. User edits the model-facing description for a core tool.
3. Runtime validates that the description is non-empty and stores it.
4. Future provider requests expose the core tool with the customized description.
5. The tool implementation and permission behavior remain unchanged.
6. User can reset the customized description back to the built-in default.

### Edge And Failure States

- If a tool is disabled, the run records a denied tool result and the agent is told the tool was denied.
- If a write/edit request targets a path outside the session current directory, runtime asks for elevated permission before executing it.
- If the user denies an elevated permission request, the file is not modified and the agent receives a denied result.
- If an elevated permission request is cancelled, expires, or loses its active turn, the tool is not executed and the run records a denied/cancelled result.
- If a write/edit request uses an explicit absolute path outside the workspace root, the elevated prompt must show the resolved absolute path and approval is scoped to that exact path for that tool call.
- If a workspace-relative path escapes the approved scope through `..` traversal or symlink resolution, the tool is refused and records a clear error rather than silently converting it into outside-workspace elevation.
- If the session current directory no longer resolves safely inside the workspace root, default write/edit grants are disabled until the session directory is repaired or reselected.
- If an edit target does not match expected text, the edit fails without changing the file.
- If a write would overwrite an existing file without explicit overwrite permission, the write fails.
- If the provider requests an unknown tool, the turn fails or returns a structured unavailable-tool result.
- If a provider response requests multiple write/edit tool calls and any call needs elevation, the runtime resolves required elevation before executing side-effecting calls from that batch.
- If a customized tool description is empty or invalid, it is not saved and the previous description remains active.

## Functional Requirements

- **FR-1:** The system must let an agent request a basic file write tool during a run.
- **FR-2:** The system must let an agent request a basic file edit tool during a run.
- **FR-3:** The system must auto-allow write/edit tools only inside the session's canonical current working directory by default.
- **FR-4:** The system must require an elevated permission request before write/edit tools operate outside the session current directory, including explicit absolute paths outside the workspace root.
- **FR-5:** The system must return structured tool results to the agent so the turn can continue.
- **FR-6:** The system must persist inspectable summaries of tool execution.
- **FR-7:** The system must support deterministic mock-provider validation for tool flows.
- **FR-8:** The system must allow users to customize model-facing descriptions for core tools without changing tool execution behavior.

## Acceptance Criteria

- **AC-1.1** (`FR-1`): Given the agent requests a valid file write inside the session current directory, then the file is written and the agent receives a success result without an elevated permission request.
- **AC-1.2** (`FR-1`): Given overwrite is not allowed for a write request, when the target file already exists, then the write fails without changing the file.
- **AC-2.1** (`FR-2`): Given the agent requests an exact text replacement inside the session current directory with the expected occurrence count, then the file is updated without an elevated permission request.
- **AC-2.2** (`FR-2`): Given an edit request has zero or unexpected multiple matches, then the edit fails without changing the file.
- **AC-3.1** (`FR-3`): Given a workspace-relative tool request resolves inside the session current directory, then it is eligible for the default scoped grant.
- **AC-3.2** (`FR-3`): Given a workspace-relative tool request uses path traversal or symlink traversal to escape the approved scope, then execution is refused rather than elevated.
- **AC-4.1** (`FR-4`): Given the agent requests a write/edit outside the session current directory, then the runtime shows an elevated permission request before modifying files.
- **AC-4.2** (`FR-4`): Given the user denies an elevated permission request, then the tool is not executed and the run records a denied result.
- **AC-4.3** (`FR-4`): Given the agent requests a write/edit using an explicit absolute path outside the workspace root, then the runtime shows an elevated permission request scoped to that exact resolved path and tool call.
- **AC-5.1** (`FR-5`): Given a tool completes, then the provider receives a tool result message before the final assistant response is produced.
- **AC-6.1** (`FR-6`): Given a tool is requested, then persisted run data includes the tool name, status, affected path when available, permission decision, permission source/scope, and result or error summary.
- **AC-7.1** (`FR-7`): Given the mock provider is configured for tool validation, then tests can drive write and edit tool flows without a live model endpoint.
- **AC-8.1** (`FR-8`): Given a user customizes a core tool description, when a future provider request exposes that tool, then the request uses the customized description.
- **AC-8.2** (`FR-8`): Given a user attempts to save an empty tool description, then the save is rejected and the previous description remains active.
- **AC-8.3** (`FR-8`): Given a user resets a core tool description, when a future provider request exposes that tool, then the request uses the built-in default description.
- **AC-8.4** (`FR-8`): Given a customized description contradicts the immutable tool name, schema, or permission behavior, then the tool implementation still follows the immutable runtime contract.

## Dependencies

- Existing single-agent `Run` execution loop.
- Existing runtime event and persistence pipeline.
- Existing run inspection data model.
- Provider adapter support for tool-call style responses.
- A workspace group model where chats inherit the group's canonical workspace directory as their workspace root and session current directory.

## Product Risks

- Users may over-trust file changes if inspection is weak.
- Default current-directory grants may be too broad if the current directory is chosen carelessly.
- Path sandboxing mistakes could allow writes outside the intended workspace.
- Custom descriptions could make tools less clear to the model if validation and reset behavior are weak.
- Adding tool execution too broadly could distract from proving the minimal single-agent harness.

## Technical Design Gate

| Field | Value |
| --- | --- |
| Separate technical design required? | Yes |
| Rationale | Tool execution touches provider protocol, runtime turn loops, persistence, permissions, file-system safety, and tests. |
| Plan link | [Basic Agent Tools Technical Design](../plans/0007-basic-agent-tools-technical-design.md) |
| Blocks implementation until resolved? | Yes |
| Owner | Joshua Sumskas |

### Product Constraints For Technical Design

- File tool paths should be workspace-relative for normal in-workspace operations.
- Explicit absolute paths should be accepted only as elevated outside-workspace requests and must never be eligible for the default grant.
- File write/edit tools must be auto-allowed only inside the session's canonical current working directory by default.
- File write/edit attempts outside the session current directory must become elevated permission requests.
- Tool results must be observable in the run record.
- The first edit capability should favor deterministic failure over clever best-effort edits.
- The app must not silently enable destructive workspace mutation.
- Core tool descriptions must be user-customizable without changing executor semantics.
- The first implementation should keep shell execution out of scope.

### Open Technical Questions

- Should the first implementation add a dedicated `HephaestusTools` module?
- Should full tool arguments be persisted, summarized, or redacted?
- Should a later version support durable approval resume across app restarts?

## Milestones

| Milestone | Outcome | Included FRs | Excluded Scope | Exit Criteria | Dependencies |
| --- | --- | --- | --- | --- | --- |
| M1 | Deterministic local file tools | FR-1, FR-2, FR-3, FR-4, FR-7 | Live provider tool calls, rich approval preferences | Mock-provider tests can write/edit inside the session current directory, request elevation elsewhere, and refuse traversal/symlink escapes | Tool executor and policy model |
| M2 | Tool loop and persistence | FR-5, FR-6 | Full inspector UI polish | A run records tool events and returns results to the agent before final response | Runtime event and persistence changes |
| M3 | Custom tool descriptions and provider support | FR-5, FR-8 | Additional tools | Live provider can request supported tools through the same runtime path using configured descriptions | Provider adapter tool-call parsing |

## Validation Plan

### Pre-Implementation Validation

- Review the technical design for tool loop, permission, and persistence boundaries.
- Confirm whether a separate tools module is warranted before implementation.

### Implementation Validation

- Automated tests for successful write/edit flows.
- Automated tests for denied tools, path escapes, existing-file writes, and failed edit matches.
- Automated tests for current-directory auto-allow, outside-directory elevation approval/denial, explicit outside-workspace elevation approval/denial, traversal/symlink refusal, and canonical parent resolution for new files.
- Automated tests for custom tool description persistence and provider request usage.
- Automated tests for custom tool description reset behavior.
- Automated tests for persisted tool summaries and ordered runtime events.
- Mock-provider end-to-end test proving tool result is returned before final assistant response.
- Provider-adapter tests for tool request encoding and streamed tool-call parsing.

### Ship Criteria

- File write and edit tools work in a configured local workspace.
- File write/edit tools are auto-allowed only inside the session current directory by default.
- File write/edit attempts outside the session current directory request elevated permission.
- Explicit absolute outside-workspace write/edit attempts request elevated permission scoped to the exact resolved path and tool call.
- Tool execution cannot bypass scope checks through traversal or symlink escapes.
- Denied and failed tool calls are visible and understandable.
- Customized core tool descriptions are used in future model requests.
- Tool events are persisted for inspection.
- The feature remains limited to write/edit; shell and delete are not present.

## Open Questions

| Question | Owner | Blocks Implementation? | Resolve In PRD/ADR/Plan | Resolution |
| --- | --- | --- | --- | --- |
| Should file tools live in `HephaestusKernel`, `HephaestusRuntime`, or a new `HephaestusTools` module? | Joshua Sumskas | Yes | Plan/ADR | TBD |
| Should exact text replacement be the only v1 edit shape? | Joshua Sumskas | No | Plan | Recommended for v1 |
| Should full arguments be persisted? | Joshua Sumskas | No | Plan | Persist summaries by default; reserve full arguments for explicit diagnostics. |

---

## Notes

This PRD intentionally treats write/edit tools as a harness capability, not a complete development-agent product. More tools should be added only after permissions, eventing, persistence, and inspection feel boring and reliable.

**Last Updated:** 2026-04-28
