# Complete Single-Agent Harness PRDs

**Status:** Accepted for implementation
**Date:** 2026-04-26
**Owner:** Codex as product owner
**Related PRDs:** [PRD-0003](../prd/0003-provider-configuration-ux.md), [PRD-0004](../prd/0004-persistent-chats-and-runs.md), [PRD-0005](../prd/0005-context-management-v1.md), [PRD-0006](../prd/0006-run-inspection.md)
**Related ADRs:** [ADR-0002](../adr/0002-swift-kernel-baseline.md), [ADR-0007](../adr/0007-headless-runtime-entrypoint.md), [ADR-0008](../adr/0008-local-app-state-storage.md)

## Product Slice

Implement the remaining PRDs as one coherent single-agent harness slice:

1. Provider configuration UX.
2. Persistent chats and runs.
3. Context management visibility.
4. Run inspection.

PRD-0001, PRD-0002, and PRD-0007 are already represented in the current app shell, live-provider path, and chat polish. This plan completes the missing product surfaces that make the harness useful across restarts and debuggable during live-provider testing.

## Decisions

- Use the file-backed JSON app-state store from ADR-0008.
- Keep the first provider settings surface as a modal opened from the chat shell.
- Keep the first history surface as a compact sidebar in the chat screen.
- Keep context details inside the run inspector rather than creating a separate route.
- Persist event summaries, provider request summaries, messages, turns, and context traces as inspectable records.
- Store enough provider configuration to power live chat from saved settings while preserving environment variables as development overrides.
- Do not add multiple provider profiles, search, export, replay, tool inspection, or workflow visualization.

## Runtime And Storage

Add runtime/application protocols and use cases for:

- loading/saving provider settings
- validating provider settings through the existing OpenAI-compatible adapter
- listing persisted sessions
- loading a session with messages and inspection records
- creating a new session
- appending runtime events and provider/context summaries during turns

The persisted data model should include:

- `PersistedSession`
- `PersistedMessage`
- `PersistedTurn`
- `PersistedRuntimeEvent`
- `PersistedProviderRequestSummary`
- `PersistedContextTrace`
- `PersistedProviderSettings`

The first store may be whole-file JSON with atomic writes. Tests should use a temporary-file store or in-memory store.

## UI

Update `ChatFeature` so the first screen contains:

- chat history sidebar
- new chat action
- provider settings action
- run inspector action for the active run
- transcript and composer from the existing chat page
- provider settings modal with base URL, API key replacement, model, validation state, save, clear, and cancel
- run inspector panel or modal showing timeline, messages, turns, provider summaries, errors, and context traces

The provider settings UI must:

- show endpoint and model fields
- not display an existing saved API key value
- allow replacing or clearing the API key
- validate and show success/failure without restarting the app
- save valid settings for new live chats

The history UI must:

- show an empty state when no sessions exist
- show previous chats after restart
- open a persisted chat
- continue the opened chat with prior messages visible

The inspector must:

- show an ordered runtime timeline
- show turn status and messages
- show provider model/message count summaries where available
- show context policy and included/excluded message summaries
- show explicit unavailable states for missing provider/context details

## Validation

Run:

```sh
swift test -Xswiftc -strict-concurrency=complete -Xswiftc -warnings-as-errors
swift run HephaestusCLI "hello" "second"
xcodebuild -project Hephaestus.xcodeproj -scheme Hephaestus -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO build
```

Add automated tests for:

- provider settings load/save/redaction semantics
- provider validation success and failure through injectable transport
- persisted session survives store reload
- reopened session continues with prior context
- context trace included/excluded behavior with a small message limit
- run inspector data contains ordered event, provider, error, and context summaries
- chat interactor loads history, opens sessions, starts new chats, and surfaces persistence errors

Manual checks:

- launch app with empty store
- create and continue a chat
- relaunch and reopen the chat
- edit and validate provider settings
- inspect successful and failed turns
- inspect context details for a short chat and a chat with excluded messages

## Non-Goals

- Keychain-backed secrets.
- Multiple provider profiles.
- Model picker or provider metadata browser.
- Search/export/replay.
- Tool execution inspection.
- Multi-agent workflow UI.

## Risks

- This is a wide product slice. Keep UI simple and test the application state rather than over-polishing navigation.
- File-backed storage is intentionally replaceable and should not leak into UI packages.
- Real-server E2E remains a separate validation step once credentials and endpoint are available.
