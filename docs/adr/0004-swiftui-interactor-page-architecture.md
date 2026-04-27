# 0004. SwiftUI Interactor Page Architecture

**Status:** Accepted
**Date:** 2026-04-25
**Deciders:** Joshua Sumskas, Codex
**Technical Story:** Define the frontend architecture convention for SwiftUI pages, presentation state, actions, lifecycle binding, and async action handling.

---

## Context

Hephaestus needs a frontend architecture that keeps SwiftUI views simple while still supporting async runtime work, testable state transitions, dependency injection, and reusable page structure.

The initial app UI will be a small chat surface, but later phases will add run inspection, context visibility, provider settings, persistence views, and eventually workflow tooling. The frontend architecture should therefore establish a repeatable pattern early without introducing a large external state-management framework.

The desired shape is that core page views receive renderable state and an action handler. The object that owns state, lifecycle, tasks, and use-case calls should be separate from the pure SwiftUI view.

### Problem Statement

The project needs a local SwiftUI architecture convention for pages that separates rendering from action handling and side effects.

### Goals

- Keep page views as pure as practical: `state` in, `handle(action)` out.
- Use present-tense actions that represent user or view events.
- Keep lifecycle methods separate from actions.
- Centralize async task handling and cancellation.
- Keep interactors scoped to the page lifecycle, not to durable runtime or domain lifecycles.
- Ensure state mutation happens on the main actor.
- Make page views easy to preview and test without constructing runtime dependencies.
- Keep the pattern lightweight enough for the first chat UI.

### Non-Goals

- Adopting a full state-management framework such as TCA.
- Defining every subview composition strategy.
- Solving navigation architecture for the whole app.
- Modeling runtime/provider events as view actions.

---

## Decision Drivers

* SwiftUI views should remain small and previewable.
* Page state should be easy to inspect and test.
* User actions should be explicit and easy to trace.
* Async work should not leak into button closures or layout code.
* Lifecycle binding should be consistent across pages.
* Interactors should not become long-lived service objects by accident.
* The architecture should work with Stitch dependency injection and use-case boundaries.

---

## Considered Options

### Option 1: State/Action Views With Interactors And `Page`

**Description:** Page views receive state and a synchronous action handler. An interactor owns state, handles actions, calls use cases, and manages lifecycle/tasks. A generic `Page(interactor:view:)` wrapper binds SwiftUI lifecycle to the interactor.

**Pros:**
- Keeps views pure and previewable.
- Gives a consistent action-handling path.
- Keeps async work and side effects out of views.
- Provides a natural place for task cancellation and lifecycle hooks.
- Avoids pulling in a heavy framework too early.

**Cons:**
- Requires maintaining local architecture infrastructure.
- Can become boilerplate-heavy if every tiny subview gets its own state/action pair.

### Option 2: Standard SwiftUI MVVM

**Description:** Use `ObservableObject` view models directly inside views, with views calling view model methods.

**Pros:**
- Familiar to SwiftUI developers.
- Minimal custom infrastructure.

**Cons:**
- Views can easily become coupled to methods and side effects.
- Lifecycle and task handling become inconsistent across pages.
- Previews often need real or fake view models instead of simple state.

### Option 3: Full State-Management Framework

**Description:** Adopt a framework such as The Composable Architecture for reducers, effects, state, and actions.

**Pros:**
- Strong conventions and testing story.
- Good fit for complex state graphs later.

**Cons:**
- Adds significant framework weight before the UI is complex.
- Can slow early iteration.
- May be more structure than the first kernel/chat UI needs.

---

## Decision

Hephaestus will use state/action SwiftUI page views backed by interactors, with a generic `Page(interactor:view:)` wrapper for lifecycle binding.

**Chosen Option:** Option 1 - State/Action Views With Interactors And `Page`

### Rationale

This architecture keeps rendering, action handling, and side effects separated while staying lightweight. It gives the project a clear convention for the first chat UI and for later screens that need to observe runs, inspect context, or coordinate use cases.

The term `Interactor` is used instead of `ViewModel` because the object does more than shape data for the view. It handles actions, owns presentation state, manages page-scoped async tasks, binds lifecycle, and calls use cases.

