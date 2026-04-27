# PRD-0001 Technical Design: macOS Mock Chat Shell

**Status:** Draft
**Date:** 2026-04-25
**Owner:** Joshua Sumskas
**Related PRD:** [PRD-0001. macOS Mock Chat Shell](../prd/0001-macos-mock-chat-shell.md)
**Related Plan:** [macOS App Shell Chat POC Plan](./macos-app-shell-chat-poc.md)
**Related ADRs:** [ADR-0004](../adr/0004-swiftui-interactor-page-architecture.md), [ADR-0005](../adr/0005-swiftui-router-and-modal-navigation.md), [ADR-0006](../adr/0006-package-boundaries-and-cross-package-deep-links.md), [ADR-0007](../adr/0007-headless-runtime-entrypoint.md)

---

## Purpose

This document defines how PRD-0001 will be implemented in the current Swift package and macOS app layout. It covers app target wiring, package linkage, app shell composition, route rendering, validation, risks, and implementation order.

Product behavior, scope, and acceptance criteria remain in PRD-0001. This design only describes the implementation path for the mock chat shell.

## Current Layout

The repository currently has two entrypoint surfaces:

```text
Hephaestus.xcodeproj
  Hephaestus/
    HephaestusApp.swift
    ContentView.swift
    Item.swift

Package.swift
  Core/
    Anvil
    HephaestusKernel
    HephaestusLLM
    HephaestusRuntime
    HephaestusComposition
  Features/
    ChatContracts
    ChatFeature
  Apps/
    HephaestusCLI
  Tests/
    HephaestusRuntimeTests
```

The package already contains the reusable architecture needed by the app shell:

- `Anvil` provides `Router<AnyRouteInput, AnyModalInput>`, `DestinationRegistry`, `RouteBuildContext`, `Page`, and `BaseInteractor`.
- `ChatContracts` provides `ChatRouteInput` and `ChatSettingsModalInput`.
- `ChatFeature` provides `ChatRoutes.registration`, `ChatRoutes.settingsModalRegistration`, `ChatPageInteractor`, and `ChatPage`.
- `HephaestusComposition` provides `MockRuntimeComposition.make()` and `MockRuntimeHarness`.
- `HephaestusRuntime` provides `CreateRunUseCase` and `StreamUserMessageUseCase`, which are the required chat dependencies.

The macOS app target is still the stock SwiftUI/SwiftData template and does not yet link the root Swift package products.

## Architecture Wiring

The app should be a thin composition and rendering host over the existing package architecture:

```text
HephaestusApp
  -> HephaestusAppShell
  -> MockRuntimeComposition.make()
  -> Router<AnyRouteInput, AnyModalInput>
  -> DestinationRegistry(routes: [ChatRoutes.registration], modals: [ChatRoutes.settingsModalRegistration])
  -> RouteBuildContext(router:resolveDependency:)
  -> AnyRouteInput(ChatRouteInput(runID: nil))
  -> DestinationRegistry.buildRoute(...)
  -> Page(interactor: ChatPageInteractor, view: ChatPage.init)
  -> ChatPage
  -> StreamUserMessageUseCase
  -> mock runtime stream
```

The core ownership rule is:

- `HephaestusApp` owns SwiftUI application lifecycle only.
- `HephaestusAppShell` owns app-level composition, router state, registry construction, startup route selection, and route rendering.
- `DestinationRegistry` owns mapping route/modal inputs to feature builders.
- `ChatFeature` owns chat UI state, interaction handling, and runtime stream consumption.
- `HephaestusRuntime` and lower packages own run creation, context preparation, provider streaming, and runtime events.

No runtime package should import SwiftUI app code. No app target code should reimplement chat state transitions that already live in `ChatPageInteractor`.

## App Target And Package Linkage

The app target should consume the root Swift package products rather than copying source files into the Xcode project.

### Workspace Linkage

Update `Hephaestus.xcworkspace/contents.xcworkspacedata` so the workspace references both:

```text
container:Hephaestus.xcodeproj
container:Package.swift
```

This makes the package visible to Xcode at the workspace level and keeps source ownership in SwiftPM.

### App Product Linkage

Link the app target to the package products it imports directly:

- `Anvil`
- `ChatContracts`
- `ChatFeature`
- `HephaestusComposition`
- `HephaestusRuntime`

