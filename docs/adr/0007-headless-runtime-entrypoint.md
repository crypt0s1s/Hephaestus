# 0007. Headless Runtime Entrypoint

**Status:** Accepted
**Date:** 2026-04-25
**Deciders:** Joshua Sumskas, Codex
**Technical Story:** Define headless support so the agent runtime can be exercised from a CLI or tests without requiring the SwiftUI app.

---

## Context

Hephaestus is a native macOS agent harness, but the core agent implementation should not require a GUI to run. The first real implementation milestone is still mock-first: a user should be able to submit a message, see mock streaming output, submit another message, and see another streamed response with conversation continuity.

The project also needs production rigor before replacing the template app UI. The architecture POC proved that the kernel, route contracts, interactor/page model, destination registry, and mock provider can compile and test as SwiftPM modules. The next decision is how to structure the real implementation so both the SwiftUI app and a non-UI executable can use the same runtime path.

### Background

The current app target is a stock SwiftUI/SwiftData template. The useful architecture is in a standalone SwiftPM proof package. If the real implementation is built directly inside the app target, the runtime will become harder to test headlessly and harder to reuse from a future backend or workflow runner.

### Problem Statement

Hephaestus needs a first-class headless runtime entrypoint so the core agent loop can be run, tested, and debugged without launching the macOS UI.

### Goals

- Keep the kernel, provider adapters, context manager, and use cases executable without SwiftUI.
- Provide a CLI-style executable for exercising the same mock streaming path as the GUI.
- Keep the GUI as a presentation adapter over shared runtime use cases.
- Make the mock streaming path deterministic and easy to test.
- Preserve future flexibility for a live provider adapter, automation runner, or backend extraction.

### Non-Goals

- Building a polished CLI product.
- Supporting multiple concurrent conversations in the headless executable.
- Implementing persistence, skills, tools, or live OpenAI-compatible providers in this decision.
- Replacing the native macOS GUI direction.
- Defining a remote server protocol or daemon process.

---

## Decision Drivers

* Core runtime behavior should be testable without simulator, signing, SwiftData, or UI lifecycle concerns.
* The GUI and CLI should not duplicate agent-loop logic.
* Streaming should be represented as a runtime/application stream, not as a SwiftUI-only behavior.
* Provider integration should remain swappable behind the existing `ProviderClient` boundary.
* The first real implementation should stay narrow enough to complete and validate.

---

## Considered Options

### Option 1: Shared Headless Runtime With GUI And CLI Entrypoints

**Description:** Put agent orchestration, use cases, context management, provider clients, and mock composition into headless-safe packages. Build the SwiftUI app and a CLI executable as separate entrypoints over the same runtime APIs.

**Pros:**
- Tests and manual debugging can run without the macOS app.
- The GUI proves presentation, not core runtime correctness.
- The CLI can exercise mock streaming and later live providers through the same use cases.
- Keeps future backend extraction plausible.
- Forces UI dependencies to stay out of the runtime.

**Cons:**
- Adds one more executable target and some command-line plumbing.
- Requires discipline around package boundaries and dependency direction.
- The first implementation needs a small shared composition layer instead of wiring everything directly in SwiftUI.

### Option 2: GUI-Only Runtime First

**Description:** Build the first real implementation entirely through the macOS app target, then add headless support later if needed.

**Pros:**
- Fewer targets at the start.
- Fastest path to seeing mock streaming in a window.
- Avoids CLI design questions during the first implementation.

**Cons:**
- Encourages runtime and UI coupling.
- Makes the agent loop harder to test and debug outside SwiftUI.
- Makes future automation, backend extraction, and workflow execution harder.
- Risks treating streaming as view-local behavior instead of runtime behavior.

### Option 3: Backend/Daemon First

**Description:** Build the runtime as a separate local service or daemon, with both GUI and CLI talking to it over an IPC or HTTP boundary.

**Pros:**
- Strong process boundary from the start.
- Natural path toward a future custom backend.
- GUI, CLI, and automation clients would share a service contract.

**Cons:**
- Adds process management, IPC, packaging, and failure modes before the kernel is mature.
- Slows down the first mock streaming milestone.
- Over-solves the current problem.

---

## Decision

Hephaestus will support a headless runtime from the first real implementation by using shared headless-safe runtime packages and separate GUI and CLI entrypoints.

**Chosen Option:** Option 1 - Shared Headless Runtime With GUI And CLI Entrypoints

### Rationale

The agent loop is the product's core, and it should be runnable without the SwiftUI app. A headless entrypoint gives a fast validation loop for the kernel, context manager, mock provider, streaming events, and future provider adapters.

This does not change the native macOS product direction. The GUI remains the primary user experience. The headless executable is a development and architecture tool that keeps the runtime honest by proving that the core implementation is not accidentally coupled to SwiftUI, `Anvil`, route registries, or app lifecycle concerns.

The first milestone should expose streaming from the runtime as an `AsyncSequence` or equivalent stream of application events. The GUI can render those events into progressive transcript state. The CLI can print those events as they arrive. Tests can consume the same stream deterministically.

This explicitly amends ADR-0003's initial UI constraint that streaming chunks did not need to be rendered live. That constraint applied to the earliest proof phase. For the first production-rigorous mock implementation, progressive mock streaming is now part of the acceptance criteria because headless and GUI execution should consume the same runtime stream.

---

## Consequences

### Positive

- The core agent path can be tested and manually exercised without UI.
- Streaming becomes a runtime/application concern, not a view-only concern.
- The macOS app can stay thin: app shell, router, feature rendering, and presentation state.
- A future live provider adapter can be tested through CLI before GUI polish.
- Future backend extraction remains easier because the runtime is already UI-independent.

### Negative

