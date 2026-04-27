# Hephaestus

Hephaestus is an early-stage native macOS agent harness. The current focus is proving a single-agent chat loop with a clean runtime boundary before expanding into persistence, richer context management, skills, run inspection, and eventually multi-agent workflows.

## Current State

- Native SwiftUI macOS app shell.
- Swift Package workspace containing the runtime and feature modules.
- Mock streaming chat flow for local validation.
- OpenAI-compatible live provider planning docs.
- PRD, ADR, technical design, and subagent review workflow docs.

## Project Structure

```text
Apps/                  Headless executable entrypoints
Core/                  Shared architecture, runtime, provider, and composition modules
Features/              Feature packages such as chat
Hephaestus/            Native macOS app target
Tests/                 Swift package tests
docs/                  Vision, roadmap, PRDs, ADRs, plans, and workflows
```

## Requirements

- macOS
- Xcode with Swift 5.9+ support

## Validate

Run the package tests:

```sh
CLANG_MODULE_CACHE_PATH="$PWD/.build/clang-module-cache" swift test -Xswiftc -strict-concurrency=complete -Xswiftc -warnings-as-errors
```

Run the headless mock chat smoke test:

```sh
CLANG_MODULE_CACHE_PATH="$PWD/.build/clang-module-cache" swift run HephaestusCLI "hello" "second"
```

Build the macOS app locally without requiring a signing certificate:

```sh
xcodebuild -workspace Hephaestus.xcworkspace -scheme Hephaestus -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO build
```

## Documentation

- [Vision](docs/vision.md)
- [Roadmap](docs/roadmap.md)
- [PRDs](docs/prd/README.md)
- [ADRs](docs/adr)
- [Plans](docs/plans)
- [Workflows](docs/workflows/README.md)

## License

MIT. See [LICENSE](LICENSE).
