# Hephaestus Observability Objectives

## Purpose

This document captures the high-level observability direction for Hephaestus. It incorporates ideas from the Codex observer brainstorm, but reframes them as product goals for Hephaestus rather than as a separate observer app.

Observability is not the first implementation priority. The near-term priority remains proving the runtime and making the single-agent harness useful. However, observability should be baked into the shape of the system as it grows, so later inspection, replay, debugging, and backend comparison do not require a second execution model.

## Product Objective

Hephaestus should make agent execution understandable.

A user should be able to answer:

- What is running right now?
- Which backend is running it?
- What did the agent see?
- What tools or commands did it use?
- What approvals or permissions blocked progress?
- What changed in the workspace?
- Where did a run fail, stall, or recover?
- How did different harness backends behave for similar work?

The product should treat observable execution as a core property of the harness, not as a logging afterthought.

## Naming And Scope

Hephaestus is the meta-harness and operator environment.

Foundry is the native in-process Swift agent harness/runtime.

Anvil is the UI framework.

Codex CLI, Claude Code, and Foundry should be treated as harness backends. Observability should sit above those backends and normalize their activity into shared run, event, tool, permission, and artifact concepts.

```text
Hephaestus
  Anvil UI
  Harness backend adapters
    Foundry
    Codex CLI
    Claude Code
  Observation and inspection layer
```

## Core Goals

### 1. Normalize Runs Across Backends

Hephaestus should expose a common event model for different harness backends.

The raw details of Codex hooks, Claude Code output, and Foundry runtime events will differ. The app should preserve those raw details where useful, but the user-facing model should normalize them into stable concepts:

- session
- run
- turn
- agent
- message
- tool call
- approval request
- file change
- error
- final result

This keeps the app from becoming a set of unrelated viewers for each backend.

### 2. Capture First, Interpret Second

The system should prefer durable event capture before deep interpretation.

Early versions should store enough raw or lightly normalized event data to support later replay, debugging, schema evolution, and better reducers. Derived views can improve over time once real backend payloads are understood.

This is especially important for external backends like Codex CLI and Claude Code, where event shape may change or may need inference.

### 3. Keep Observation Passive By Default

Observation should not interfere with agent work.

The default mode should record events, update state, and surface useful information without blocking the run. If an observer endpoint, hook, or parser fails, the run should continue whenever possible.

Policy enforcement and guardrails are valuable later, but they should be explicit features rather than hidden side effects of observation.

### 4. Make Runs Inspectable While They Happen

Hephaestus should support live inspection as a product capability.

The user should be able to watch a run progress through a readable timeline:

- prompt submitted
- model response started
- tool call requested
- permission requested
- tool completed
- file changed
- error occurred
- run completed

Live state should eventually answer both "what is happening now?" and "what just happened?"

### 5. Preserve Raw Evidence For Debugging

When safe, Hephaestus should retain raw backend payloads next to normalized events.

Raw evidence is useful for:

- debugging adapter bugs
- validating event reducers
- replaying sessions
- comparing backends
- evolving schemas without losing old data

Raw payload storage should be controlled by configuration and redaction rules. Local development can be more permissive; shared or remote workflows should be more conservative.

### 6. Redact Before Long-Term Storage

Observation will see sensitive data.

Prompts, shell commands, tool outputs, environment variables, file paths, API keys, tokens, and private source code may appear in event streams. Hephaestus should include a redaction layer before data becomes durable or shareable.

At minimum, the design should account for:

- bearer tokens
- API keys
- passwords and secrets
- private key material
- `.env` contents
- user-configured redaction patterns
- a setting for whether raw payloads are stored

### 7. Treat Inspection As A First-Class UX

Run inspection should become more than logs.

The app should eventually provide:

- session dashboard
- run timeline
- tool usage panel
- approval and permission history
- selected event detail
- raw payload view
- context package view
- provider or backend request summary
- failure and retry highlights

The UI should be readable without requiring the user to know the implementation internals.

### 8. Support Replay And Comparison Later

The observability model should leave room for:

- replaying a run timeline without re-running the agent
- exporting a run as Markdown or JSON
- comparing Codex CLI, Claude Code, and Foundry behavior
- identifying repeated failures or tool loops
- measuring tool usage and permission friction

These are not v1 requirements, but the event model should not make them impossible.

## Non-Goals

- Do not build a standalone Codex observer as the primary product direction.
- Do not prioritize a browser dashboard over the native Hephaestus app.
- Do not make guardrail enforcement part of the first observation slice.
- Do not require every backend to support every observable feature equally.
- Do not over-model agent identity before backend payloads prove what identifiers are available.
- Do not store sensitive raw payloads without clear local-only assumptions and redaction controls.

## Backend Adapter Expectations

Each harness backend adapter should declare what it can observe.

Examples:

- supports live events
- supports tool call events
- supports approval events
- supports file change summaries
- supports structured final output
- supports resume or session IDs
- supports raw payload capture

Unsupported capabilities should be explicit so the UI can show "unavailable" instead of silently hiding missing data.

## Event Model Direction

The initial normalized event model should be small and extensible:

```text
HarnessEvent
  runStarted
  turnStarted
  messageAppended
  assistantDelta
  toolCallStarted
  toolCallCompleted
  approvalRequested
  approvalResolved
  fileChanged
  error
  runCompleted
```

Each event should include:

- stable event ID
- timestamp
- backend ID
- session or run ID when available
- turn ID when available
- related tool call ID when available
- normalized summary fields
- optional raw payload reference

The app should derive current state from events rather than treating UI state as the source of truth.

## Milestone Direction

### Near Term

- Keep Foundry runtime events structured.
- Continue building persistent run inspection.
- Preserve provider request summaries and context traces.
- Define backend adapter capabilities before adding external backends.

### Middle Term

- Add Codex CLI as a harness backend.
- Capture Codex JSON output or hook events where available.
- Normalize Codex activity into the shared event model.
- Show external backend runs in the same run inspector as Foundry runs.

### Later

- Add Claude Code as another harness backend.
- Add replay from stored events.
- Add backend comparison views.
- Add optional guardrail mode for policy enforcement.
- Add export for run evidence and debugging reports.

## Guiding Principle

Hephaestus should make agent systems feel observable by construction.

The first version can be narrow, but each runtime, backend, tool, and context feature should leave behind enough structured evidence for the user to understand what happened.