- The first implementation has more package/target setup than a single app-target spike.
- Shared composition must be designed carefully so it does not become a global service locator.
- CLI output is an additional behavior surface to keep compiling, even if it stays intentionally minimal.

### Neutral

- The first headless executable is for development validation, not a full product surface.
- GUI and CLI may format runtime events differently, but must consume the same underlying stream.
- Persistence remains deferred; the initial headless run can be in-memory only.

---

## Implementation

### Package Boundary

The real implementation should move toward this shape:

```text
Core/
  HephaestusKernel/
    Run, Turn, RunMessage, ContextManaging, ProviderClient

  HephaestusLLM/
    MockProviderClient
    future OpenAI-compatible provider adapters

  HephaestusRuntime/
    use cases
    run/session orchestration
    runtime event stream models
    in-memory run store
    mock harness construction

  Anvil/
    SwiftUI page/interactor/router/deep-link infrastructure

Features/
  ChatContracts/
    route and modal input contracts

  ChatFeature/
    ChatPage
    ChatPageInteractor
    ChatRoutes

Apps/
  HephaestusCLI/
    headless executable target
```

`HephaestusRuntime` must not import SwiftUI, `Anvil`, `ChatFeature`, or app target code. It may depend on `HephaestusKernel` and provider packages such as `HephaestusLLM`.

`ChatFeature` may depend on runtime use-case protocols or public runtime application types. It should not own the core submit-message use case implementation.

### Entrypoints

The macOS app entrypoint should:

- build or receive the shared runtime composition
- own the `Router<AnyRouteInput, AnyModalInput>`
- install feature route and modal registrations
- render `ChatFeature` through `Page(interactor:view:)`
- translate runtime streams into chat page state

The CLI entrypoint should:

- build the same mock runtime composition
- accept one or more user messages from arguments or stdin
- submit messages through the same runtime use case as the GUI
- print streaming assistant chunks as they arrive
- exit with a non-zero status for runtime failures

### Runtime Use Cases

The initial runtime use cases should be headless-safe:

- `CreateRunUseCase`
- `StreamUserMessageUseCase`
- `ObserveRunEventsUseCase`

`SubmitUserMessageUseCase` may still exist as a convenience wrapper, but the primary path for the next implementation should be streaming. A final-string API is useful for tests and simple call sites, but it must be layered over the streaming path rather than replacing it.

Suggested streaming shape:

```swift
public protocol StreamUserMessageUseCase {
    func streamUserMessage(
        runID: UUID,
        text: String
    ) async throws -> AsyncThrowingStream<RuntimeEvent, Error>
}
```

The exact event names can evolve, but the stream should represent at least:

- user message accepted
- context prepared
- assistant text delta
- assistant message completed
- turn failed

### Mock Streaming

The mock provider should stream multiple deterministic chunks with a small delay or controllable scheduler. The runtime should expose these chunks as runtime events. The GUI should render progressive text from those events, and the CLI should print the same text as chunks arrive.

Tests should not rely on wall-clock timing. If the mock uses delays for manual visual feedback, those delays should be configurable or disabled in tests.

### Composition

Both GUI and CLI need a way to build the same default mock harness. The initial implementation can put this in `HephaestusRuntime` if it stays small. If composition grows or starts pulling in infrastructure details, split it into a separate headless-safe `HephaestusComposition` package.

Composition must remain explicit. Avoid global singletons. Stitch can be used to register and resolve dependencies, but use cases should still be injectable and constructible in tests without launching either entrypoint.

### Dependency Rules

- `HephaestusKernel` imports no SwiftUI, no `Anvil`, and no feature packages.
- `HephaestusRuntime` imports no SwiftUI, no `Anvil`, and no feature packages.
- `HephaestusLLM` imports provider contracts from `HephaestusKernel` and no UI packages.
- `HephaestusCLI` imports runtime/kernel/provider packages and no SwiftUI.
- The macOS app imports UI packages and runtime packages.
- `ChatFeature` imports `Anvil`, `ChatContracts`, and runtime use-case protocols.

---

## Validation

This decision is correct if the same mock streaming agent path can run from both the macOS GUI and a headless executable without duplicating runtime logic.

### Success Metrics

- `swift run HephaestusCLI` can submit at least one message and print streamed mock assistant chunks.
- The macOS app can submit a message and render the same mock streaming event path progressively.
- Tests can consume the runtime stream without launching SwiftUI.
- `HephaestusRuntime` compiles without SwiftUI, `Anvil`, or feature packages.
- The real provider adapter can later replace the mock provider without changing GUI or CLI call sites.

### Monitoring

- Watch for SwiftUI imports appearing in kernel, runtime, or provider packages.
- Watch for chat feature code owning runtime use-case implementations.
- Watch for the CLI using a different code path from the GUI.
- Watch for streaming behavior implemented only in view state instead of runtime events.
- Watch for composition becoming an implicit global singleton.

---

## Related Decisions

- [0002. Swift Kernel Baseline For Hephaestus](./0002-swift-kernel-baseline.md)
- [0003. Initial Agent Kernel POC](./0003-initial-agent-kernel-poc.md)
- [0004. SwiftUI Interactor Page Architecture](./0004-swiftui-interactor-page-architecture.md)
- [0006. Package Boundaries And Cross-Package Deep Links](./0006-package-boundaries-and-cross-package-deep-links.md)

---

## References

- [Roadmap](../roadmap.md)
- [Next Step](../next-step.md)

---

## Notes

This ADR should be treated as a boundary decision for the real implementation. The next code milestone should create the shared runtime package and the minimal CLI before or alongside the SwiftUI chat screen, so headless execution stays real rather than aspirational.

**Last Updated:** 2026-04-25
