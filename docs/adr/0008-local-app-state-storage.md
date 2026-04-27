# 0008. Local App State Storage

**Status:** Accepted
**Date:** 2026-04-26
**Deciders:** Joshua Sumskas, Codex
**Technical Story:** Choose the first durable storage boundary for provider configuration, chat history, context traces, and run inspection data.

---

## Context

PRD-0003 through PRD-0006 move Hephaestus from a mock/live chat surface into a competent single-agent harness. The app now needs durable local state for:

- provider configuration
- chat sessions and messages
- runtime event timelines
- provider request summaries
- context assembly traces

The project is still early. The storage shape must be useful enough for product validation without locking Hephaestus into a final database or account model.

## Decision Drivers

- Keep the first implementation local-first and easy to inspect.
- Avoid SwiftUI or app-target dependencies in runtime packages.
- Preserve a path to SwiftData, SQLite, or a backend later.
- Make persistence failures explicit in the UI.
- Avoid displaying API keys casually after entry.

## Considered Options

### Option 1: File-Backed JSON Store Behind Protocols

Store app state in an application-support JSON file and expose it through small async store protocols.

**Pros:**
- Fast to implement and test.
- Easy to inspect during development.
- Works from SwiftPM tests without app lifecycle.
- Keeps storage behind replaceable protocols.
- Supports all current PRD data with one migration version.

**Cons:**
- Not ideal for large histories.
- Requires whole-file write discipline.
- API keys are not as protected as Keychain storage.

### Option 2: SwiftData First

Use SwiftData models for sessions, messages, settings, and event records.

**Pros:**
- Native Apple persistence stack.
- Better querying and migration story than a flat file.
- Natural app integration.

**Cons:**
- Pulls storage closer to app lifecycle early.
- Adds model-container setup before the data model has stabilized.
- Harder to exercise from current SwiftPM runtime tests.

### Option 3: Keychain Plus Database First

Store API keys in Keychain and non-secret state in a local database.

**Pros:**
- Stronger credential posture.
- Better long-term separation of secrets and durable app data.

**Cons:**
- More moving parts before provider UX is proven.
- Requires test doubles and platform-specific setup.
- Premature before provider profiles and auth flows are designed.

## Decision

Hephaestus will use a file-backed JSON app-state store for v1 provider configuration, chat history, event timelines, provider summaries, and context traces. The store is accessed only through protocols exposed from the runtime/application layer.

**Chosen Option:** Option 1 - File-Backed JSON Store Behind Protocols

Provider API keys may be stored in this v1 file-backed state, but the UI must treat them as write-only after entry:

- never show the saved key value
- show only whether a key is saved
- allow replacement or clearing
- keep the storage boundary replaceable so Keychain can become a later ADR-backed change

This is acceptable for the prototype harness because the product is local-first and developer-facing today. Before broader distribution, credentials should move to Keychain or another OS-backed secret store.

## Consequences

### Positive

- PRD-0003 through PRD-0006 can share one durable state boundary.
- Tests can use temporary files or in-memory stores.
- Runtime, UI, and app composition can be wired without SwiftData.
- Future storage migration has a single protocol seam.

### Negative

- Local JSON is not a strong secret storage solution.
- Large histories will eventually need a more queryable store.
- Whole-file persistence must be implemented carefully enough to avoid obvious data loss.

### Neutral

- The first settings UI is a modal in the chat shell.
- The first history UI is a compact sidebar, not a full run browser.
- Context details live inside the run inspector for v1.

## Implementation Notes

- Keep app-state models `Codable` and versioned.
- Write atomically by encoding to a temporary file and replacing the destination.
- Surface load/save failures through explicit UI error state.
- Keep all runtime storage protocols UI-free.
- Preserve environment variables as development overrides for live provider validation.

## Follow-Ups

- Revisit Keychain-backed provider secrets before broad release.
- Revisit SwiftData or SQLite when history search, filtering, or richer run inspection requires querying.
- Add export/import only after the durable app-state model stabilizes.
