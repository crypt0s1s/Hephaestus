# Hephaestus Vision

## End Goal

Hephaestus is intended to become a native macOS environment for building, running, and inspecting agent systems.

The long-term target is not just a single-agent harness. It is an `agent harness harness`: a system that can define and execute multi-agent workflows on top of a reusable runtime kernel.

## Product Shape

At maturity, Hephaestus should provide:

- A native SwiftUI macOS application for operating and inspecting agent runs.
- A reusable `agent kernel` that owns the lifecycle of an agent turn.
- A messaging model that allows agents to communicate with each other in a structured way.
- A workflow layer that can compose multiple agents into larger systems.
- A custom context management system that decides what each agent sees on each turn.
- A provider layer that can talk to OpenAI-compatible endpoints without tying the architecture to one specific backend.
- A persistence and artifact model so runs can be replayed, inspected, and extended later.

## Design Principles

### Kernel First

The project should prove the runtime before building orchestration and UI complexity. Multi-agent systems should be built on top of a working single-agent kernel rather than invented all at once.

### Flexible Provider Boundary

Hephaestus should work with OpenAI-compatible endpoints today, while keeping the door open for a custom backend later. Provider integrations should therefore be adapters, not the source of truth for runtime behavior.

### Context As A System

Context should not be treated as raw transcript replay. The product should own a custom context management pipeline that can assemble bounded, explainable context packages from multiple sources.

### Observable Execution

Runs should be inspectable. Requests, streamed output, messages, tool calls, summaries, and context decisions should all be visible and auditable.

### Extensibility Over Premature Completeness

The first version should be narrow in features but strong in boundaries. The architecture should make it easy to add workflow composition, more tools, different providers, and a richer UI later.

## What Success Looks Like

Hephaestus will be on the right track when it can:

1. Run a single agent across multiple turns with correct continuity.
2. Assemble context intentionally rather than sending the full raw transcript.
3. Persist or at least clearly represent the run state and event history.
4. Add a second agent without rewriting the core runtime model.
5. Evolve into graph-based multi-agent workflows using the same kernel primitives.
