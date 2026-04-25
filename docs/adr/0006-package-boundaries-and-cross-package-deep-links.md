# 0006. Package Boundaries And Cross-Package Deep Links

**Status:** Accepted
**Date:** 2026-04-25
**Deciders:** Joshua Sumskas, Codex
**Technical Story:** Define local package boundaries and a deep-link architecture that allows packages to expose screens without depending on each other's UI implementation.

---

## Context

Hephaestus needs a frontend architecture that can scale beyond the first chat screen. The app should eventually contain multiple features, reusable UI components, theme primitives, agent runtime code, provider adapters, and app-specific composition.

The frontend should stay separate from the core agent implementation so the UI can evolve or be replaced without entangling the kernel. At the same time, feature packages need a way to expose screens that can be opened from other packages or from external deep links.

The project has already accepted:

- ADR-0002: a Swift-first kernel baseline
- ADR-0004: state/action page views with interactors
- ADR-0005: app-level router and modal navigation

This ADR extends those decisions by defining package boundaries and cross-package deep-link registration.

### Problem Statement

The project needs package boundaries that keep frontend code away from core runtime code, while still allowing screens in one package to be opened from another package through stable deep-linkable route inputs.

### Goals

- Keep the agent kernel free of SwiftUI and frontend framework dependencies.
- Put generic frontend architecture in its own package.
- Allow feature packages to define screens and expose deep-linkable route and modal inputs.
- Allow packages to link to screens in other packages without importing their views, interactors, or full feature implementation.
- Keep deep links stable by targeting route inputs rather than render state.
- Let the app target compose installed feature routes, modals, dependencies, and rendering.

### Non-Goals

- Implementing deep-link parsing in this ADR.
- Defining every app route and modal.
- Supporting dynamic third-party plugin loading.
- Making render state part of the deep-link contract.
- Letting arbitrary packages instantiate each other's SwiftUI screens directly.

---

## Decision Drivers

* UI and kernel code should remain replaceable independently.
* Feature packages should be able to expose screens without creating dependency cycles.
* Deep links should be stable and testable.
* The app target should remain the composition root.
* The first implementation should be provable with a small local POC.

---

## Considered Options

### Option 1: Package-Owned Destination Contracts With App-Composed Registry

**Description:** Each feature exposes a small public destination-contract surface containing stable route/modal input types and destination registrations. The app target composes all registrations into a destination registry. Deep links resolve to destination IDs and encoded inputs, then the app registry builds the destination with app-provided dependencies.

**Pros:**
- Avoids direct feature-to-feature UI dependencies.
- Keeps deep links tied to stable input state rather than transient render state.
- Lets the app control which features are installed.
- Supports normal navigation and external deep links through the same route/modal input path.
- Keeps generic routing infrastructure out of product-specific packages.
- Allows packages to depend on small route-contract modules instead of concrete UI implementation.

**Cons:**
- Requires a route registry abstraction.
- Requires discipline around route and modal input versioning.
- May need type erasure around encoded route inputs and view builders.
- Requires explicit build context plumbing for destination dependencies.

### Option 2: Global App Route Enum With Direct Feature Cases

**Description:** Put every route in one large `AppRoute` enum with associated values for each screen.

**Pros:**
- Simple to understand at small scale.
- Strong compile-time visibility of all routes.

**Cons:**
- Becomes large as features grow.
- Encourages the app target to know every feature detail.
- Makes cross-package route ownership unclear.
- Does not by itself solve deep-link decoding or feature-level route registration.

### Option 3: Feature Packages Import Each Other's Screens

**Description:** Let packages navigate directly to concrete screens from other packages.

**Pros:**
- Very direct call sites.
- Minimal routing infrastructure.

**Cons:**
- Creates package dependency cycles or broad dependency graphs.
- Couples packages to each other's UI implementation.
- Makes replacing frontend code harder.
- Conflicts with the goal of isolating core and frontend concerns.

---

## Decision

Hephaestus will use package-owned destination contracts with an app-composed registry for cross-package deep links.

**Chosen Option:** Option 1 - Package-Owned Destination Contracts With App-Composed Registry

### Rationale

The stable contract between packages should be a semantic destination identifier and a codable route/modal input, not a concrete SwiftUI view, interactor, or render state. This lets packages link to another screen by destination ID and input payload without depending on that screen's implementation.

The app target remains the composition root. It decides which feature route registrations are installed and how registered destinations are rendered. This keeps feature packages decoupled while still making navigation explicit and testable.