`HephaestusKernel` and `HephaestusLLM` should be transitive through `HephaestusComposition` and `HephaestusRuntime`. If Xcode requires explicit product references for a clean build, add them only after the first `xcodebuild` failure proves they are needed.

### Project File Constraints

Keep `Hephaestus.xcodeproj/project.pbxproj` edits minimal:

- Add Swift package product dependencies only for products imported by app target source.
- Add corresponding framework build files only to the macOS app target.
- Avoid moving package sources into Xcode groups as app target files.
- Avoid unrelated signing, deployment, or template cleanup changes in the same implementation diff unless needed to build.

### Executable Linkage Procedure

Prefer Xcode's local package linkage UI if available:

1. Open `Hephaestus.xcworkspace`.
2. Confirm the workspace contains both `Hephaestus.xcodeproj` and the root `Package.swift`.
3. Select the `Hephaestus` app target.
4. Add the package products listed above to **Frameworks, Libraries, and Embedded Content**.
5. Build once with `xcodebuild`.

If the project file must be edited manually, make the diff mechanically equivalent to Xcode's package product linkage:

1. Add one `XCSwiftPackageProductDependency` object for each direct product: `Anvil`, `ChatContracts`, `ChatFeature`, `HephaestusComposition`, and `HephaestusRuntime`.
2. Add those product dependency object IDs to the `packageProductDependencies` array on the `Hephaestus` `PBXNativeTarget`.
3. Add one `PBXBuildFile` object per product with `productRef` pointing at the matching `XCSwiftPackageProductDependency`.
4. Add those build file IDs to the app target's `PBXFrameworksBuildPhase.files` array.
5. Do not add package source files to `PBXSourcesBuildPhase`.
6. Do not add the products to test targets unless tests import them from Xcode target source.

The current project has the app target object `210F77E42F8E4C840000B61B` and app frameworks phase `210F77E22F8E4C840000B61B`. Treat those IDs as current-state references, not durable API.

After linkage, verify the project file contains:

- five `XCSwiftPackageProductDependency` entries for the direct products
- matching `PBXBuildFile` entries with `productRef`
- non-empty `packageProductDependencies` for the `Hephaestus` app target
- non-empty `files` in the app target framework build phase

## App Shell Composition

Replace the template root with a small app shell. The intended shape is:

```swift
import Anvil
import ChatContracts
import ChatFeature
import HephaestusComposition
import HephaestusRuntime
import SwiftUI

@MainActor
struct HephaestusAppShell: View {
    @StateObject private var router = Router<AnyRouteInput, AnyModalInput>()

    private let registry: DestinationRegistry
    private let runtime: MockRuntimeHarness
    private let startupRoute: AnyRouteInput

    init() throws {
        runtime = MockRuntimeComposition.make(delayNanoseconds: 80_000_000)
        registry = try DestinationRegistry(
            routes: [ChatRoutes.registration],
            modals: [ChatRoutes.settingsModalRegistration]
        )
        startupRoute = try AnyRouteInput(ChatRouteInput(runID: nil))
    }

    var body: some View {
        RouteHost(
            router: router,
            registry: registry,
            context: buildContext()
        )
        .task {
            if router.path.isEmpty {
                router.replaceStack([startupRoute])
            }
        }
    }

    private func buildContext() -> RouteBuildContext {
        RouteBuildContext(router: router) { type in
            if type == CreateRunUseCase.self {
                return runtime.createRun
            } else if type == StreamUserMessageUseCase.self {
                return runtime.streamUserMessage
            } else {
                throw RouteBuildError.missingDependency(String(describing: type))
            }
        }
    }
}
```

The final code may split `RouteHost` into a separate file, but the composition rules should stay the same.

### Startup Failure Handling

Because `DestinationRegistry` and `AnyRouteInput` construction can throw, `HephaestusApp` should avoid `fatalError` for normal startup failures. Prefer a small wrapper that stores either the shell or an error view:

```swift
struct HephaestusRootView: View {
    private let result: Result<HephaestusAppShell, Error>

    init() {
        result = Result { try HephaestusAppShell() }
    }

    var body: some View {
        switch result {
        case .success(let shell):
            shell
        case .failure(let error):
            StartupErrorView(error: error)
        }
    }
}
```

This satisfies the technical requirement that startup failures render explicitly rather than producing a blank window.

Minimal error views are sufficient for this slice:

