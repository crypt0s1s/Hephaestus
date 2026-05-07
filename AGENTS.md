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

Use existing repository templates and indexes:

- [PRD Template](docs/prd/template.md)
- [ADR Template](docs/adr/template.md)
- [PRDs Index](docs/prd/README.md)
- [Docs Index](docs/README.md)
