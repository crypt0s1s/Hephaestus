# 0005. SwiftUI Router And Modal Navigation

**Status:** Accepted
**Date:** 2026-04-25
**Deciders:** Joshua Sumskas, Codex
**Technical Story:** Define app-level navigation and modal presentation ownership for the SwiftUI frontend.

---

## Context

Hephaestus will start with a small chat UI, but the frontend will quickly need more screens: provider settings, run inspection, context details, persisted sessions, and later workflow tooling.

ADR-0004 defines page views as pure state/action renderers backed by interactors. Navigation should follow the same principle: page views should not directly push routes or present sheets. Navigation state should be owned by a small app-level router and applied by the app shell.

The project also needs a single concept for temporary presentation. Instead of designing separately around sheets, panels, half-height presentations, and full-screen covers at the page level, the app should model presentation intent as a typed modal and let the shell decide how each modal is shown.

### Problem Statement

The app needs a lightweight navigation strategy that supports route stacks and modal presentation without leaking SwiftUI navigation mechanics into page views.

### Goals

- Centralize navigation stack state.
- Centralize modal presentation state.
- Keep pure page views navigation-agnostic.
- Let interactors request navigation through a typed router.
- Use app-specific typed routes and modals.
- Stay close to native SwiftUI navigation APIs.

### Non-Goals

- Building a custom navigation framework.
- Supporting multiple simultaneous modals in the first implementation.
- Solving multi-window state restoration.
- Defining every future route and modal now.

---

## Decision Drivers

* Page views should remain pure state/action renderers.
* Navigation should be testable without inspecting SwiftUI internals.
* The app needs a route stack and temporary presentation.
* SwiftUI-native APIs should remain the rendering mechanism.
* The first implementation should stay small enough for the kernel POC.

---

## Considered Options

### Option 1: Typed App Router With Route Stack And Modal

**Description:** Use a core `Router<Route, Modal>` owned by the app shell. The router stores a navigation path and one active modal. Interactors request navigation by calling the router. The shell renders routes and modals with SwiftUI APIs.

**Pros:**
- Keeps views free of navigation mechanics.
- Gives a single testable place for navigation state.
- Works naturally with typed route and modal enums.
- Leaves presentation style decisions in the app shell.
- Small enough to build locally.

**Cons:**
- Adds one local abstraction over SwiftUI navigation.
- Interactors can become coupled to app route/modal types if not managed carefully.

### Option 2: Direct SwiftUI Navigation In Views

**Description:** Let each page view own its own `NavigationLink`, `.sheet`, and presentation state.

**Pros:**
- Minimal infrastructure.
- Matches many simple SwiftUI examples.

**Cons:**
- Pushes navigation mechanics into pure views.
- Makes previews and tests less focused.
- Leads to inconsistent presentation patterns as the app grows.

### Option 3: External Router Framework

**Description:** Adopt a third-party routing/navigation framework.

**Pros:**
- May provide deep linking, state restoration, or advanced routing patterns.
- Reduces custom infrastructure.

**Cons:**
- Adds framework weight before the app needs it.
- May conflict with the local interactor/page architecture.
- Less control over macOS-specific presentation behavior.

---

## Decision

Hephaestus will use a typed app-level router with a navigation path and one active modal.

**Chosen Option:** Option 1 - Typed App Router With Route Stack And Modal

### Rationale

This keeps navigation aligned with the frontend architecture in ADR-0004. Pure page views emit actions. Interactors decide what those actions mean. The router owns navigation state. The app shell renders that state with SwiftUI.

The key abstraction is `modal`, not `sheet` or `fullScreenCover`. A modal describes presentation intent. The app shell can decide whether a modal is rendered as a sheet, full-screen cover, confirmation dialog, panel, or another native presentation form.

---

## Consequences

### Positive

- Navigation state is centralized and testable.
- Page views stay previewable without navigation dependencies.
- The app can change modal presentation style without changing page actions.
- Route and modal types document the app's navigable surface area.

### Negative

- The router becomes a shared dependency for interactors that navigate.
- The app shell must maintain route and modal view builders.
- Only one active modal is supported in the first implementation.

### Neutral

- Deep linking and restoration are deferred.
- macOS-specific modal sizing remains a shell/content concern, not a router concern.

---

## Implementation

### Core Router

The router should be a `@MainActor` observable object.

Suggested shape:

```swift
@MainActor
final class Router<Route: Hashable, Modal: Identifiable>: ObservableObject {
    @Published var path: [Route] = []
    @Published var modal: Modal?

    func push(_ route: Route) {
        path.append(route)
    }

    func pop() {
        _ = path.popLast()
    }

    func popToRoot() {
        path.removeAll()
    }

    func present(_ modal: Modal) {
        self.modal = modal
    }

    func dismissModal() {
        modal = nil
    }
}
```

### App Route And Modal Types

The app should define concrete route and modal enums at the shell level.

Initial illustrative shape:

```swift
enum AppRoute: Hashable {
    case chat
    case run(UUID)
    case providerSettings
}

enum AppModal: Identifiable {
    case providerSettings
    case runDetails(UUID)
    case confirmCancelRun(UUID)

    var id: String {
        switch self {
        case .providerSettings:
            "providerSettings"
        case .runDetails(let id):
            "runDetails-\(id)"
        case .confirmCancelRun(let id):
            "confirmCancelRun-\(id)"
        }
    }
}
```

The first implementation may only need a subset of these cases. The enum examples are illustrative, not required all at once.

ADR-0006 refines this illustrative app route/modal enum approach for cross-package feature navigation. When the destination registry is introduced, the app router should use `Router<AnyRouteInput, AnyModalInput>` and the shell should render entries through the registry. The ownership rule in this ADR remains the same: the shell owns navigation state, and pure page views stay navigation-agnostic.

### App Shell Ownership

The app shell should own the router and apply it to SwiftUI navigation.

Illustrative shape:

```swift
struct AppShell: View {
    // For simple, single-package navigation. ADR-0006 refines this to
    // Router<AnyRouteInput, AnyModalInput> once the destination registry exists.
    @StateObject private var router = Router<AppRoute, AppModal>()

    var body: some View {
        NavigationStack(path: $router.path) {
            Page(
                interactor: ChatPageInteractor(router: router),
                view: ChatPage.init
            )
            .navigationDestination(for: AppRoute.self) { route in
                routeView(route)
            }
            .sheet(item: $router.modal) { modal in
                modalView(modal)
            }
        }
    }
}
```

The shell decides presentation style. If a modal later needs full-screen presentation or a confirmation dialog, the shell can choose that based on the `AppModal` case.

### View And Interactor Rules

Pure page views:

- do not own routers
- do not call `NavigationStack`, `navigationDestination`, or `.sheet` for app-level navigation
- emit semantic actions such as `tapProviderSettings`

Interactors:

- may receive the app router or a navigation use case
- translate page actions into router mutations
- keep route decisions out of pure views

The router:

- owns route stack state
- owns active modal state
- does not know how route or modal views are rendered

### Modal Semantics

`AppModal` describes intent, not presentation mechanics.

Good modal cases:

- `providerSettings`
- `runDetails(UUID)`
- `confirmCancelRun(UUID)`

Avoid modal cases named only after mechanics:

- `sheet`
- `fullScreen`
- `halfScreen`

If the app later needs multiple modal styles, the shell should map semantic modal cases to SwiftUI presentation APIs.

---

## Validation

This decision is correct if the first chat UI can navigate or present settings/details without the pure page views knowing about SwiftUI navigation APIs.

### Success Metrics

- App shell owns the app router, either `Router<AppRoute, AppModal>` for simple local navigation or `Router<AnyRouteInput, AnyModalInput>` once ADR-0006's destination registry is introduced.
- Pure page views receive only `state` and `handle`.
- Interactors request navigation by mutating the router or calling a navigation use case.
- `AppModal` cases are semantic, not presentation-mechanic names.
- Route and modal rendering happens in the shell.

### Monitoring

- Watch for `.sheet` or route-stack state appearing in pure page views.
- Watch for interactors constructing SwiftUI views directly.
- Watch for modal cases being named after presentation mechanics instead of intent.
- Watch for multiple modal states being added before there is a concrete need.

---

## Related Decisions

- [0003. Initial Agent Kernel POC](./0003-initial-agent-kernel-poc.md)
- [0004. SwiftUI Interactor Page Architecture](./0004-swiftui-interactor-page-architecture.md)

---

## References

- [Roadmap](../roadmap.md)
- [Next Step](../next-step.md)

---

## Notes

The first implementation can start with only the route and modal cases needed for the chat proof of concept. The important decision is ownership: the shell owns navigation state, and views stay navigation-agnostic.

**Last Updated:** 2026-04-25
