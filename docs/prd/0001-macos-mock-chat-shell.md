# PRD-0001. macOS Mock Chat Shell

**Status:** Draft
**Date:** 2026-04-25
**Owner:** Joshua Sumskas
**Related ADRs:** [ADR-0003](../adr/0003-initial-agent-kernel-poc.md), [ADR-0007](../adr/0007-headless-runtime-entrypoint.md)
**Related Plans:** [macOS App Shell Chat POC Plan](../plans/macos-app-shell-chat-poc.md)

---

## Summary

Build the first real native macOS screen for Hephaestus: a simple chat interface backed by the mock agent runtime. The user should be able to launch the app, type a message, see a streamed mock assistant response render in the UI, then send a second message that proves the runtime preserves prior conversation context.

## Problem

The project has a working early agent runtime outside the native app, but the actual macOS app still shows the default template. We need a visible product loop in the app so we can validate the first chat experience before adding live provider integration.

### Background

This is the first product-facing slice after the agent kernel skeleton. It should validate the app composition path before adding a live OpenAI-compatible provider, persistence, context compaction, skills, or multi-agent workflows.

### Users And Jobs

| User | Job To Be Done | Current Pain | Usage Context |
| --- | --- | --- | --- |
| App builder | Verify the native app can host the first chat loop | The runtime is not visible in the real app target | Local development while building the first macOS harness |
| Future Hephaestus user | Send a message and receive an assistant response in a native app | No visible chat surface exists yet | Early prototype usage and manual validation |

## Product Outcome

The native macOS app opens directly into a working mock chat screen. The screen proves the basic product loop: enter message, send, stream assistant response, send another message, and preserve context between turns.

### Success Metrics

| Metric | Baseline | Target | Measurement Method |
| --- | --- | --- | --- |
| Native app chat availability | App shows default template | App launches into chat screen | Manual app launch |
| First-turn mock streaming | No app UI path | User sees streamed assistant text after sending a message | Manual validation |
| Second-turn context retention | Not visible in app | Second response reflects prior conversation context | Manual validation with mock output |

## Scope Boundaries

### In Scope

- Replace the default app template with a focused Hephaestus chat experience.
- Use the existing mock agent runtime rather than a live provider.
- Show a simple chat UI with draft entry, send button, mock streaming output, and basic error display.
- Support at least two consecutive messages in the same run.

### Out Of Scope

- Live OpenAI-compatible provider integration.
- API key entry or provider settings.
- Chat persistence.
- Context compaction controls.
- Skills.
- Multi-agent workflows.
- Polished visual design.
- Sidebar, route list, or full navigation design.

### Deferred

- Persistent chat history.
- Real provider configuration and model selection.
- Production-grade context management UI.
- More complete app navigation.
- Design system and theme package.

### Scope Creep Watchlist

- Adding live network calls before the mock app shell is stable.
- Adding persistence before the single in-memory run loop is proven.
- Designing multi-agent workflow UI before the single-agent chat loop works.
- Adding internal architecture shortcuts that prevent this screen from becoming the base for the real chat experience.

## User Experience

### Primary Flow

1. User launches the macOS app.
2. App opens to the chat screen.
3. User types a message.
4. User taps Send.
5. The user message appears in the transcript.
6. The assistant response streams into the transcript.
7. User sends a second message.
8. The second assistant response completes, using the prior turn as context.

### Edge And Failure States

- Empty draft cannot be sent.
- Send is disabled while a message is running.
- Runtime errors render as visible error text.
- Cancellation should not leave a permanently streaming assistant bubble.
- App startup failures should render an explicit error rather than a blank window.

## Functional Requirements

- **FR-1:** The macOS app must launch into a Hephaestus chat experience instead of the default template.
- **FR-2:** The chat experience must use the mock agent runtime.
- **FR-3:** The chat screen must allow the user to send a non-empty message and see the user message in the transcript.
- **FR-4:** The chat screen must show assistant text progressively and mark the assistant response complete.
- **FR-5:** The chat screen must support at least two messages in the same run so prior context is included.

