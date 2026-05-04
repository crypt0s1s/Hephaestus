# PRD-0009. Meta-Harness Foundation

**Status:** Shipped
**Date:** 2026-05-04
**Owner:** Joshua Sumskas
**Related ADRs:** [ADR-0006. Package Boundaries And Cross-Package Deep Links](../adr/0006-package-boundaries-and-cross-package-deep-links.md)
**Related Plans:** [Meta-Harness Foundation Refactor](../plans/0008-meta-harness-foundation-refactor.md)

---

## Summary

Reframe the current chat-first Hephaestus app toward a project/task/operator model without regressing the existing conversation mechanics. The shipped slice makes the app route through a task workspace, represents current conversation work as task-shaped work inside a project-shaped workspace, and prepares run inspection and backend identity to become reusable product surfaces.

## Problem

Hephaestus is intended to become a meta-harness/operator app for agent work, but the app previously presented chat as the central product object. This made it hard to add project-scoped navigation, task workflow state, reusable run inspection, and future harness backends without continuing to grow a chat feature into the whole application.

### Background

The current chat service boundary is useful: chat IO now outlives page interactors, and runtime events are applied by session-scoped services. The next product risk is that project, task, backend, and observability concepts will keep being introduced as chat-specific state unless the first meta-harness foundation is defined before implementation.

### Users And Jobs

| User | Job To Be Done | Current Pain | Usage Context |
| --- | --- | --- | --- |
| App builder | Extend Hephaestus toward task/workflow UI without breaking chat | All new product concepts naturally land in `ChatFeature` | Implementing the next app architecture slices |
| Operator user | Understand work as tasks and runs rather than only transcripts | Chat history does not express project, task, backend, or workflow state | Running and inspecting agent work in a local project |

## Product Outcome

The app can keep current conversation behavior working while routing through a task workspace and internally representing the selected work as a task-backed conversation in a project context. The current native runtime can be identified as the Foundry backend at the product layer, and run inspection can begin moving toward a reusable observation model instead of a chat-only popover.

### Success Metrics

| Metric | Baseline | Target | Measurement Method |
| --- | --- | --- | --- |
| Chat compatibility | Current chat send/select/cancel/inspect works | No behavioral regression | Existing tests and manual smoke test |
| Task readiness | Chats are only chat/session-shaped | Current sessions can be projected as task-shaped work | Projection tests and app state review |
| Backend readiness | Runtime/provider selection is app/chat-specific | Current native runtime has a product-level backend identity | Contract tests or static descriptor validation |
| Inspection readiness | Inspector consumes chat/runtime persistence directly | Inspection has a reusable run snapshot contract | Mapping tests |

## Scope Boundaries

### In Scope

- A minimal project concept for the current local workspace context.
- A minimal task concept that can represent existing chat sessions as task-backed conversations.
- A minimal workflow-state concept for current draft/running/failed/completed task status.
- Product-level backend identity for the current native runtime as Foundry.
- A reusable run inspection/observation projection over current persisted runtime data.
- Preservation of existing conversation behavior and persistence.

### Out Of Scope

- Replacing the current conversation UI with the final project/task/workflow UI.
- Renaming existing runtime packages to Foundry.
- Implementing Codex CLI or Claude Code adapters.
- Building workflow builder UI or workflow recipes.
- Multi-agent orchestration.
- Full project discovery or workspace indexing.
- A complete backend manager surface.

### Deferred

- Dedicated `ProjectWorkspaceFeature`.
- Dedicated `ConversationFeature`.
- Dedicated `RunInspectorFeature`.
- Backend health checks and executable discovery.
- Replay, export, redaction, and backend comparison views.

### Scope Creep Watchlist

- Treating this slice as permission to rewrite the app shell.
- Moving all persistence into project/task storage immediately.
- Designing every future feature package before the first extraction proves useful.
- Surfacing fake future backends as runnable options.

## User Experience

### Primary Flow

1. User opens Hephaestus and sees the task workspace.
2. User starts or selects a task.
3. System preserves current conversation behavior.
4. Internally, the selected task can be understood as work for a default project and task.
5. User can inspect the current run as before.
6. Future task workspace UI can reuse the same task, backend, and observation concepts.

### Edge And Failure States

- If no explicit project exists, the app uses a default local project projection.
- If an existing persisted session has no task storage, the task projection is derived without requiring storage migration.
- If a task conversation is running, the projected task status reflects running state.
- If inspection data is missing, the current no-inspection state remains available.
- Task switching, cancellation, persistence reload, and run inspection must not regress.

## Functional Requirements

- **FR-1:** The system must preserve current conversation send, task switch, cancel, reload, and inspect behavior.
- **FR-2:** The system must support a minimal project concept suitable for current local work.
- **FR-3:** The system must support a minimal task concept that can represent current chat sessions.
- **FR-4:** The system must expose the current native runtime as a product-level Foundry backend descriptor without renaming runtime packages.
- **FR-5:** The system must provide a reusable observation/run-inspection projection over current persisted run data.
- **FR-6:** The system must keep workflow builder, Codex CLI, and Claude Code out of the first slice.

## Acceptance Criteria

