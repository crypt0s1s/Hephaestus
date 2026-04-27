# Live Provider Test And Chat UX Slice

**Status:** Accepted for implementation
**Date:** 2026-04-25
**Owner:** Codex as product owner
**Related PRDs:** [PRD-0002](../prd/0002-live-openai-compatible-chat.md), [PRD-0007](../prd/0007-chat-experience-ux-v1.md)
**Related ADRs:** [ADR-0002](../adr/0002-swift-kernel-baseline.md), [ADR-0006](../adr/0006-package-boundaries-and-cross-package-deep-links.md), [ADR-0007](../adr/0007-headless-runtime-entrypoint.md)

## Product Slice

Today should make the app more trustworthy and more pleasant without turning provider setup into a full settings product.

The slice has three outcomes:

1. A detailed automated test suite around the runtime, chat interactor, provider failure paths, and OpenAI-compatible request/stream parsing.
2. A more deliberate native chat UI with clearer transcript hierarchy, empty/running/error states, and accessibility identifiers.
3. An environment-configured OpenAI-compatible provider path that can be pointed at OpenAI or another compatible endpoint for tomorrow's real-server validation.

## Decisions

- Keep mock mode as the default when no live provider mode is requested.
- Use environment variables for the first live provider path:
  - `HEPHAESTUS_PROVIDER=mock|openai-compatible`
  - `HEPHAESTUS_OPENAI_BASE_URL`, defaulting to `https://api.openai.com/v1`
  - `HEPHAESTUS_OPENAI_API_KEY`
  - `HEPHAESTUS_OPENAI_MODEL`, defaulting to `gpt-4.1-mini`
- Build the live adapter behind the existing `ProviderClient` protocol. No new ADR is needed for this slice because ADR-0002 and ADR-0007 already establish the provider boundary and headless runtime entrypoint.
- Use the OpenAI-compatible `POST /chat/completions` streaming shape for the first adapter. The adapter should parse `text/event-stream` `data:` lines and extract `choices[].delta.content`.
- Keep credentials out of source and out of persisted app state.
- Make provider errors visible through the existing runtime failure path; do not silently fall back to mock after live mode is selected.

## Implementation Areas

### Provider And Composition

- Add an OpenAI-compatible provider client under `Core/HephaestusLLM`.
- Add provider configuration parsing under `Core/HephaestusComposition`.
- Compose either mock or live runtime from the app shell and CLI without changing `ChatFeature`.
- Keep the provider transport injectable so tests can run without network access.

### Test Suite

- Add tests for provider configuration defaults and validation.
- Add tests for request construction, authorization header use, base URL joining, model selection, and streaming SSE parsing.
- Add tests for invalid credentials or provider failures flowing to `turnFailed`.
- Expand chat interactor tests for progressive streaming, error recovery, run reuse, and loading-state transitions.
- Keep UI tests focused on launch and basic chat affordances only; real-server E2E is explicitly deferred.

### Chat UI

- Refine `ChatPage` with a clearer header, transcript area, message bubbles, empty state, status indicator, error banner, and polished composer.
- Preserve existing state/action contracts unless a small field is needed to render accepted state cleanly.
- Add accessibility labels/identifiers for the transcript, message input, send button, running state, and error banner.
- Keep the UI local to `ChatFeature`; do not introduce a theme package yet.

## Validation

Run:

```sh
swift test -Xswiftc -strict-concurrency=complete -Xswiftc -warnings-as-errors
swift run HephaestusCLI "hello" "second"
xcodebuild -workspace Hephaestus.xcworkspace -scheme Hephaestus -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO build
```

Manual checks:

- Launch the app in mock mode and send at least two messages.
- Launch with `HEPHAESTUS_PROVIDER=openai-compatible` but no API key and confirm the provider error is visible and recoverable.
- Tomorrow, run with a real endpoint and API key to validate live streaming.

## Non-Goals

- Provider settings UI.
- Credential persistence or keychain storage.
- Model picker.
- Real-server E2E validation today.
- Persistence of runs or transcripts.

## Open Follow-Ups

- PRD-0003 should own persistent provider configuration UX.
- A future ADR may be needed when choosing secure credential storage or multi-provider profile ownership.
- Real-server E2E should become a separate workflow once a live endpoint and credentials are available.