## Acceptance Criteria

- **AC-1.1** (`FR-1`): Given the app launches, when the main window appears, then it shows the chat experience rather than the template item list.
- **AC-2.1** (`FR-2`): Given the user sends a message, when the assistant responds, then the response comes from the mock runtime and does not require network configuration.
- **AC-3.1** (`FR-3`): Given a non-empty draft, when the user taps Send, then the draft clears and the user message appears in the transcript.
- **AC-3.2** (`FR-3`): Given an empty or whitespace-only draft, when the user views the send control, then sending is unavailable.
- **AC-4.1** (`FR-4`): Given a message is sent, when the assistant response is generated, then assistant text appears progressively in the transcript.
- **AC-4.2** (`FR-4`): Given the assistant response completes, then the streaming indicator is removed and the send control becomes available again.
- **AC-5.1** (`FR-5`): Given a completed first turn, when the user sends a second message, then the second assistant response reflects prior conversation context.

## Dependencies

- Existing mock runtime.
- Existing native macOS app target.
- Technical implementation plan for app-shell wiring.

## Product Risks

- App-target wiring could slow implementation.
- If this becomes a throwaway prototype, it will not reduce risk for the real chat experience.
- If the UI grows beyond the minimal chat loop, this PRD could absorb work better left to later PRDs.
- If the screen depends too strongly on mock-only behavior, live provider wiring may be harder later.

## Technical Design Gate

PRDs define product need and product constraints. ADRs record durable architectural choices. Technical designs or implementation plans in `docs/plans/` describe how an accepted PRD will be built.

| Field | Value |
| --- | --- |
| Separate technical design required? | Yes |
| Rationale | This requires app-target wiring and implementation choices that should stay out of the PRD. |
| Plan link | [macOS App Shell Chat POC Plan](../plans/macos-app-shell-chat-poc.md) |
| Blocks implementation until resolved? | Yes |
| Owner | Joshua Sumskas |

### Product Constraints For Technical Design

- The visible screen must not be a throwaway prototype.
- The mock runtime must remain replaceable so live providers can be added later.
- The implementation must not introduce persistence or network setup into this slice.

### Open Technical Questions

- What technical structure best keeps this screen reusable for the live-provider phase?

## Milestones

| Milestone | Outcome | Included FRs | Excluded Scope | Exit Criteria | Dependencies |
| --- | --- | --- | --- | --- | --- |
| M1 | App opens to a non-template chat experience | FR-1, FR-2 | Streaming polish, persistence, live provider | Main window renders chat UI without template UI | Existing mock runtime |
| M2 | User can complete one mock chat turn | FR-3, FR-4 | Persistence, live provider, skills | User sends one message and sees a completed mock assistant response | M1 |
| M3 | User can complete two contextual mock turns | FR-5 | Live provider, persistence, skills | User sends two messages and sees the second response reflect prior context | M2 |

## Validation Plan

### Pre-Implementation Validation

- Review this PRD and the linked implementation plan.
- Confirm the app target should use mock runtime composition only.

### Implementation Validation

- Manually launch the app and send two messages.

### Ship Criteria

- App opens to chat screen.
- User can send two messages in one run.
- Mock assistant streams and completes responses.
- No placeholder template UI remains visible.

## Open Questions

| Question | Owner | Blocks Implementation? | Resolve In PRD/ADR/Plan | Resolution |
| --- | --- | --- | --- | --- |
| Does the first screen need any product-visible navigation beyond chat? | Joshua Sumskas | No | PRD | No for this PRD; navigation is deferred. |

---

## Notes

This PRD intentionally stops before live provider integration. The next product PRD should cover OpenAI-compatible provider configuration and live streaming once the mock app shell is validated.

**Last Updated:** 2026-04-25
