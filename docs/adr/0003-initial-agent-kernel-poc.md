# 0003. Initial Agent Kernel POC

**Status:** Accepted
**Date:** 2026-04-25
**Deciders:** Joshua Sumskas, Codex
**Technical Story:** Define the first implementation phase for proving the agent kernel with a minimal UI, mock provider, Stitch dependency injection, and testable use cases.

---

## Context

Hephaestus has an accepted baseline architecture: Swift-first, local-first, modular monolith, actor-oriented runtime, custom context management, and OpenAI-compatible provider adapters. The project now needs a practical first implementation phase.

The first phase should prove the kernel path before investing in a fuller harness, persistence, skills, tools, or multi-agent workflows. It should still include a small UI, because the app is a native macOS product and the kernel needs to be exercised through the same shape the app will eventually use.

The implementation should use dependency injection so the provider, context manager, and use cases can be replaced in tests. The project should use Stitch by EntrHQ for dependency injection.

### Problem Statement

The project needs a narrow first milestone that proves the agent kernel works end to end without depending on a real model endpoint or a complex UI.

### Goals

- Build the smallest useful single-agent kernel path.
- Provide a basic SwiftUI chat interface for manual testing.
- Use Stitch for app dependency wiring.
- Route UI actions through use cases rather than direct provider calls.
- Use a mock provider first so behavior is deterministic and testable.
- Keep the real OpenAI-compatible endpoint as a later adapter swap, not a UI rewrite.

### Non-Goals

- Persisting chats or runs to disk.
- Rendering streaming chunks live in the transcript. This was later amended by ADR-0007 for the first real mock-streaming implementation, where progressive mock streaming becomes part of the GUI and headless validation path.
- Adding tools, skills, memory, summaries, or artifact retrieval.
- Building multi-agent messaging or workflow composition.
- Implementing a production-grade provider configuration UI.

---

## Decision Drivers

* The first milestone should prove the runtime lifecycle with minimum moving parts.
* Tests need deterministic provider behavior.
* The UI should exercise the real application path, not a separate demo path.
* Dependencies should be swappable for tests and previews.
* The design should leave room for later persistence, real streaming UI, skills, tools, and real providers.

---

## Considered Options

### Option 1: Mock-First Kernel With Thin Chat UI

**Description:** Implement the kernel, use cases, Stitch wiring, mock provider, deterministic context manager, and a simple SwiftUI chat surface. Add the real provider adapter after the mock path is stable.

**Pros:**
- Proves the kernel before introducing endpoint variability.
- Allows useful unit tests from the start.
- Gives a manual UI path without overbuilding the app.
- Keeps the real provider behind the same interface as the mock provider.

**Cons:**
- The first visible app will not call a real LLM until a later step.
- Streaming UI behavior is deferred even though the event model prepares for it.

### Option 2: Real Endpoint First

**Description:** Implement the provider adapter first and wire the initial UI directly to a real OpenAI-compatible endpoint.

**Pros:**
- Produces an impressive manual demo quickly.
- Tests the external integration early.

**Cons:**
- Makes tests slower, nondeterministic, and dependent on credentials/network.
- Encourages coupling UI behavior to provider behavior before the kernel is proven.
- Makes failures harder to diagnose because runtime and endpoint bugs appear together.

### Option 3: Kernel-Only With No UI

**Description:** Implement only core types and tests, leaving the UI until the kernel is more mature.

**Pros:**
- Fastest path to pure runtime tests.
- Avoids UI decisions during the first kernel pass.

**Cons:**
- Does not validate the app-level interaction shape.
- Risks building a kernel that is awkward to observe from SwiftUI.
- Delays manual testing of the product surface.

---

## Decision

The initial implementation phase will use a mock-first single-agent kernel with a thin SwiftUI chat UI and Stitch-based dependency injection.

**Chosen Option:** Option 1 - Mock-First Kernel With Thin Chat UI

### Rationale

This option proves the most important path while keeping the number of variables low. The first implementation should answer one question: can the app submit two sequential user messages through the real kernel path, assemble context correctly, and produce assistant messages with continuity?

Using a mock provider first makes that question testable. The mock should be deterministic and should expose enough received context for tests to verify that the second turn includes prior state and does not duplicate the current user message.

The UI should stay deliberately simple. It should display user messages immediately and append the assistant response when the turn finishes. The runtime event model should still support provider chunks, but the first UI does not need to render partial text live.

ADR-0007 amends this UI constraint for the next real implementation milestone. The proof phase can still use final-response rendering, but the first production-rigorous mock implementation should expose and render mock streaming events so the GUI, CLI, and tests exercise the same runtime stream.

Stitch should be used as the dependency injection mechanism. The UI should depend on use cases or view models composed from use cases, not on provider adapters directly.

### Proof-First Implementation Note

Before replacing the app UI, the project validated the core architecture in a standalone SwiftPM proof package. This was intentionally done before app integration because it tests the package boundaries, route contracts, destination registry, interactor/page shape, mock provider, and two-turn kernel continuity without simulator, signing, or SwiftData template friction.

