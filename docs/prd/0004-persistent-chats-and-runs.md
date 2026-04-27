# PRD-0004. Persistent Chats And Runs

**Status:** Draft
**Date:** 2026-04-25
**Owner:** Joshua Sumskas
**Related ADRs:** [ADR-0008](../adr/0008-local-app-state-storage.md)
**Related Plans:** [Complete Single-Agent Harness PRDs](../plans/0003-complete-single-agent-harness-prds.md)

---

## Summary

Persist chat sessions and run history so users can close and reopen the app without losing prior conversations.

## Problem

The current chat loop is in-memory. Once the app closes or the run is lost, the user cannot resume or inspect prior conversations. A competent single-agent harness needs durable sessions before it can support longer-running work.

## Users And Jobs

| User | Job To Be Done | Current Pain | Usage Context |
| --- | --- | --- | --- |
| Early user | Continue a previous chat session | Conversations disappear after app/runtime reset | Multi-session app usage |
| App builder | Inspect prior runs while developing the harness | Prior state only exists in memory | Debugging and validation |

## Product Outcome

The user can see prior chat sessions, reopen one, and continue the conversation with previous messages visible.

## Success Metrics

| Metric | Baseline | Target | Measurement Method |
| --- | --- | --- | --- |
| Session durability | In-memory only | Chats survive app restart | Manual validation |
| Resume capability | No reopen path | User can reopen and continue a chat | Manual validation |
| Basic history visibility | No session list | User can identify prior chats | Manual validation |

## Scope Boundaries

### In Scope

- Persist chat sessions and messages.
- Show a basic list of prior chats.
- Reopen a prior chat.
- Continue a reopened chat.
- Preserve enough run metadata to support later inspection.

### Out Of Scope

- Full event timeline inspector.
- Context compaction.
- Cross-device sync.
- Search.
- Export/import.
- Multi-agent workflow persistence.

### Deferred

- Rich run browser.
- Artifact persistence.
- Replay from full event records.
- Conversation naming and organization polish.

## User Experience

### Primary Flow

1. User chats with the assistant.
2. User closes and reopens the app.
3. User sees the prior chat in a basic history surface.
4. User opens the prior chat.
5. Prior messages are visible.
6. User sends another message in the same conversation.

### Edge And Failure States

- Empty history shows a useful empty state.
- Persistence failure shows an explicit error.
- Corrupt or unsupported stored data does not crash the app.

## Functional Requirements

- **FR-1:** The app must persist chat sessions and messages.
- **FR-2:** The app must show a basic history of persisted chats.
- **FR-3:** The user must be able to reopen a persisted chat.
- **FR-4:** The user must be able to continue a reopened chat.
- **FR-5:** Persistence failures must be visible.

## Acceptance Criteria

- **AC-1.1** (`FR-1`): Given a completed chat turn, when the app restarts, then the prior messages are still available.
- **AC-2.1** (`FR-2`): Given one or more persisted chats, when the user opens the app, then a basic history surface can show them.
- **AC-3.1** (`FR-3`): Given a persisted chat, when the user opens it, then its messages are rendered.
- **AC-4.1** (`FR-4`): Given a reopened chat, when the user sends a new message, then the conversation continues from the prior messages.
- **AC-5.1** (`FR-5`): Given persistence cannot load, then the app shows an explicit error rather than a blank screen.

## Dependencies

- Working chat shell.
- Decision on persistence storage.
- Technical design for persistence model and migration path.

## Product Risks

- Persistence can force premature decisions about event storage and replay.
- A weak data model can block later run inspection.
- UI can expand into full navigation before the minimal history loop is proven.

## Technical Design Gate

| Field | Value |
| --- | --- |
| Separate technical design required? | Yes |
| Rationale | Persistence requires data modeling, migration strategy, app navigation, and runtime resume behavior. |
| Plan link | [Complete Single-Agent Harness PRDs](../plans/0003-complete-single-agent-harness-prds.md) |
| Blocks implementation until resolved? | Yes |
| Owner | Joshua Sumskas |

### Product Constraints For Technical Design

- Data should be durable across app restarts.
- Persisted chats should be reusable by future run inspection work.
- The first history UI should remain minimal.

## Milestones

| Milestone | Outcome | Included FRs | Excluded Scope | Exit Criteria | Dependencies |
| --- | --- | --- | --- | --- | --- |
| M1 | Messages persist | FR-1 | History UI | Restart preserves messages | Storage decision |
| M2 | Basic history exists | FR-2, FR-3 | Rich browser | User reopens a persisted chat | M1 |
| M3 | Reopened chats continue | FR-4, FR-5 | Replay inspector | User sends another message in reopened chat | M2 |

## Validation Plan

### Pre-Implementation Validation

- Decide storage technology and minimum data model.
- Decide whether runtime events are persisted now or deferred.

### Implementation Validation

- Create chat, restart app, reopen chat.
- Continue reopened chat.
- Force persistence load failure where feasible.

### Ship Criteria

- Prior chat survives restart.
- User can reopen and continue it.
- Persistence errors are visible.

## Open Questions

| Question | Owner | Blocks Implementation? | Resolve In PRD/ADR/Plan | Resolution |
| --- | --- | --- | --- | --- |
| Should PRD-0004 persist runtime events or only chat messages? | Joshua Sumskas | Yes | ADR/Plan | Persist messages plus lightweight runtime event, provider, turn, and context summaries. |
| What is the minimum history navigation UI? | Joshua Sumskas | Yes | Plan | Compact chat-history sidebar in the chat shell. |

---

## Notes

This PRD is the bridge from demo chat to competent single-agent harness.

**Last Updated:** 2026-04-25
