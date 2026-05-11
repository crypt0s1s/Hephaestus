# AGENTS.md

## Project Guidance

Hephaestus uses source-controlled planning artifacts for feature work. Before creating or implementing a feature, follow the feature creation and development flow:

- [Feature Creation And Development Flow](docs/workflows/feature-creation-and-development-flow.md)

In short:

- Start with a PRD when the product capability, user value, scope, or acceptance criteria are not already defined.
- Add a technical design or implementation plan only after the PRD establishes the product slice.
- Add an ADR when the work needs a durable architecture decision or changes a long-lived system boundary.
- Prefer complete solutions over bandaid fixes. Hephaestus is an early-stage project, so avoid preserving legacy code, compatibility layers, or outdated concepts unless the user explicitly asks for them.
- When a refactor would produce the better long-term shape, propose it in the implementation plan. Refactors should be total within the affected concept or boundary, not partial patches that leave competing old and new patterns in place.
- Implement only after the PRD and any required design/ADR gates are resolved, then validate against the PRD acceptance criteria.

## Prototype And Mocking Frame

It is acceptable to mock behavior while building early workflow slices, but mocks must be shaped so they can be replaced by the real building blocks later.

- Keep mocks behind explicit interfaces, adapters, or test/support implementations. Do not mix mock behavior into production core files.
- Name temporary hardcoded implementations honestly, such as `PlanningReviewPrototype...` or `...Fixture`, when they are not meant to become the general architecture.
- Preserve separation of concerns even in prototypes: UI state, runtime orchestration, backend calls, artifact storage, validation, and workflow definitions should have distinct owners.
- Avoid letting a happy-path spike define generic models by accident. If a model is planning-specific, keep it in the planning feature; if it is meant to be reusable, keep planning-specific prompts, paths, and validation out of it.
- Prefer replaceable seams over broad abstractions. A small concrete protocol or service boundary is enough when it lets the mocked piece be swapped for the real implementation later.
- Before adding hardcoded prompts, file paths, agent names, or validation rules, place them in a feature-specific component and make the temporary nature clear in the type or file name.
- Review prototype code for migration pressure: the next implementation should replace one component, not untangle behavior spread across the model, view, runner, and backend adapter.

Use existing repository templates and indexes:

- [PRD Template](docs/prd/template.md)
- [ADR Template](docs/adr/template.md)
- [PRDs Index](docs/prd/README.md)
- [Docs Index](docs/README.md)

## UI Development Standards

Follow [ADR-0004. SwiftUI Interactor Page Architecture](docs/adr/0004-swiftui-interactor-page-architecture.md) for SwiftUI feature work.

- Page views should render data and emit actions: `state` in, `action` out.
- Put action enums and action processing with the interactor/model that handles them, not in the rendering view file.
- Name the action sink `action` unless an existing local convention is more specific.
- Keep SwiftUI view bodies shallow. A parent body should read like a table of contents for the screen or section.
- Split views by responsibility when a block combines multiple concepts, such as header plus controls, list container plus row rendering, or editor plus submission state.
- Prefer dedicated small `View` structs over large nested `@ViewBuilder` properties when the section has its own inputs, bindings, state, or repeated rows.
- Keep side effects, async work, runtime calls, and workflow submission behavior out of views. Views should call the action sink only.
- Keep lifecycle separate from actions. Use interactor/model lifecycle methods for `onAppear` and `onDisappear`.
- Use Anvil theme tokens and existing UI primitives before adding custom styling.
- Preserve stable accessibility identifiers for UI-testable controls and workflow states.

Repo-local agent guidance:

- [Running Tests](docs/workflows/running-tests.md): use before running or triaging app builds, unit tests, or macOS UI tests. A matching user-level agent skill exists at `/Users/bytedance/.agents/skills/hephaestus-running-tests/SKILL.md`.
