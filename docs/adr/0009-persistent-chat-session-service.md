# 0009. Persistent Chat Session Service And UI Subscription Boundary

**Status:** Accepted
**Date:** 2026-04-27
**Deciders:** Joshua Sumskas, Codex
**Technical Story:** Move durable chat execution and transcript projection out of `ChatPageInteractor` while preserving the SwiftUI page/interactor lifecycle boundary.

---

## Context

ADR-0004 defines interactors as page-lifecycle adapters. The chat page has grown past that boundary: it starts runtime streams, consumes runtime events, mutates the visible transcript, tracks running/error state, and refreshes sidebar summaries.

Persistent chat behavior needs a service that can keep running after the page disappears or after the user switches chats. The page interactor should attach to a selected chat service, render its latest snapshot, and detach without cancelling domain work.

## Decision

Hephaestus will introduce a chat feature-lifetime `ChatWorkspaceService` that owns selected chat state, sidebar summaries, selected-service attachment, and workspace snapshot publication. The workspace service privately uses a `ChatSessionServiceRegistry` to create and reuse per-session `ChatSessionService` instances. Each session service is keyed by the persisted session ID, which is also the runtime run ID for persistent chats.

Per-chat services will be `@MainActor` reference types for this slice. They own snapshot publication, direct `streamUserMessage(runID:text:)` consumption, transcript projection, in-flight turn state, and explicit cancellation of their active send task.

The page interactor will:

- subscribe to the workspace/page projection,
- detach from the previous service when the selected chat changes or the page disappears,
- forward user intents such as send, select chat, new chat, and cancel to `ChatWorkspaceService`, and
- keep provider settings and inspector state page-local for now.

The workspace service will:

- own selected chat authority and selected service attachment,
- subscribe to the selected service snapshot,
- publish sidebar summary state through the workspace snapshot,
- publish selected-chat attachment errors separately from sidebar summary state,
- refresh summaries after session creation or service-reported chat changes, and
- keep the registry as a workspace-private cache/factory dependency.

The registry will:

- create services from persisted sessions or newly created sessions,
- retain services for the app lifetime in this slice, and
- avoid becoming a page interactor or route-builder dependency.

## Consequences

Page disappearance is not user cancellation. `onDisappear` cancels page subscriptions and page-scoped work only. `ChatWorkspaceService` remains attached to the selected `ChatSessionService`, and a running service continues consuming its runtime stream until it completes, fails, or receives an explicit cancel command.

The service consumes the direct command stream returned by `StreamUserMessageUseCase`. The runtime event hub remains available for lower-level observation, but the page no longer consumes runtime event streams directly.

Eviction is intentionally deferred. Services are retained for the app lifetime until there is a concrete memory or lifecycle pressure that justifies an eviction policy.

Persisted session reload is service creation behavior. If the workspace asks the registry for a session ID that is not cached, the registry loads the persisted session through `LoadSessionUseCase` and seeds the service snapshot from stored messages.

## Validation

This decision is correct if:

- a chat response can finish with no page interactor attached,
- switching chats does not leak runtime events into the newly selected transcript,
- page disappearance detaches snapshot subscriptions without cancelling the active turn,
- explicit cancel stops the selected service's active turn state, and
- selecting a chat does not force the sidebar into a full-list loading state.

## Related Documents

- [0004. SwiftUI Interactor Page Architecture](./0004-swiftui-interactor-page-architecture.md)
- [Chat Log Runtime Architecture Map](../plans/0005-chat-log-runtime-architecture-map.md)
- [Chat Session Service Refactor Plan](../plans/0006-chat-session-service-refactor-plan.md)