The production implementation should now port the proven package shapes into the real app/package layout rather than treating the proof package as the final module structure.

---

## Consequences

### Positive

- The first implementation is testable without a real endpoint.
- The app gets a real manual testing path early.
- Provider integration remains replaceable through dependency injection.
- The kernel, context manager, and use cases can evolve independently of the UI.

### Negative

- The first milestone does not prove real endpoint behavior.
- The UI will initially feel basic because assistant output appears only when a turn completes.
- Stitch setup adds a dependency before the app has much runtime code.

### Neutral

- Persistence remains deferred until the kernel path is proven.
- Streaming is represented internally but not fully surfaced in the first UI.
- The real endpoint adapter becomes the next integration step after the mock provider path passes tests.

---

## Implementation

The first implementation phase should be built in this order:

1. Preserve the passing SwiftPM architecture proof as a reference while moving code into the real package layout.
2. Add Stitch as a Swift Package dependency.
3. Create the composition root for app dependencies.
4. Define the kernel contracts from ADR-0002 in Swift.
5. Implement the deterministic v0 `ContextManager`.
6. Implement `MockProviderClient`.
7. Implement use cases for creating a run, submitting a user message, and observing run events.
8. Replace the template item-list UI with a basic chat UI.
9. Add tests around the kernel and use cases.
10. Add the real OpenAI-compatible provider adapter after the mock path is stable.

### Use Case Boundary

The first app use cases should be:

- `CreateRunUseCase`: creates an in-memory run for the default agent.
- `SubmitUserMessageUseCase`: submits user text into the run and drives one turn through the kernel.
- `ObserveRunEventsUseCase`: exposes runtime events for UI state and future persistence.

The UI should call use cases. It should not construct provider requests, assemble context, or mutate run internals.

### Mock Provider

The mock provider should:

- conform to `ProviderClient`
- return deterministic assistant text
- support the same async stream shape as the real provider
- record the last received `ProviderRequest` for tests

The mock response can be simple, but it must make continuity testable. For example, it can mention the number of provider messages it received or echo selected prior message text in a predictable way.

### Context Manager V0

The first context manager should:

- keep the system prompt separate from runtime messages
- include the most recent 20 non-system messages
- include the current user message exactly once
- produce a `ContextAssemblyTrace`
- avoid token counting, summaries, and model-based compaction

This keeps the behavior simple while preserving the architecture for later custom compaction.

### Basic UI

The first UI should:

- show a single in-memory conversation
- append user messages immediately
- show a sending/running state during the turn
- append the assistant message only when the turn finishes
- show basic failure text if the turn fails

The first UI does not need session lists, provider settings, persistence, streaming partial text, or an inspector.

### Real Provider Adapter

The real OpenAI-compatible provider adapter should be added after the mock path is tested. It should use the same `ProviderClient` interface and receive configuration through DI, so swapping mock and real providers does not change the UI or use cases.

---

## Validation

This decision is correct if the first implementation can prove the kernel path in tests and through a minimal UI without relying on an external endpoint.

### Architecture POC Result

The architecture proof is considered successful if a standalone SwiftPM package can compile and test:

- `Anvil` interactor/page/router/deep-link primitives
- `HephaestusKernel` without SwiftUI or frontend dependencies
- `HephaestusLLM` mock provider through the kernel provider boundary
- `ChatContracts` as a small route/modal contract package
- `ChatFeature` destination registration and page construction
- a separate feature linking to chat by importing only `ChatContracts`
- two sequential turns with prior context included and the current user message included once

The proof validates the architecture shape, not the final app integration. The remaining implementation concerns are Stitch composition, event observation from the UI, app shell rendering, persistence, and the real provider adapter.

### Success Metrics

- The app can create a run and submit a user message through use cases.
- The mock provider produces a deterministic assistant response.
- The UI displays a two-turn conversation using the kernel path.
- Tests verify that turn two includes prior context and includes the current user message exactly once.
- Tests can swap provider and context manager dependencies through Stitch or direct use-case construction.

### Monitoring

- Watch for provider-specific request construction leaking into views.
- Watch for context assembly moving into view models or provider adapters.
- Watch for UI code depending directly on mock-provider behavior.
- Watch for tests requiring network access before the real provider adapter is intentionally added.

---

## Related Decisions

- [0001. Record Architecture Decisions](./0001-record-architecture-decisions.md)
- [0002. Swift Kernel Baseline For Hephaestus](./0002-swift-kernel-baseline.md)
- [0007. Headless Runtime Entrypoint](./0007-headless-runtime-entrypoint.md)

---

## References

- [Swift Package Registry: Stitch](https://swiftpackageregistry.com/entrhq/stitch)
- [Roadmap](../roadmap.md)
- [Next Step](../next-step.md)

---

## Notes

This ADR intentionally keeps the first phase small. The purpose is to prove the runtime shape and dependency boundaries before adding persistence, skills, tools, model-backed context compaction, or multi-agent orchestration.

**Last Updated:** 2026-04-25