Interactors are still view-lifecycle objects. They must not become the durable owner of runtime sessions, provider IO, persisted domain state, or background work that needs to continue after the page disappears. If work must survive view disappearance, it belongs in an app-lifetime or domain-lifetime service that the interactor attaches to while visible.

The generic host should be called `Page`, and top-level screens should be composed with:

```swift
Page(
    interactor: ChatPageInteractor(...),
    view: ChatPage.init
)
```

This requires page views to follow the standard initializer shape:

```swift
init(
    state: State,
    handle: @escaping (Action) -> Void
)
```

---

## Consequences

### Positive

- Page views can be previewed with static state and a no-op handler.
- Interactors provide a consistent place for async work, state mutation, and lifecycle.
- The UI can call use cases without knowing kernel/provider details.
- The pattern is small enough to implement locally.

### Negative

- The project needs a small amount of local UI framework code.
- Interactors can become large if action handling is not split into private methods.
- Some Swift generic constraints may need a small spike before the final `Page` implementation is locked.

### Neutral

- Subviews may use the same state/action style, but this ADR only requires it for key page-level views.
- The architecture does not prevent adopting a heavier state framework later if the UI grows enough to justify it.

---

## Implementation

### Core Types

The frontend infrastructure should include:

- `BaseInteractor<State, Action>`
- `Page<Interactor, Content>`
- `PageTaskScope`
- `StoreState<Data, Failure>`

### Core Principle: Interactors Are Page-Lifecycle Adapters

Interactors are owned by `Page` through `@StateObject` and are bound to SwiftUI lifecycle hooks. They are therefore suitable for:

- translating view actions into use-case calls,
- owning renderable page state,
- managing page-scoped tasks and subscriptions,
- mapping service snapshots into view state, and
- requesting navigation or presentation changes.

They are not suitable as the source of truth for work with a longer lifetime than the page. Interactors should not own:

- long-running provider or runtime IO that must continue after `onDisappear`,
- persisted domain state,
- per-session caches that outlive the visible screen,
- cross-page coordination, or
- background tasks whose cancellation semantics are domain decisions rather than view lifecycle decisions.

When a feature needs durable behavior, introduce a service at the appropriate lifetime boundary and have the interactor subscribe to it. The interactor may detach on disappear without corrupting the underlying operation.

Dependency injection should follow the same lifetime boundary. App-scope dependencies can be injected into route builders and interactors through the route context. Page-scope dependencies belong to the interactor. Domain services with a longer lifetime, such as a chat-session service, should be created and retained by an app-scope registry or container, not by the page interactor.

### Store State

Page and service state should represent loadable data with a shared model instead of parallel booleans and optional errors.

The shared shape is:

```swift
enum StoreState<Data, Failure: Error> {
    case loading(placeholder: Data? = nil)
    case loaded(Data)
    case error(Failure)
}
```

Use `StoreState` when a page or service renders data that can be loading, loaded, or failed. Prefer this over local pairs such as `isLoadingSessions` plus `persistenceErrorMessage`, or `isLoading` plus optional data plus optional error. The optional placeholder lets the UI keep rendering stale data while a refresh is in flight.

### `BaseInteractor`

`BaseInteractor` should:

- be `@MainActor`
- own `@Published private(set) var state`
- expose `func handle(_ action: Action)`
- wrap action handling in a main-actor task scope
- expose lifecycle hooks `onAppear()` and `onDisappear()`
- cancel active tasks on disappear by default
- expose `setState(_:)` as the only state mutation convention
- dispatch actions to `handleAction(_:)`

The switch in `handleAction(_:)` should only route to private handler methods. Substantial work should live in methods such as `handleTapSend()` or `handleChangeDraft(_:)`.

Illustrative shape:

```swift
@MainActor
class BaseInteractor<State, Action>: ObservableObject {
    @Published private(set) var state: State
    private let taskScope = PageTaskScope()

    init(initialState: State) {
        self.state = initialState
    }

    func handle(_ action: Action) {
        taskScope.run { [weak self] in
            await self?.handleAction(action)
        }
    }

    func onAppear() {}

    func onDisappear() {
        taskScope.cancelAll()
    }

    func handleAction(_ action: Action) async {
        preconditionFailure("Override handleAction(_:)")
    }

    func setState(_ update: (inout State) -> Void) {
        update(&state)
    }
}
```

