# PRD-0005. Context Management V1

**Status:** Draft
**Date:** 2026-04-25
**Owner:** Joshua Sumskas
**Related ADRs:** [ADR-0002](../adr/0002-swift-kernel-baseline.md)
**Related Plans:** [Complete Single-Agent Harness PRDs](../plans/0003-complete-single-agent-harness-prds.md)

---

## Summary

Make context management visible and controllable enough that users can understand what conversation state is being sent to the model for each turn.

## Problem

The long-term product depends on custom context management, not raw transcript replay. Today, context behavior is not a visible product concept. Without context visibility, users cannot trust or debug why the assistant responded the way it did.

## Users And Jobs

| User | Job To Be Done | Current Pain | Usage Context |
| --- | --- | --- | --- |
| App builder | Verify context assembly is intentional | Context behavior is hidden | Runtime development |
| Early user | Understand whether prior messages are included | Assistant continuity is opaque | Longer chats |

## Product Outcome

For each turn, the user can inspect a simple context summary showing what was included, what was excluded, and why.

## Success Metrics

| Metric | Baseline | Target | Measurement Method |
| --- | --- | --- | --- |
| Context visibility | Hidden | User can inspect included/excluded context | Manual validation |
| Context policy clarity | Implicit | Active policy is visible | Manual validation |
| Debug usefulness | Requires code inspection | User can explain context selection from UI | Manual validation |

## Scope Boundaries

### In Scope

- Show the active context policy for a run.
- Show included and excluded messages for a turn.
- Show a simple reason/trace for context selection.
- Support a basic context budget or message limit view.

### Out Of Scope

- Automatic summarization.
- Long-term memory/RAG.
- User-editable context packages.
- Artifact recall.
- Multi-agent context sharing.

### Deferred

- Compaction/summarization.
- Working memory.
- Context editing.
- Context quality metrics.

## User Experience

### Primary Flow

1. User sends a message.
2. Assistant responds.
3. User opens context details for the turn.
4. App shows included messages, excluded messages, and active context policy.

### Edge And Failure States

- If no context trace exists, the UI says context details are unavailable.
- If all messages fit, excluded context is shown as empty.
- Context details should remain readable for short chats.

## Functional Requirements

- **FR-1:** The app must expose context details for a completed turn.
- **FR-2:** Context details must show included messages.
- **FR-3:** Context details must show excluded messages or explicitly show none were excluded.
- **FR-4:** Context details must show the active context policy.
- **FR-5:** Missing context traces must be handled clearly.

## Acceptance Criteria

- **AC-1.1** (`FR-1`): Given a completed turn, when the user opens context details, then context information is visible.
- **AC-2.1** (`FR-2`): Given messages were included, then those messages are listed or summarized.
- **AC-3.1** (`FR-3`): Given messages were excluded, then the excluded set is visible.
- **AC-3.2** (`FR-3`): Given nothing was excluded, then the UI clearly says no messages were excluded.
- **AC-4.1** (`FR-4`): Given a context policy was used, then its name or description is visible.
- **AC-5.1** (`FR-5`): Given context trace is missing, then the app shows an explicit unavailable state.

## Dependencies

- Persistent or inspectable run state.
- Runtime context trace data.
- Basic UI surface for run/turn details.

## Product Risks

- Context UI can become too technical for early users.
- Showing raw messages may be enough for V1 but not for future compacted context.
- This can grow into memory/RAG too early if scope is not held.

## Technical Design Gate

| Field | Value |
| --- | --- |
| Separate technical design required? | Yes |
| Rationale | Context visibility depends on runtime event data, persistence/inspection surfaces, and UI decisions. |
| Plan link | [Complete Single-Agent Harness PRDs](../plans/0003-complete-single-agent-harness-prds.md) |
| Blocks implementation until resolved? | Yes |
| Owner | Joshua Sumskas |

### Product Constraints For Technical Design

- Context details must be explainable to a user, not only useful to an implementer.
- V1 must not require summarization or long-term memory.
- Context trace data should support future compaction features.

## Milestones

| Milestone | Outcome | Included FRs | Excluded Scope | Exit Criteria | Dependencies |
| --- | --- | --- | --- | --- | --- |
| M1 | Context trace is available | FR-1 | UI polish | Completed turn has inspectable trace | Runtime support |
| M2 | Included/excluded context visible | FR-2, FR-3 | Summarization | User can inspect context membership | M1 |
| M3 | Policy visible and missing state handled | FR-4, FR-5 | Editable context | UI explains policy/unavailable state | M2 |

## Validation Plan

### Pre-Implementation Validation

- Confirm which run/turn UI surface will host context details.
- Confirm required context trace data exists or will be added.

### Implementation Validation

- Inspect a short chat where all messages fit.
- Inspect a chat where older messages are excluded.
- Inspect missing/unavailable trace state.

### Ship Criteria

- User can inspect context for a completed turn.
- Included/excluded context is visible.
- Active policy is visible.

## Open Questions

| Question | Owner | Blocks Implementation? | Resolve In PRD/ADR/Plan | Resolution |
| --- | --- | --- | --- | --- |
| Should context details live in chat UI or a run inspector? | Joshua Sumskas | Yes | Plan | In the run inspector for v1. |
| What is the first user-facing context policy name? | Joshua Sumskas | No | Plan | Recent messages. |

---

## Notes

This PRD should precede advanced context compaction so the product has a visible place to explain context decisions.

**Last Updated:** 2026-04-25
