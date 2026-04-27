# Chat Selection And Provider Validation Fixes

**Status:** Implemented
**Date:** 2026-04-27
**Related PRDs:** [PRD-0003](../prd/0003-provider-configuration-ux.md), [PRD-0004](../prd/0004-persistent-chats-and-runs.md), [PRD-0007](../prd/0007-chat-experience-ux-v1.md)

## Scope

Fix three usability and provider-compatibility issues found during manual app usage:

1. Chat history rows should be selectable across the whole row, not only over visible text.
2. Selecting the already active chat should be a no-op.
3. Provider settings validation should accept an OpenAI-compatible local endpoint at `http://127.0.0.1:8000/v1` with any API key and model `gpt-5.4`.

## Findings

### History Row Hit Target

The history row label did not reliably define the full visual row as the hit target. This made whitespace inside non-selected rows feel inactive.

Fix:

- Keep the row full width.
- Apply an explicit rounded `contentShape` to the visual row.
- Keep the selected and unselected row shape consistent.

Validation:

- Manual QA should confirm clicking the row background opens the chat.
- Existing UI should still identify the selected row visually.

### Active Chat Reopen

Opening the currently selected session re-ran the load-session path. That reset local UI state and could briefly show loading behavior even though the user had not changed chats.

Fix:

- Ignore selected-row clicks in the sidebar.
- Add an interactor-level guard so programmatic chat selection of the current ID is also a no-op.
- Preserve initial route loading with an explicit forced load during startup.

Validation:

- Unit test proves the current session does not call `loadSession`.
- Manual QA should confirm re-clicking the active chat leaves the transcript, draft, and loading state unchanged.

### Provider Settings Validation

Validation used the streaming chat-completions path. That is stricter than needed for settings validation and can fail against otherwise compatible providers that support normal JSON chat-completions responses.

Fix:

- Send provider validation as `stream: false`.
- Use `Accept: application/json` for non-streaming requests.
- Parse normal chat-completions JSON responses using `choices[].message.content`.
- Keep live chat streaming behavior unchanged.

Validation:

- Unit tests cover non-streaming parsing, provider validation request shape, and local-style settings for `http://127.0.0.1:8000/v1`, API key `anything`, and model `gpt-5.4`.
- Manual endpoint checks should verify both `/models` and `/chat/completions` return HTTP 200.