Cross-package typed linking should use small public route-contract modules. A package that needs to link to chat should be able to import `ChatRoutes` or `ChatContracts` to construct `ChatRouteInput`, without importing `ChatFeature` views, interactors, or feature internals. If a caller cannot or should not import the contract module, it may use URL/string deep links and let the registry decode them.

The generic UI architecture package will be named `Anvil`. The name fits the Hephaestus theme and describes the package's role: a stable shaping surface for pages, interactors, routing, modals, task scopes, and deep-link contracts.

---

## Consequences

### Positive

- Kernel packages remain independent from frontend packages.
- Feature packages can expose screens without depending on each other's UI implementation.
- Deep links become stable data contracts.
- The app target controls route composition and installed feature surface area.
- The same route/modal input can be used for normal navigation and external deep links.

### Negative

- The app needs a destination registry and type-erased destination input wrapper.
- Route and modal input schemas need to be treated as compatibility contracts.
- Destination construction can become indirect and needs good tests.
- Features that want typed cross-package links need small public contract targets.

### Neutral

- The first implementation can use only one or two feature registrations.
- Route IDs become part of the app's navigation API.
- Full plugin loading remains out of scope.

---

## Implementation

### Package Layout

The project should move toward this local package layout:

```text
Core/
  Anvil/
    Package.swift
    Sources/Anvil/
      Interactor/
      Page/
      Router/
      DeepLinking/
      TaskScope/

  HephaestusTheme/
    Package.swift
    Sources/HephaestusTheme/
      Colors/
      Typography/
      Spacing/
      Materials/

  HephaestusUI/
    Package.swift
    Sources/HephaestusUI/
      Buttons/
      Inputs/
      Panels/
      Chat/

  HephaestusKernel/
    Package.swift
    Sources/HephaestusKernel/
      Agent/
      Run/
      Context/
      ProviderContracts/

  HephaestusLLM/
    Package.swift
    Sources/HephaestusLLM/
      OpenAICompatible/
      MockProvider/

Features/
  ChatContracts/
    Package.swift
    Sources/ChatContracts/
      ChatRouteInput.swift
      ChatModalInput.swift

  ChatFeature/
    Package.swift
    Sources/ChatFeature/
      ChatPage.swift
      ChatPageInteractor.swift
      ChatRouteRegistration.swift
```

The first POC does not need to create every package immediately, but the dependency direction should follow this shape.

### Dependency Rules

The dependency direction should be:

```text
Hephaestus app
  -> feature packages
  -> HephaestusUI
  -> HephaestusTheme

Hephaestus app
  -> Anvil
  -> no product-specific packages

feature packages
  -> Anvil
  -> feature contract packages they need to link to
  -> use-case or kernel contracts they need

HephaestusKernel
  -> no SwiftUI
  -> no Anvil
  -> no HephaestusUI

HephaestusLLM
  -> provider contracts from HephaestusKernel
  -> no SwiftUI
```

Core runtime packages must not depend on SwiftUI, `Anvil`, `HephaestusUI`, or app-level route types.

Feature contract packages must stay small. They may define route IDs, modal IDs, route input types, modal input types, and lightweight helper factories. They may import `Anvil` for generic destination-contract protocols such as `RouteInput`, `ModalInput`, `AnyRouteInput`, `AnyModalInput`, and `NavigationIntent`. They must not import SwiftUI, feature interactors, feature views, or kernel implementation packages unless there is a specific contract-level reason.

### Destination Contracts

Deep links and cross-package navigation should target destination inputs, not render state.

Use separate protocols for stack routes and modals so ADR-0005's `Router<Route, Modal>` distinction remains intact.

```swift
public protocol RouteInput: Codable, Hashable, Sendable {
    static var routeID: String { get }
    static var version: Int { get }
}

public protocol ModalInput: Codable, Hashable, Sendable {
    static var modalID: String { get }
    static var version: Int { get }
}
```

Example feature-owned route input:

```swift
public struct ChatRouteInput: RouteInput {
    public static let routeID = "hephaestus.chat.main"
    public static let version = 1

    public let runID: UUID?
}
```

Example feature-owned modal input:

```swift
public struct ChatSettingsModalInput: ModalInput {
    public static let modalID = "hephaestus.chat.settings"
    public static let version = 1
}
```

Destination IDs must be namespaced. Use reverse-domain or product-prefixed IDs such as `hephaestus.chat.main`, not short IDs such as `chat`. Versions are part of the encoded payload contract and should be incremented when a breaking decode change is introduced.

Render state remains separate:

```swift
struct ChatPageState: Equatable {
    var messages: [ChatMessageState]
    var draftText: String
    var isRunning: Bool
    var errorMessage: String?
}
```

The interactor bridges from route input to render state:

```text
ChatRouteInput / ChatSettingsModalInput
  -> ChatPageInteractor
  -> ChatPageState
  -> ChatPage
```

Do not decode external links directly into `ChatPageState`.

### Type-Erased Destination Inputs

`Anvil` should provide type-erased wrappers so packages can pass route and modal inputs without importing the destination feature's view.

Illustrative shape:

```swift
public struct AnyRouteInput: Hashable, Sendable {
    public let routeID: String
    public let version: Int
    public let encoded: Data
}

public struct AnyModalInput: Hashable, Sendable, Identifiable {
    public let modalID: String
    public let version: Int
    public let encoded: Data

    public let instanceID: UUID

    public var id: UUID { instanceID }
}
```

It should support encoding a concrete route input:

```swift
let input = ChatRouteInput(runID: runID)
let anyInput = try AnyRouteInput(input)
```

And decoding inside the owning registration:

```swift
let input = try anyInput.decode(ChatRouteInput.self)
```

The decoder must validate that the incoming `routeID` or `modalID` matches the requested concrete type. It must also check the payload version and either decode it or return a typed unsupported-version error.

### Route Registration

Each feature package should export registrations for destinations it owns.

Illustrative shape:

```swift
public struct RouteRegistration {
    public let routeID: String
    public let version: Int
    public let decodeDeepLink: (URL) throws -> AnyRouteInput?
    public let build: @MainActor (AnyRouteInput, RouteBuildContext) throws -> AnyView
}

public struct ModalRegistration {
    public let modalID: String
    public let version: Int
    public let decodeDeepLink: (URL) throws -> AnyModalInput?
    public let build: @MainActor (AnyModalInput, RouteBuildContext) throws -> AnyView
}
```

Destination builders are main-actor-isolated because they construct SwiftUI views and page interactors. Deep-link decoding remains nonisolated because it only parses data.

Feature package example:

```swift
public enum ChatRoutes {
    public static var registration: RouteRegistration {
        RouteRegistration(
            routeID: ChatRouteInput.routeID,
            version: ChatRouteInput.version,
            decodeDeepLink: { url in
                // Decode URL into ChatRouteInput, then erase it.
            },
            build: { anyInput, context in
                let input = try anyInput.decode(ChatRouteInput.self)
                let submitMessage = try context.dependency(SubmitUserMessageUseCase.self)
                return AnyView(
                    Page(
                        interactor: ChatPageInteractor(
                            input: input,
                            submitMessage: submitMessage,
                            router: context.router
                        ),
                        view: ChatPage.init
                    )
                )
            }
        )
    }
}
```

The concrete implementation may avoid `AnyView` if a better type-erased destination abstraction is practical, but the registration must hide the concrete page/interactor from packages that only need to link to it.

### Route Build Context

Destination construction needs app-level dependencies. Registrations must receive a build context instead of relying on globals or singletons.

Illustrative shape:

```swift
public struct RouteBuildContext {
    public let router: Router<AnyRouteInput, AnyModalInput>
    private let resolveDependency: (Any.Type) throws -> Any

    public func dependency<T>(_ type: T.Type = T.self) throws -> T {
        guard let value = try resolveDependency(type) as? T else {
            throw RouteBuildError.missingDependency(String(describing: type))
        }
        return value
    }
}
```

`RouteBuildContext` must be defined in generic frontend infrastructure, not in the app target. It should expose a type-erased dependency resolution function so feature registrations can request the dependencies they need without importing the app's concrete composition root.

The app target is responsible for constructing `RouteBuildContext` and wiring `dependency(_:)` to the chosen dependency system, such as Stitch. Feature packages should request dependencies by protocol or public contract type and should not import the app target.

### Destination Registry

The app target composes feature registrations:

```swift
let registry = DestinationRegistry(
    routes: [
        ChatRoutes.registration,
        SettingsRoutes.registration,
        RunsRoutes.registration
    ],
    modals: [
        ChatRoutes.settingsModalRegistration
    ]
)
```

The registry is responsible for:

- looking up route registrations by `routeID`
- looking up modal registrations by `modalID`
- decoding external deep links into `AnyRouteInput` or `AnyModalInput`
- building destination views with a `RouteBuildContext`
- rejecting unknown or malformed route inputs
- rejecting duplicate route or modal IDs at startup
- rejecting unsupported route or modal input versions

Deep link matching must be deterministic. Prefer a canonical URL form where the host or first path component maps directly to a destination ID.

Example:

```text
hephaestus://route/hephaestus.chat.main?runID=...
hephaestus://modal/hephaestus.chat.settings
```