`PageTaskScope` should also be `@MainActor`. The compiled POC showed that treating the scope as main-actor-owned avoids task cleanup racing with interactor state ownership and keeps the code compatible with Swift's stricter concurrency checks.

### `Page`

`Page` should:

- own the interactor with `@StateObject`
- render the supplied pure page view
- pass `interactor.state` and `interactor.handle` to the view
- call `interactor.onAppear()` from SwiftUI `onAppear`
- call `interactor.onDisappear()` from SwiftUI `onDisappear`

The intended call site is:

```swift
Page(
    interactor: ChatPageInteractor(...),
    view: ChatPage.init
)
```

The illustrative shape is:

```swift
struct Page<Interactor: BaseInteractor<State, Action>, State, Action, Content: View>: View {
    @StateObject private var interactor: Interactor
    private let view: (State, @escaping (Action) -> Void) -> Content

    init(
        interactor: @autoclosure @escaping () -> Interactor,
        @ViewBuilder view: @escaping (State, @escaping (Action) -> Void) -> Content
    ) {
        _interactor = StateObject(wrappedValue: interactor())
        self.view = view
    }

    var body: some View {
        view(interactor.state, interactor.handle)
            .onAppear { interactor.onAppear() }
            .onDisappear { interactor.onDisappear() }
    }
}
```

### Actions

Actions should describe user or view events exposed by the rendered view.

Use present-tense names such as:

- `tapSend`
- `tapRetry`
- `tapCancel`
- `tapChat(UUID)`
- `changeDraft(String)`
- `scrollToBottom`
- `reachHistoryEnd`

Avoid naming user actions after implementation details such as `openSession`. If selecting a chat requires loading or opening a session, expose the user intent as `tapChat(id)` and route to a private interactor helper such as `openSession(id)`.

Do not use actions for internal runtime events that the view does not directly produce. Provider chunks, run completion, and context assembly events should be observed by the interactor or use cases and mapped into state.

Lifecycle should not be modeled as actions. Use `onAppear()` and `onDisappear()` on the interactor instead.

Runtime events that represent durable domain progress should normally be owned by a runtime or session service first. The interactor should observe a page-appropriate projection of that service while the view is visible.

### Page Views

Key page-level views should have this shape:

```swift
struct ChatPage: View {
    let state: ChatPageState
    let handle: (ChatPageAction) -> Void
}
```

Previews should instantiate the pure view directly:

```swift
#Preview {
    ChatPage(
        state: .preview,
        handle: { _ in }
    )
}
```

---

## Validation

This decision is correct if the first chat UI can be built without views directly knowing about providers, context managers, or run internals.

### Success Metrics

- `ChatPage` can be previewed with static state and a no-op handler.
- `ChatPageInteractor` owns state and calls use cases.
- View actions use present-tense event names.
- `onAppear` and `onDisappear` are lifecycle hooks, not action cases.
- State mutation in interactors happens through `setState(_:)`.
- Async work is launched through the interactor task scope.
- The task scope is main-actor-owned and cancels page tasks on disappear.
- Long-running runtime work can continue correctly when the page interactor disappears, because that work is owned outside the interactor.

### Monitoring

- Watch for views calling use cases or providers directly.
- Watch for interactors growing large without private handler methods.
- Watch for interactors owning app-lifetime or session-lifetime services directly instead of subscribing to them.
- Watch for interactors becoming the only source of truth for persisted or background domain state.
- Watch for runtime events being modeled as view actions.
- Watch for state mutation outside `setState(_:)`.

---

## Related Decisions

- [0002. Swift Kernel Baseline For Hephaestus](./0002-swift-kernel-baseline.md)
- [0003. Initial Agent Kernel POC](./0003-initial-agent-kernel-poc.md)

---

## References

- [Roadmap](../roadmap.md)
- [Next Step](../next-step.md)

---

## Notes

The names in this ADR are intentional: `Page` is the lifecycle host, page views are renderers, and interactors own action handling and presentation state.

**Last Updated:** 2026-04-25
