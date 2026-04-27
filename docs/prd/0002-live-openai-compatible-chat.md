# PRD-0002. Live OpenAI-Compatible Chat

**Status:** Draft
**Date:** 2026-04-25
**Owner:** Joshua Sumskas
**Related ADRs:** [ADR-0002](../adr/0002-swift-kernel-baseline.md), [ADR-0007](../adr/0007-headless-runtime-entrypoint.md)
**Related Plans:** [Live Provider Test And Chat UX Slice](../plans/0002-live-provider-test-and-ux-slice.md)

---

## Summary

Allow the existing macOS chat screen to send messages to a real OpenAI-compatible endpoint instead of the mock runtime, while preserving the same basic chat experience already proven by PRD-0001.

## Problem

The app can prove the chat loop with a mock provider, but it cannot yet validate real model streaming, provider errors, authentication failures, or model selection. Without a live provider path, the product remains a local demo rather than a usable agent harness.

## Users And Jobs

| User | Job To Be Done | Current Pain | Usage Context |
| --- | --- | --- | --- |
| App builder | Verify the harness works with a real LLM backend | Mock responses do not expose real provider behavior | Local development and provider integration testing |
| Early user | Send a message to a real assistant from the native app | The app only returns deterministic mock text | Early manual usage |

## Product Outcome

The user can run a live chat turn from the native app using an OpenAI-compatible endpoint and receive streamed model output in the existing chat UI.

## Success Metrics

| Metric | Baseline | Target | Measurement Method |
| --- | --- | --- | --- |
| Live chat availability | Mock-only responses | One successful live streamed response | Manual validation |
| Error visibility | Live errors not represented | Missing/invalid credentials and network failures are visible | Manual forced-failure validation |
| Mock path preservation | Mock path works today | Mock/headless validation still works | Existing validation path |

## Scope Boundaries

### In Scope

- Send chat messages to one configured OpenAI-compatible endpoint.
- Stream live assistant output into the existing chat UI.
- Show user-visible errors for missing credentials, invalid endpoint/model, and provider failure.
- Preserve the mock runtime path for tests and local validation.

### Out Of Scope

- Full provider settings UI.
- Multiple provider profiles.
- Persistence of chats or provider responses.
- Tool calling.
- Context compaction.
- Multi-agent workflows.

### Deferred

- Native provider configuration UX.
- Secure credential storage.
- Provider capability detection.
- Model picker and model metadata.

## User Experience

### Primary Flow

1. User launches the app with a live provider configured.
2. User sends a message in the chat screen.
3. App streams the real assistant response.
4. User can send a second message in the same run.

### Edge And Failure States

- Missing credentials show a clear setup/configuration error.
- Invalid endpoint/model shows a provider error.
- Network failure leaves the user message visible and marks the turn failed.
- The UI does not silently fall back to mock responses unless explicitly configured to use mock mode.

## Functional Requirements

- **FR-1:** The app must support a live OpenAI-compatible provider mode.
- **FR-2:** The live provider mode must stream assistant text into the existing chat UI.
- **FR-3:** Provider failures must be visible to the user.
- **FR-4:** The mock provider path must remain available for tests and local validation.
- **FR-5:** The feature must not require a full provider settings UI to validate live chat.

## Acceptance Criteria

- **AC-1.1** (`FR-1`): Given valid live provider configuration, when the user sends a message, then the request is sent to the configured endpoint.
- **AC-2.1** (`FR-2`): Given a live response is streaming, when text arrives, then it appears progressively in the chat transcript.
- **AC-3.1** (`FR-3`): Given invalid credentials, when the user sends a message, then the app shows a visible provider error.
- **AC-3.2** (`FR-3`): Given a network or endpoint failure, when the request fails, then the app marks the turn failed and enables another send.
- **AC-4.1** (`FR-4`): Given mock mode is used, when the existing mock validation runs, then mock chat still works.

## Dependencies

- PRD-0001 mock chat shell.
- A usable OpenAI-compatible endpoint and credentials.
- Technical design for provider configuration source, auth handling, and streaming response mapping.

## Product Risks

- Provider setup could expand into full settings UX too early.
- Live provider failures could be confusing if error messages are too raw.
- Hardcoding credentials or endpoint details would make later configuration work harder.

## Technical Design Gate

| Field | Value |
| --- | --- |
| Separate technical design required? | Yes |
| Rationale | Live provider support requires networking, credential handling, streaming mapping, and provider/runtime composition choices. |
| Plan link | [Live Provider Test And Chat UX Slice](../plans/0002-live-provider-test-and-ux-slice.md) |
| Blocks implementation until resolved? | Yes |
| Owner | Joshua Sumskas |

### Product Constraints For Technical Design

- Live provider mode must not remove or break mock mode.
- Credentials must not be hardcoded in source.
- Provider errors must be user-visible.
- The first live path may use developer-supplied configuration before provider settings UX exists.

## Milestones

| Milestone | Outcome | Included FRs | Excluded Scope | Exit Criteria | Dependencies |
| --- | --- | --- | --- | --- | --- |
| M1 | Live provider can complete one turn | FR-1, FR-2 | Settings UI, persistence | User receives one live response | Endpoint credentials |
| M2 | Provider errors are visible | FR-3 | Full error taxonomy | Invalid config shows useful error | M1 |
| M3 | Mock and live modes coexist | FR-4, FR-5 | Provider profiles | Mock validation and live validation both work | M2 |

## Validation Plan

### Pre-Implementation Validation

- Confirm the initial source of live provider configuration.
- Confirm which OpenAI-compatible endpoint will be used for testing.

### Implementation Validation

- Send one live message.
- Send a second live message in the same run.
- Force invalid credentials and confirm visible error.
- Run existing mock validation.

### Ship Criteria

- Live message sends and streams successfully.
- Provider failure is visible and recoverable.
- Mock path still works.

## Open Questions

| Question | Owner | Blocks Implementation? | Resolve In PRD/ADR/Plan | Resolution |
| --- | --- | --- | --- | --- |
| What is the initial provider configuration source before settings UX exists? | Joshua Sumskas | Yes | Plan | Environment variables: `HEPHAESTUS_PROVIDER`, `HEPHAESTUS_OPENAI_BASE_URL`, `HEPHAESTUS_OPENAI_API_KEY`, and `HEPHAESTUS_OPENAI_MODEL`. |
| Which model should be the default for live validation? | Joshua Sumskas | Yes | Plan | `gpt-4.1-mini`, overrideable with `HEPHAESTUS_OPENAI_MODEL`. |

---

## Notes

This PRD intentionally avoids full provider configuration UX. That is handled by PRD-0003.

**Last Updated:** 2026-04-25