```swift
struct StartupErrorView: View {
    let error: Error

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Hephaestus could not start")
                .font(.headline)
            Text(String(describing: error))
                .textSelection(.enabled)
        }
        .padding()
        .frame(minWidth: 520, minHeight: 320)
    }
}

struct RouteErrorView: View {
    let error: Error

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Screen could not be opened")
                .font(.headline)
            Text(String(describing: error))
                .textSelection(.enabled)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
```

## App Shell Rendering

Use the registry to render the current route. Do not instantiate `ChatPage` or `ChatPageInteractor` directly in app target code.

For this slice, full sidebar or multi-route UI is unnecessary. The route host can render the last route in the router path:

```swift
@MainActor
struct RouteHost: View {
    @ObservedObject var router: Router<AnyRouteInput, AnyModalInput>
    let registry: DestinationRegistry
    let context: RouteBuildContext

    var body: some View {
        Group {
            if let route = router.path.last {
                buildRoute(route)
            } else {
                ProgressView("Opening Hephaestus...")
            }
        }
        .sheet(item: Binding(
            get: { router.modal },
            set: { if $0 == nil { router.dismissModal() } }
        )) { modal in
            buildModal(modal)
        }
    }

    private func buildRoute(_ route: AnyRouteInput) -> AnyView {
        do {
            return try registry.buildRoute(route, context: context)
        } catch {
            return AnyView(RouteErrorView(error: error))
        }
    }

    private func buildModal(_ modal: AnyModalInput) -> AnyView {
        do {
            return try registry.buildModal(modal, context: context)
        } catch {
            return AnyView(RouteErrorView(error: error))
        }
    }
}
```

This intentionally uses the registry even though there is only one visible route. That proves ADR-0005 and ADR-0006 through the real app target instead of bypassing them for the first screen.

## Template Removal

Remove the SwiftData template from the active app path:

- `HephaestusApp.swift` should import `SwiftUI` only unless later code needs another app-level framework.
- The `WindowGroup` should render `HephaestusRootView` or equivalent.
- `.modelContainer(...)` should be removed from the app scene.
- `ContentView.swift` should either become the app shell/root view file or be replaced by purpose-named files such as `HephaestusRootView.swift`, `HephaestusAppShell.swift`, `RouteHost.swift`, and `StartupErrorView.swift`.
- `Item.swift` should be removed only if the Xcode project cleanup is being done in the same implementation change and the app target no longer references it. Otherwise, disconnect it from runtime behavior and leave repository deletion for a focused cleanup.

The implementation should not add persistence, SwiftData models, or persistent chat history for PRD-0001.

## Dependency Resolution

`RouteBuildContext` currently resolves dependencies by `Any.Type`. For this slice, a small app-local resolver closure is sufficient. It should expose only the dependencies used by `ChatRoutes.registration`:

- `CreateRunUseCase.self` -> `runtime.createRun`
- `StreamUserMessageUseCase.self` -> `runtime.streamUserMessage`

Do not introduce a global service locator. Do not make `MockRuntimeHarness` a singleton. Keep the harness as state owned by the app shell instance so it can later be replaced with live-provider composition.

If a future feature requires more dependencies, extend the resolver at the app shell boundary rather than making feature packages import `HephaestusComposition`.

## Runtime Behavior

The UI should consume the existing streaming path:

```text
ChatPage.tapSend
  -> ChatPageInteractor.handleTapSend()
  -> ensureRun()
  -> StreamUserMessageUseCase.streamUserMessage(runID:text:)
  -> RuntimeEvent stream
  -> ChatPageState.messages updates
```

The second message should reuse `ChatPageState.runID`. The runtime store keeps the `Run` in memory, and `RecentContextManager` includes prior messages when the mock provider request is built. The visible proof is the mock provider response text, which includes the request message count.

No app shell code should manually append chat messages or inspect provider requests.

## Validation Commands

Run package validation first:

```sh
CLANG_MODULE_CACHE_PATH="$PWD/.build/clang-module-cache" swift test -Xswiftc -strict-concurrency=complete -Xswiftc -warnings-as-errors
```

Run headless validation:

```sh
CLANG_MODULE_CACHE_PATH="$PWD/.build/clang-module-cache" swift run HephaestusCLI "hello" "second"
```

Run app build validation after workspace and app target linkage:

```sh
xcodebuild -workspace Hephaestus.xcworkspace -scheme Hephaestus -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO build
```

