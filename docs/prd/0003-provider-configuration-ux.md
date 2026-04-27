# PRD-0003. Provider Configuration UX

**Status:** Draft
**Date:** 2026-04-25
**Owner:** Joshua Sumskas
**Related ADRs:** [ADR-0008](../adr/0008-local-app-state-storage.md)
**Related Plans:** [Complete Single-Agent Harness PRDs](../plans/0003-complete-single-agent-harness-prds.md)

---

## Summary

Provide a simple native configuration surface for selecting and validating an OpenAI-compatible provider endpoint, API key, and model so live chat can be used without hardcoded or ad hoc local setup.

## Problem

Live chat needs repeatable provider configuration. Without a visible configuration path, users must rely on developer-only setup, which blocks real use and makes provider failures harder to understand.

## Users And Jobs

| User | Job To Be Done | Current Pain | Usage Context |
| --- | --- | --- | --- |
| App builder | Configure a live provider repeatedly while developing | Configuration is implicit or hardcoded | Local development |
| Early user | Enter endpoint credentials and know whether they work | No native setup or validation path exists | First-run setup |

## Product Outcome

The user can enter provider configuration, validate it, and use it for live chat without editing source code or relying on hidden setup.

## Success Metrics

| Metric | Baseline | Target | Measurement Method |
| --- | --- | --- | --- |
| Config visibility | No UI | Provider config is visible and editable | Manual validation |
| Validation feedback | Errors surface only during chat | User can test config before chat | Manual validation |
| Recovery from bad config | Unclear | User can correct invalid config and retry | Manual forced-failure validation |

## Scope Boundaries

### In Scope

- Enter/edit base URL, API key, and model.
- Validate provider configuration.
- Show clear success/failure state.
- Use saved configuration for live chat.

### Out Of Scope

- Multiple provider profiles.
- Organization/account switching.
- Model metadata browser.
- Advanced provider capability detection.
- Multi-user credential management.

### Deferred

- Secure sync across devices.
- Provider marketplace/presets.
- Advanced auth flows.

## User Experience

### Primary Flow

1. User opens provider configuration.
2. User enters endpoint, API key, and model.
3. User validates the configuration.
4. App shows success.
5. User returns to chat and uses the configured provider.

### Edge And Failure States

- Missing API key blocks validation.
- Invalid URL shows a clear field-level error.
- Provider rejection shows a visible error.
- User can edit and re-validate without restarting the app.

## Functional Requirements

- **FR-1:** The app must expose provider configuration in the native UI.
- **FR-2:** The user must be able to validate the configured provider.
- **FR-3:** The app must use valid saved configuration for live chat.
- **FR-4:** Invalid configuration must produce actionable feedback.

## Acceptance Criteria

- **AC-1.1** (`FR-1`): Given the user opens configuration, then endpoint, API key, and model fields are visible.
- **AC-2.1** (`FR-2`): Given valid configuration, when the user validates it, then the app shows success.
- **AC-2.2** (`FR-2`): Given invalid configuration, when the user validates it, then the app shows a visible error.
- **AC-3.1** (`FR-3`): Given saved valid configuration, when the user sends a live chat message, then the configured provider is used.
- **AC-4.1** (`FR-4`): Given a validation error, then the user can edit the config and retry.

## Dependencies

- PRD-0002 live provider support.
- Decision on local credential storage.
- Technical design for where configuration lives and how validation works.

## Product Risks

- Settings work could expand into a full provider management system too early.
- Credential handling can create trust issues if storage is unclear.
- Validation can be misleading if it only checks connectivity and not chat capability.

## Technical Design Gate

| Field | Value |
| --- | --- |
| Separate technical design required? | Yes |
| Rationale | Configuration touches credential storage, validation behavior, app settings UI, and live runtime composition. |
| Plan link | [Complete Single-Agent Harness PRDs](../plans/0003-complete-single-agent-harness-prds.md) |
| Blocks implementation until resolved? | Yes |
| Owner | Joshua Sumskas |

### Product Constraints For Technical Design

- API keys must not be displayed casually after entry.
- Invalid configuration must be recoverable in the UI.
- Configuration should not force a restart for normal changes.

## Milestones

| Milestone | Outcome | Included FRs | Excluded Scope | Exit Criteria | Dependencies |
| --- | --- | --- | --- | --- | --- |
| M1 | Config fields exist | FR-1 | Validation, persistence | User can enter config | UI shell |
| M2 | Config can be validated | FR-2, FR-4 | Provider profiles | Success and failure states are visible | M1 |
| M3 | Config powers live chat | FR-3 | Advanced provider management | Live chat uses saved config | PRD-0002 |

## Validation Plan

### Pre-Implementation Validation

- Decide credential storage approach.
- Decide whether settings is a modal, route, or app preferences surface.

### Implementation Validation

- Validate with correct config.
- Validate with bad API key.
- Validate with bad endpoint.
- Send live chat after saving config.

### Ship Criteria

- User can configure and validate a provider.
- Live chat can use saved config.
- Invalid config is clear and recoverable.

## Open Questions

| Question | Owner | Blocks Implementation? | Resolve In PRD/ADR/Plan | Resolution |
| --- | --- | --- | --- | --- |
| Should API keys be stored in Keychain from the first settings version? | Joshua Sumskas | Yes | ADR/Plan | No. ADR-0008 chooses file-backed local state for v1, with API keys hidden in UI and Keychain deferred. |
| Where should provider settings live in the UI? | Joshua Sumskas | Yes | Plan | Chat shell modal for v1. |

---

## Notes

This PRD should not become full provider management. It is the smallest native setup path for live chat.

**Last Updated:** 2026-04-25
