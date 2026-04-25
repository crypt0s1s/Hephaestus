# Hephaestus Roadmap

## Summary

The project should be built in layers. Each layer should validate one architectural assumption before the next layer is added.

The order matters:

1. Prove a single-agent kernel.
2. Make the kernel observable and durable.
3. Build a competent single-agent harness.
4. Add multi-agent workflows on top of the harness.
5. Add richer native UI and operator tooling.

## Phase 1: Agent Kernel POC

Goal: prove that Hephaestus can execute a coherent agent turn lifecycle.

Deliverables:

- One `Agent` model with a fixed profile.
- One `Run` model that owns turn history.
- One `Provider` adapter that calls an OpenAI-compatible endpoint.
- One `ContextManager` that assembles context for each turn.
- One event stream that reports request lifecycle and streamed output.

Success criteria:

- The app can send a first user message.
- The provider returns a response.
- A second user message can be sent in the same run.
- The second response correctly reflects prior conversation state.

## Phase 2: Kernel Hardening

Goal: make the kernel reliable enough to build on.

Deliverables:

- Streaming support with chunked events.
- Error handling and cancellation.
- Structured event records rather than ad hoc logging.
- Local persistence for runs and artifacts.
- Replay of prior runs from stored state.

Success criteria:

- Runs survive app restarts or can be reconstructed from persisted state.
- Failures are surfaced as explicit runtime events.
- The runtime can replay what happened without re-calling the model.

## Phase 3: Single-Agent Harness

Goal: turn the kernel into a competent agent harness before introducing multi-agent orchestration.

Deliverables:

- Persistent chat and run history.
- A more complete context management pipeline with summaries, working memory, and artifact recall.
- Skills or capability profiles that shape how an agent behaves for a given task.
- A stronger tool model with permissions and structured results.
- Better run inspection so agent behavior can be debugged without reading implementation code.

Success criteria:

- A single agent can operate across longer sessions without relying on raw transcript replay.
- Prior runs and chats are persisted and can be resumed or inspected.
- Agent behavior can be varied through skills or profiles without rewriting the runtime.
- The harness feels stable and useful on its own, even before multi-agent support exists.

## Phase 4: Multi-Agent Workflows

Goal: build multi-agent composition on top of a working agent harness rather than directly on top of the kernel.

Deliverables:

- A typed `Message` or mailbox model between agents.
- Shared artifact references between agents.
- A second agent role, such as worker or reviewer.
- Routing logic for task delegation and result return.

Success criteria:

- One agent can delegate work to another agent.
- Messages are observable and persisted.
- Inter-agent traffic builds on existing harness primitives instead of bypassing them.
- A workflow can fan out and fan in without introducing a second execution model.

## Phase 5: Native Operator Experience

Goal: turn the runtime into a usable macOS tool.

Deliverables:

- Session list and run browser.
- Transcript and event timeline.
- Inspector for context assembly, messages, artifacts, and raw provider traffic.
- Workflow visualization.

Success criteria:

- An operator can understand what happened in a run without digging through code.
- The UI exposes enough runtime state to debug agent behavior.

## Ongoing Cross-Cutting Work

These concerns should be developed throughout the roadmap, not left until the end:

- Context policy design
- Provider capability abstraction
- Artifact storage model
- Testing strategy
- ADRs for major architectural decisions