- **AC-1.1** (`FR-1`): Given an existing persisted session, when the app opens or selects it as a task, then the transcript and run state still load as before.
- **AC-1.2** (`FR-1`): Given a response is streaming, when the user switches tasks, then events remain scoped to their original task/session.
- **AC-1.3** (`FR-1`): Given a selected task is running, when the user cancels, then only the selected task's active turn is cancelled.
- **AC-2.1** (`FR-2`): Given no explicit project has been created, then current work can still be associated with a default local project concept.
- **AC-3.1** (`FR-3`): Given a persisted session summary, then the app can project it into a task summary without changing stored session data.
- **AC-3.2** (`FR-3`): Given a selected task has running or error state, then the projected task status can reflect that state.
- **AC-4.1** (`FR-4`): Given the current native runtime is active, then product-level metadata can identify it as the Foundry backend.
- **AC-4.2** (`FR-4`): Given Codex CLI and Claude Code are future backends, then this slice does not expose them as runnable adapters.
- **AC-5.1** (`FR-5`): Given current persisted run inspection data, then it can be mapped into a reusable run inspection snapshot with event order, run ID, summary, and error information preserved.
- **AC-6.1** (`FR-6`): Given implementation begins, then no workflow builder, Codex CLI adapter, or Claude Code adapter is added as part of this PRD.

## Dependencies

- Existing task workspace/session behavior.
- Existing persisted session/runtime event data.
- Existing run inspection use case.
- ADR-0006 package boundary and route-contract direction.
- Product direction from `docs/vision.md`, `docs/product-ui-vision.md`, `docs/observability-objectives.md`, and `docs/modularization-objectives.md`.

## Product Risks

- Users may not see visible value immediately if the first slice is mostly structural.
- A task projection that mirrors chat too closely could preserve chat-first assumptions.
- Backend identity could become misleading if unsupported capabilities are marked too optimistically.
- Over-extraction could slow the next implementation slice without improving boundaries.

## Technical Design Gate

| Field | Value |
| --- | --- |
| Separate technical design required? | Yes |
| Rationale | The slice changes package boundaries, domain contracts, backend identity, and observation ownership while preserving existing chat behavior. |
| Plan link | [Meta-Harness Foundation Refactor](../plans/0008-meta-harness-foundation-refactor.md) |
| Blocks implementation until resolved? | Yes |
| Owner | Joshua Sumskas |

### Product Constraints For Technical Design

- Preserve existing conversation behavior during the refactor.
- Do not replace the current conversation mechanics in the first slice.
- Keep core/domain packages independent of SwiftUI, Anvil, and feature packages.
- Keep the app target as composition root, not feature owner.
- Do not rename all current runtime packages to Foundry in the first slice.
- Do not implement Codex CLI or Claude Code adapters yet.
- Prefer incremental extraction over theoretical completeness.

### Open Technical Questions

- Should the default project be persisted immediately or remain a projection until project selection exists?
- Should task IDs initially match session IDs to reduce migration pressure?
- Should runtime-to-observation mapping live in composition instead of the observation contract package?

## Milestones

| Milestone | Outcome | Included FRs | Excluded Scope | Exit Criteria | Dependencies |
| --- | --- | --- | --- | --- | --- |
| M1 | Domain and projection foundation | FR-1, FR-2, FR-3 | Full project UI, storage migration | Existing chats still work and can be represented as task-shaped work | Current chat persistence |
| M2 | Observation contract foundation | FR-1, FR-5 | Replay/export/comparison UI | Current inspection maps into reusable run snapshots | Current inspector data |
| M3 | Backend descriptor foundation | FR-4, FR-6 | Codex CLI and Claude Code adapters | Current native runtime has a Foundry backend descriptor and no fake external adapters | Harness contract package |

## Validation Plan

### Pre-Implementation Validation

- Review the linked technical plan for package direction, temporary compromises, and non-goals.
- Confirm no new ADR is needed beyond ADR-0006 before the first extraction; create one only if implementation discovers a durable boundary decision not covered by existing ADRs.

### Implementation Validation

- Run existing task workspace service/interactor tests.
- Add projection tests for session-to-task mapping.
- Add observation mapping tests.
- Run `swift build` and `swift test`.
- Manually smoke test chat send, selection, streaming switch, cancel, inspect, and persisted reload.

### Ship Criteria

- Current conversation behavior is unchanged.
- Existing stored sessions remain readable.
- New project/task/backend/observation concepts are available for the next task workspace slice.
- No external backend adapters or workflow builder code are included.

## Open Questions

| Question | Owner | Blocks Implementation? | Resolve In PRD/ADR/Plan | Resolution |
| --- | --- | --- | --- | --- |
| Persist default project now or later? | Joshua Sumskas | No | Plan | TBD |
| Match task IDs to session IDs in the bridge? | Joshua Sumskas | No | Plan | TBD |
| Add a new ADR for harness backend descriptors? | Joshua Sumskas | No | ADR if needed | Existing ADR-0006 may be enough for first slice |

---

## Notes

This PRD intentionally describes the product outcome and constraints. Package names, type sketches, implementation phases, validation commands, and temporary compromises live in the linked implementation plan.

**Last Updated:** 2026-05-04