If multiple registrations match the same URL, registry construction or resolution should fail explicitly. It should not choose the first match silently.

### Navigation Intent

Navigation should still flow through the router from ADR-0005.

Suggested intent shape:

```swift
public enum NavigationIntent {
    case push(AnyRouteInput)
    case replaceStack([AnyRouteInput])
    case presentModal(AnyModalInput)
    case dismissModal
}
```

This lets a package request navigation to another package's route by route ID and encoded input without importing the destination screen.

ADR-0005's app router should become:

```swift
typealias AppRouter = Router<AnyRouteInput, AnyModalInput>
```

This refines ADR-0005's illustrative `Router<AppRoute, AppModal>` shape for the cross-package destination registry model. The app shell uses the destination registry to render `AnyRouteInput` stack entries and `AnyModalInput` modal entries.

### Deep Link Flow

The intended flow is:

```text
URL
  -> DestinationRegistry resolves matching registration
  -> registration decodes URL into concrete RouteInput or ModalInput
  -> RouteInput or ModalInput is erased
  -> Router applies NavigationIntent
  -> AppShell asks DestinationRegistry to build destination with RouteBuildContext
  -> Feature interactor builds render state from destination input
```

Normal navigation and external deep links should converge on the same route/modal input path.

### Cross-Package Linking

There are two supported ways to link to another package's destination:

1. Import the destination's small contract package and construct its route or modal input.
2. Use a URL/string deep link and let the destination registry decode it.

Do not import the destination feature package only to navigate to it.

Example typed link:

```swift
import ChatContracts

let input = try AnyRouteInput(ChatRouteInput(runID: runID))
router.push(input)
```

This imports only the contract target, not `ChatFeature`.

### POC Requirement

This ADR requires a proof of concept before the pattern is used widely.

The POC should prove:

- `Anvil` can live as a separate local package.
- A feature can define route/modal inputs and registrations.
- Another package or app-level component can navigate to that feature by importing only its contract package.
- Another package or app-level component can navigate to that feature using only a URL deep link.
- A deep link URL can decode into the same route or modal input.
- The target interactor can build page state from route input.
- The kernel package does not depend on any frontend package.
- Destination construction fails with a typed dependency error when the app composition root does not provide a required dependency.
- Route registrations and modal registrations remain separate, and modal inputs cannot be pushed as route inputs.

### POC Result

The architecture POC validated this pattern in a standalone SwiftPM package. It confirmed that a separate feature can construct a navigation intent to chat by importing only `ChatContracts`, while `ChatFeature` owns the SwiftUI page, interactor, and registration. It also confirmed that route builders need to be `@MainActor` and that contract packages need permission to import `Anvil`'s generic destination-contract types.

---

## Validation

This decision is correct if packages can expose deep-linkable screens without depending on each other's UI implementation and without coupling frontend packages to the agent kernel.

### Success Metrics

- `Anvil` contains only generic UI architecture primitives.
- Feature route/modal inputs are `Codable`, `Hashable`, and owned by the feature package.
- Route and modal IDs are namespaced and versioned.
- The app target composes a destination registry from feature registrations.
- A POC proves cross-package navigation by encoded route input.
- A POC proves external URL decoding into the same route/modal input path.
- A POC proves destination construction receives dependencies through `RouteBuildContext`.
- A POC proves missing route-build dependencies fail through a typed error.
- Kernel packages compile without SwiftUI or frontend package dependencies.

### Monitoring

- Watch for feature packages importing each other's concrete SwiftUI views.
- Watch for deep links decoding directly into page render state.
- Watch for manually encoded route payloads when a contract package should exist.
- Watch for `Anvil` gaining product-specific concepts.
- Watch for the kernel importing SwiftUI, `Anvil`, or `HephaestusUI`.
- Watch for route IDs changing without compatibility consideration.

---

## Related Decisions

- [0002. Swift Kernel Baseline For Hephaestus](./0002-swift-kernel-baseline.md)
- [0004. SwiftUI Interactor Page Architecture](./0004-swiftui-interactor-page-architecture.md)
- [0005. SwiftUI Router And Modal Navigation](./0005-swiftui-router-and-modal-navigation.md)

---

## References

- [Sashimi Architecture](../../sashimi/docs/architecture/architecture.md)
- [Sashimi Stack Navigation Design](../../sashimi/docs/architecture/stack-navigation-design.md)
- [Roadmap](../roadmap.md)

---

## Notes

This ADR intentionally defines the package and route-input architecture before implementation. The cross-package deep-linking pattern is non-trivial and should be validated with a small POC before the app accumulates many feature packages.

**Last Updated:** 2026-04-25
