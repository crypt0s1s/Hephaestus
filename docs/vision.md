# Hephaestus Vision

## End Goal

Hephaestus is intended to become a native macOS environment for building, running, configuring, and inspecting agent systems.

The long-term target is not just a single-agent harness. It is a meta-harness: a system that can define and execute agent work across multiple harness backends, including the native Foundry runtime, Codex CLI, Claude Code, and future adapters.

## Product Shape

At maturity, Hephaestus should provide:

- A native SwiftUI macOS application for operating and inspecting agent runs.
- A project-scoped workspace model, where each filesystem project contains tasks, sessions, runs, artifacts, and configuration.
- A reusable native agent runtime, Foundry, that owns the lifecycle of an agent turn.
- A harness adapter layer that can run work through Foundry, Codex CLI, Claude Code, or other backends.
- A messaging model that allows agents to communicate with each other in a structured way.
- A workflow layer that can compose multiple agents, roles, tools, approval policies, and backend choices into larger systems.
- A workflow creation surface that can start simple and later support reusable workflow recipes.
- A custom context management system that decides what each agent sees on each turn.
- A provider layer that can talk to OpenAI-compatible endpoints without tying the architecture to one specific backend.
- A persistence and artifact model so runs can be replayed, inspected, and extended later.

## Design Principles

### Kernel First

The project should prove the runtime before building orchestration and UI complexity. Multi-agent systems should be built on top of a working single-agent kernel rather than invented all at once.

### Flexible Provider Boundary

Hephaestus should work with OpenAI-compatible endpoints today, while keeping the door open for a custom backend later. Provider integrations should therefore be adapters, not the source of truth for runtime behavior.

### Flexible Harness Boundary

Hephaestus should also support different execution harnesses. Foundry, Codex CLI, and Claude Code should be modeled as harness backends with declared capabilities rather than as special-case UI flows.

### Workflow-State UI

The primary user interface should be driven by the current workflow state. Chat is one useful panel, but it should not be the only shape of work. Planning, running, waiting for approval, reviewing, comparing, and completing should each have a first-class surface.

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
5. Run the same kind of task through different harness backends.
6. Evolve into graph-based multi-agent workflows using the same kernel and harness primitives.

## Related Vision Notes

- [Product UI Vision](./product-ui-vision.md)
- [Observability Objectives](./observability-objectives.md)
