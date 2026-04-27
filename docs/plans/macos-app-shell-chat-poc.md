# macOS App Shell Chat POC Plan

Detailed PRD-0001 implementation guidance now lives in [PRD-0001 Technical Design: macOS Mock Chat Shell](./0001-macos-mock-chat-shell-technical-design.md). Keep this POC plan as the short milestone outline.

## Goal

Render the first real Hephaestus macOS screen using the committed package architecture:

```text
Hephaestus app target
  -> app composition root
  -> MockRuntimeComposition
  -> Anvil Router + DestinationRegistry
  -> ChatFeature registration
  -> Page(interactor:view:)
  -> mock streaming chat UI
```

The milestone is intentionally small: launch the native macOS app, type a message, tap send, see mock streaming text render, then send a second message and confirm the runtime includes prior context.

## Current State

- `Hephaestus/ContentView.swift` is still the default SwiftData template.
- `Hephaestus/HephaestusApp.swift` still creates a SwiftData `ModelContainer` for `Item`.
- The SwiftPM package builds and tests independently.
- The Xcode workspace currently references only `Hephaestus.xcodeproj`, not the root Swift package.
- The app target does not yet link the package products required by the chat screen.

## Decisions For This Slice

- Use the mock runtime only. Do not add a live OpenAI-compatible client yet.
- Remove the default SwiftData template from the app shell unless Xcode requires the files to remain temporarily.
- Keep persistence out of this slice.
- Keep navigation simple: one root chat route, no sidebar, no settings modal rendering unless needed for compile coverage.
- Build the real screen through `ChatRoutes.registration` and `Page(interactor:view:)`, not by directly instantiating `ChatPage`.

## Implementation Steps

1. Add the root Swift package to the Xcode workspace.
   - Update `Hephaestus.xcworkspace/contents.xcworkspacedata` so Xcode sees both `Hephaestus.xcodeproj` and `Package.swift`.
   - Prefer workspace-level package visibility over duplicating source files into the app target.

2. Link required SwiftPM products to the app target.
   - Required products are expected to be `Anvil`, `ChatFeature`, `HephaestusComposition`, and `HephaestusRuntime`.
   - `ChatContracts`, `HephaestusKernel`, and `HephaestusLLM` should arrive transitively unless Xcode requires explicit product linkage.

3. Replace the template app bootstrap.
   - Remove `SwiftData` imports and `ModelContainer` setup from `HephaestusApp`.
   - Replace the default `ContentView` root with an app shell view.
   - Keep `Item.swift` only if the Xcode project needs a separate cleanup step; otherwise remove it from the app target and repository.

4. Add `HephaestusAppShell`.
   - Own `Router<AnyRouteInput, AnyModalInput>`.
   - Own `DestinationRegistry`.
   - Own a simple dependency resolver backed by the mock runtime harness.
   - Construct `RouteBuildContext` with the router and dependency resolver.
   - On launch, push `ChatRouteInput(runID: nil)` through `AnyRouteInput`.

5. Render routes through the registry.
   - For the current root route, build the route view from the registry.
   - Keep error rendering explicit if route construction fails.
   - Avoid adding a full navigation stack abstraction until there is more than one real screen.

6. Validate app behavior.
   - Build the SwiftPM package with strict concurrency.
   - Build the macOS app target from Xcode or `xcodebuild`.
   - Run the app and verify mock streaming with at least two messages.

## Expected Files To Change

- `Hephaestus.xcworkspace/contents.xcworkspacedata`
- `Hephaestus.xcodeproj/project.pbxproj`
- `Hephaestus/HephaestusApp.swift`
- `Hephaestus/ContentView.swift` or a replacement app-shell file
- Possibly `Hephaestus/Item.swift` if removing the SwiftData template fully

## Validation Commands

```sh
CLANG_MODULE_CACHE_PATH="$PWD/.build/clang-module-cache" swift test -Xswiftc -strict-concurrency=complete -Xswiftc -warnings-as-errors
xcodebuild -workspace Hephaestus.xcworkspace -scheme Hephaestus -destination 'platform=macOS' build
CLANG_MODULE_CACHE_PATH="$PWD/.build/clang-module-cache" swift run HephaestusCLI "hello" "second"
```

## Risks

- Manual `project.pbxproj` edits are easy to get wrong. Keep the package-linking diff small and validate with `xcodebuild`.
- Xcode may require explicit package-product linkage even when SwiftPM dependencies are transitive.
- The app shell can become a hidden composition singleton if the dependency resolver is not kept local and explicit.
- If route rendering bypasses `DestinationRegistry`, the POC stops proving ADR-0005 and ADR-0006.

## Open Technical Questions

- Should the default SwiftData files be removed fully now, or only disconnected from the app shell in this slice?
- Should package product linkage be done manually in `project.pbxproj`, or should project state be regenerated through Xcode if manual edits become fragile?
- Should the local Xcode signing change be kept, reverted, or isolated from the app-shell commit?

## Not In This Slice

- OpenAI-compatible live provider.
- Chat persistence.
- Context compaction UI.
- Skills.
- Multi-agent workflows.
- Full navigation/sidebar design.