This is the local compile/link validation command. It intentionally disables code signing on the command line so the build does not depend on a developer machine having a `Mac Development` certificate for the configured app team. Do not encode this as a project signing change; keep project signing settings on their normal automatic/team-owned values unless a separate signing task changes them.

Manual app validation:

- Launch the `Hephaestus` macOS app.
- Confirm the default SwiftData item list is not visible.
- Send a non-empty first message and observe progressive assistant text.
- Confirm empty or whitespace-only input cannot be sent.
- Send a second message in the same window and confirm the second mock response reflects a larger context.
- Confirm app route or dependency construction failures render explicit error views if forced during development.

Concrete forced-failure checks:

- To exercise `RouteErrorView`, temporarily remove the `StreamUserMessageUseCase.self` branch from the app shell dependency resolver. Launching the chat route should render "Screen could not be opened" with a missing dependency error.
- To exercise `StartupErrorView`, temporarily construct the destination registry with duplicate `ChatRoutes.registration` entries. App launch should render "Hephaestus could not start" with a duplicate route error.
- Revert both forced-failure changes before committing implementation work.

## Risks

| Risk | Impact | Mitigation |
| --- | --- | --- |
| Manual `project.pbxproj` linkage is wrong | App build fails or links the wrong products | Keep linkage diff small and validate with `xcodebuild` immediately |
| App shell bypasses `DestinationRegistry` | The slice does not prove the accepted route architecture | Render chat only through `ChatRoutes.registration` and `registry.buildRoute` |
| Runtime composition becomes global | Later live-provider replacement becomes harder | Keep `MockRuntimeHarness` owned by `HephaestusAppShell` |
| Template SwiftData code remains active | App still behaves like the stock template | Remove `ModelContainer`, `SwiftData` imports, `@Query`, and item list from the active root |
| Xcode transitive package linkage is insufficient | Build failures despite valid SwiftPM tests | Add explicit product dependencies only for products the app needs |
| Startup errors crash the app | Manual validation sees a crash or blank window | Use root-level `Result` rendering and explicit error views |
| The implementation grows into navigation or persistence work | PRD-0001 takes on deferred scope | Keep this slice to one startup chat route, one in-memory run, and mock composition |

## Implementation Sequence

1. Add package visibility to the Xcode workspace.
   - Add `container:Package.swift` to `Hephaestus.xcworkspace/contents.xcworkspacedata`.
   - Do not duplicate SwiftPM source files into the app target.

2. Link app target package products.
   - Add direct app target dependencies for `Anvil`, `ChatContracts`, `ChatFeature`, `HephaestusComposition`, and `HephaestusRuntime`.
   - Keep project-file changes limited to package linkage unless build validation requires more.

3. Replace the active template bootstrap.
   - Remove active SwiftData setup from `HephaestusApp.swift`.
   - Point `WindowGroup` at the new root view.
   - Leave `Item.swift` deletion for the same change only if the project no longer references it.

4. Add app shell files.
   - Add `HephaestusRootView`.
   - Add `HephaestusAppShell`.
   - Add `RouteHost`.
   - Add small explicit error views for startup and route-building failures.

5. Wire mock runtime dependencies.
   - Construct `MockRuntimeComposition.make(...)` in the app shell.
   - Build `RouteBuildContext` with only `CreateRunUseCase` and `StreamUserMessageUseCase`.
   - Avoid global state.

6. Install and render the chat route.
   - Register `ChatRoutes.registration` and `ChatRoutes.settingsModalRegistration`.
   - Create `AnyRouteInput(ChatRouteInput(runID: nil))`.
   - Replace the router stack with the startup route on first appearance.
   - Render through `DestinationRegistry.buildRoute`.

7. Validate incrementally.
   - Run `swift test` before Xcode project edits if possible.
   - Run `swift run HephaestusCLI "hello" "second"` to confirm headless runtime behavior still works.
   - Run the no-signing `xcodebuild` validation command after app linkage.
   - Launch the app manually and complete the two-message mock chat validation.

8. Clean up only in scope.
   - Remove remaining active template UI paths.
   - Do not add persistence, provider settings, live network setup, sidebar navigation, or design-system work.

## Non-Goals For This Design

- Defining live provider setup.
- Adding persistence or SwiftData chat storage.
- Adding a polished design system.
- Adding a sidebar or multi-screen navigation model.
- Changing runtime package boundaries.
- Replacing `RouteBuildContext` with a larger dependency injection framework.
