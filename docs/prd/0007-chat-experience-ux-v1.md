# PRD-0007. Chat Experience UX V1

**Status:** Draft
**Date:** 2026-04-25
**Owner:** Joshua Sumskas
**Related ADRs:** TBD
**Related Plans:** [Live Provider Test And Chat UX Slice](../plans/0002-live-provider-test-and-ux-slice.md)

---

## Summary

Refine the chat experience after baseline functionality is working, focusing on visual hierarchy, interaction polish, accessibility, keyboard behavior, scrolling, loading/error states, and overall usability.

## Problem

Baseline features prioritize functionality. That is appropriate early, but the app will eventually need a deliberate chat experience rather than an accumulation of minimal controls and incidental layouts.

## Users And Jobs

| User | Job To Be Done | Current Pain | Usage Context |
| --- | --- | --- | --- |
| Early user | Use chat comfortably for longer sessions | Baseline UI may be functional but unpolished | Daily prototype usage |
| App builder | Identify UX issues separately from runtime work | UX concerns get mixed into functional PRDs | Product refinement |

## Product Outcome

The chat screen feels like a coherent native macOS experience suitable for longer use, without changing the underlying runtime capabilities.

## Success Metrics

| Metric | Baseline | Target | Measurement Method |
| --- | --- | --- | --- |
| Chat readability | Functional layout | Transcript is easy to scan | Manual UX review |
| Interaction polish | Basic controls | Keyboard, send, scroll, and loading states feel intentional | Manual validation |
| UX debt reduction | Issues tracked ad hoc | Known chat UX issues are resolved or intentionally deferred | Review checklist |

## Scope Boundaries

### In Scope

- Chat transcript visual hierarchy.
- Input area behavior and affordances.
- Keyboard behavior.
- Auto-scroll and scroll anchoring behavior.
- Loading, streaming, error, and empty states.
- Basic accessibility review.

### Out Of Scope

- New runtime features.
- Live provider support.
- Persistence.
- Run inspector.
- Multi-agent workflow UI.
- Full design system.

### Deferred

- Global app theme.
- Advanced typography and visual identity.
- Sidebar/operator layout.
- Workflow visualization.

## User Experience

### Primary Flow

1. User opens a chat.
2. User sends and receives multiple messages.
3. App keeps the latest relevant content visible.
4. User can understand loading, streaming, error, and completion states.
5. User can continue the chat comfortably.

### Edge And Failure States

- Long transcripts remain usable.
- Streaming state is visible.
- Errors are noticeable without being overwhelming.
- Keyboard behavior is predictable.
- Empty state guides the user.

## Functional Requirements

- **FR-1:** The chat transcript must be readable for multi-turn conversations.
- **FR-2:** Input behavior must support efficient keyboard-driven use.
- **FR-3:** The latest turn must remain visible during normal send/receive flow.
- **FR-4:** Loading, streaming, completed, and error states must be visually distinct.
- **FR-5:** The chat screen must meet basic accessibility expectations.

## Acceptance Criteria

- **AC-1.1** (`FR-1`): Given a multi-turn chat, when the user scans the transcript, then user and assistant messages are visually distinct.
- **AC-2.1** (`FR-2`): Given the input is focused, when the user presses Return, then the expected send behavior occurs.
- **AC-3.1** (`FR-3`): Given a new message or response appears, then the latest turn remains visible unless the user intentionally scrolls away.
- **AC-4.1** (`FR-4`): Given a turn is running, then the UI shows that the assistant is still responding.
- **AC-4.2** (`FR-4`): Given a turn fails, then the error state is visible and understandable.
- **AC-5.1** (`FR-5`): Given basic accessibility review, then controls have usable labels and focus behavior.

## Dependencies

- Baseline chat functionality.
- Physical UX validation notes from previous PRDs.
- Agreement that this PRD is a design/refinement pass, not a runtime feature pass.

## Product Risks

- UX refactor could accidentally introduce runtime behavior changes.
- Work could grow into full design system or app navigation.
- Polishing too early could slow core harness progress.

## Technical Design Gate

| Field | Value |
| --- | --- |
| Separate technical design required? | Yes |
| Rationale | UX refactor affects view structure, state rendering, accessibility, and manual validation flow. |
| Plan link | [Live Provider Test And Chat UX Slice](../plans/0002-live-provider-test-and-ux-slice.md) |
| Blocks implementation until resolved? | Yes |
| Owner | Joshua Sumskas |

### Product Constraints For Technical Design

- Do not change runtime behavior except where needed to expose UI state.
- Preserve existing chat acceptance criteria.
- Keep the refactor focused on the chat screen.

## Milestones

| Milestone | Outcome | Included FRs | Excluded Scope | Exit Criteria | Dependencies |
| --- | --- | --- | --- | --- | --- |
| M1 | UX audit completed | FR-1 through FR-5 | Implementation | UX issues are listed and prioritized | Baseline chat |
| M2 | Interaction polish complete | FR-2, FR-3, FR-4 | Visual redesign | Keyboard, scroll, loading/error states pass manual validation | M1 |
| M3 | Visual readability pass complete | FR-1, FR-5 | Full design system | Transcript is readable and accessible enough for longer use | M2 |

## Validation Plan

### Pre-Implementation Validation

- Gather current UX issues from physical usage.
- Decide what is fixed now versus deferred.

### Implementation Validation

- Manually complete multi-turn chat.
- Validate keyboard-only send flow.
- Validate scrolling with longer transcripts.
- Validate error state rendering.

### Ship Criteria

- Chat is comfortable for longer prototype use.
- Known high-friction chat UX issues are resolved or explicitly deferred.
- No runtime capability scope is added.

## Open Questions

| Question | Owner | Blocks Implementation? | Resolve In PRD/ADR/Plan | Resolution |
| --- | --- | --- | --- | --- |
| Should UX V1 introduce a small theme package or remain local to chat? | Joshua Sumskas | Yes | PRD/Plan | Remain local to `ChatFeature` for this slice. |
| What level of visual identity is appropriate before broader app navigation exists? | Joshua Sumskas | No | PRD/Plan | Polished native chat hierarchy only; defer broader app identity. |

---

## Notes

This PRD intentionally comes after baseline functional slices. It formalizes the later UX refactor rather than blocking early feature delivery on design polish.

**Last Updated:** 2026-04-25
