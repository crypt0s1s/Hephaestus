# Hephaestus Modularization Objectives

## Purpose

This document captures the modularization direction needed to make Hephaestus compatible with the broader product vision: project-scoped work, task-based workflows, multiple harness backends, workflow creation, observability, and native UI surfaces that are not all shaped like chat.

The current app has useful package boundaries, but the implementation is still centered around the first chat slice. Future work should refactor toward smaller packages with clearer ownership, stable contracts, and explicit dependency direction.

## Current Problem

The current UI and runtime infrastructure proved the first loop, but it should not become the permanent shape of the app.

Current risks:

- `ChatFeature` owns too many concepts at once: chat UI, history sidebar, provider settings, run inspection, and session workspace behavior.
- The app shell is the composition root, runtime selector, dependency resolver, startup router, and provider settings adapter.
- Core concepts such as project, task, workflow, backend, role, skill, hook, artifact, and observation do not yet have clean package homes.
- Run inspection is currently embedded in chat instead of being a reusable observability surface.
- Provider selection and harness/backend selection are not yet separated.
- The app can grow by adding UI directly to the existing chat surface, which would make later extraction harder.

The goal is not to rewrite everything immediately. The goal is to make each new slice land in the package where it belongs.

## Modularization Goals

### 1. Separate Product Concepts From Feature Screens

Core product concepts should live in contract or domain packages, not inside SwiftUI features.

Examples:

- Project
- Task
- Run
- Workflow
- Backend
- Role
- Tool policy
- Skill
- Hook
- Artifact
- Observation event

Feature screens should render and manipulate these concepts through use cases and contracts. They should not define the app's central domain model privately.

### 2. Keep Foundry As One Backend, Not The Whole App

Foundry should become the native in-process runtime backend.

Hephaestus should own the meta-harness layer above Foundry, Codex CLI, Claude Code, and future adapters. That means Foundry runtime packages should not absorb workflow authoring, backend selection, external adapter diagnostics, or app-level task management.

### 3. Split Features By User Surface

Large UI surfaces should become separate feature packages.

Expected feature packages:

- Project workspace
- Task workspace
- Chat or conversation panel
- Workflow library and builder
- Run inspector
- Observability dashboard or panels
- Backend manager
- Profiles and roles
- Skills and hooks
- Artifacts
- Settings

Each feature should own its page/interactor/view state, but depend on smaller domain and use-case contracts for the underlying data.

### 4. Make Contracts Small And Stable

Every feature that can be opened by another feature should expose a small contract package.

Contract packages may contain:

- route inputs
- modal inputs
- destination IDs
- feature-facing use-case protocols
- lightweight state summaries
- stable identifiers

Contract packages should not contain concrete SwiftUI views, interactors, storage implementations, or backend adapters.

### 5. Separate Harness Backends From LLM Providers

LLM providers and harness backends are different concepts.

LLM provider examples:

- OpenAI-compatible endpoint
- mock provider
- future model service

Harness backend examples:

- Foundry
- Codex CLI
- Claude Code

The package model should preserve this distinction. A Codex CLI backend may itself choose a model and provider internally, while Foundry may use `HephaestusLLM` provider adapters directly.

### 6. Make Observability Reusable

Observability should be a shared subsystem, not a chat-only inspector.

Observation concepts should be available to:

- Foundry runs
- Codex CLI runs
- Claude Code runs
- workflow steps
- comparison tasks
- future replay/export features

The run inspector should consume normalized observation data rather than depending on chat-specific persisted state.

### 7. Preserve Dependency Direction

The app should compose modules, but modules should not depend back on the app.

Target direction:

```text
Hephaestus app target
  -> feature packages
  -> feature contract packages
  -> domain/use-case contract packages
  -> core runtime/domain packages

Feature packages
  -> Anvil
  -> design system packages
  -> contracts/use cases they need

Core runtime/domain packages
  -> no SwiftUI
  -> no Anvil
  -> no feature packages
```

## Target Package Families

### App And Composition

```text
HephaestusApp
HephaestusComposition
```

Responsibilities:

- app startup
- route registry composition
- dependency graph wiring
- default project/task selection
- concrete store selection
- feature installation

These packages should not own feature behavior.

### UI Foundation

```text
Anvil
HephaestusDesignSystem
```

Responsibilities:

- page/interactor primitives
- routing and modal infrastructure
- task scopes
- shared UI components
- theme, typography, spacing, panels, buttons, forms

`Anvil` should stay generic. `HephaestusDesignSystem` can be product-specific.

### Product Domain

```text
HephaestusProjects
HephaestusTasks
HephaestusWorkflows
HephaestusArtifacts
HephaestusObservation
```

Responsibilities:

- domain models
- identifiers
- state machines
- use-case protocols
- storage-facing contracts
- normalized events

These packages should avoid SwiftUI.

### Native Runtime Backend

```text
FoundryKernel
FoundryRuntime
FoundryLLM
FoundryTools
FoundryComposition
```

Responsibilities:

- native agent turn lifecycle
- context assembly
- provider request/response contracts
- tool execution boundary
- native runtime persistence hooks
- Foundry-specific composition

Existing `HephaestusKernel`, `HephaestusRuntime`, `HephaestusLLM`, and `HephaestusTools` can migrate toward this naming over time if the Foundry split is adopted.

### Harness Backend Adapters

```text
HephaestusHarness
CodexCLIBackend
ClaudeCodeBackend
FoundryBackend
```

Responsibilities:

- normalized harness request/result/event contracts
- backend capability matrix
- command construction
- process execution adapters
- backend event parsing
- backend health checks

The harness layer should understand tasks and runs, but not concrete SwiftUI pages.

### Feature Packages

```text
ProjectWorkspaceContracts
ProjectWorkspaceFeature

TaskWorkspaceContracts
TaskWorkspaceFeature

ConversationContracts
ConversationFeature

WorkflowBuilderContracts
WorkflowBuilderFeature

RunInspectorContracts
RunInspectorFeature

BackendManagerContracts
BackendManagerFeature

ProfilesContracts
ProfilesFeature

SkillsHooksContracts
SkillsHooksFeature

ArtifactsContracts
ArtifactsFeature
```

These can be introduced gradually. The key is to avoid letting one feature become the container for all app behavior.

## Suggested Refactor Sequence

### Phase 1: Document And Stabilize Boundaries

- Keep the current app working.
- Treat existing chat as a conversation feature, not the future app shell.
- Add domain docs for project, task, workflow, backend, and observation.
- Identify which current `ChatFeature` concepts belong elsewhere.

### Phase 2: Extract Reusable Inspector Concepts

- Move run inspection contracts out of chat-specific state.
- Define normalized observation events and summaries.
- Create a reusable run inspector feature or contract package.
- Keep the chat page using it through contracts.

### Phase 3: Introduce Project And Task Domain Packages

- Define project and task models.
- Make task the user-facing unit above chat/run.
- Create project/task route contracts.
- Let chat become a panel or mode inside task workspace.

### Phase 4: Introduce Harness Backend Contracts

- Define backend capability contracts.
- Define normalized harness run request/result/event.
- Model Foundry as a backend adapter.
- Add Codex CLI adapter later without changing the task UI model.

### Phase 5: Split Workflow Creation

- Define workflow recipe/spec contracts.
- Add workflow library/builder feature package.
- Support roles, tools, skills, hooks, approvals, and backend choices in the spec.
- Keep authoring UI separate from execution UI.

### Phase 6: Rename Native Runtime To Foundry If Adopted

- Rename packages only once the conceptual split is stable.
- Prefer compatibility shims or staged moves over a disruptive all-at-once rename.
- Keep `Hephaestus` reserved for the app/meta-harness.

## Near-Term Extraction Candidates

The current `ChatFeature` should eventually shed:

- provider settings -> backend/provider settings feature or settings package
- run inspector -> run inspector feature
- session list/sidebar -> project/task workspace feature
- chat session domain -> conversation/task domain package
- runtime event projection -> observation package

The remaining conversation package should focus on:

- transcript rendering
- composer
- interactive steering
- conversation-specific page state
- conversation panel route/input contracts

## Dependency Rules

- Feature packages may depend on `Anvil` and contracts.
- Feature packages should not import other concrete feature packages for navigation.
- Feature packages should not own global app state.
- Domain packages should not import SwiftUI.
- Backend adapters should not import SwiftUI.
- The app target should compose concrete dependencies but avoid implementing feature behavior.
- Runtime packages should not know about routes, pages, modals, or project dashboards.
- Observation should depend on normalized event contracts, not on chat UI state.

## Validation Questions

Before adding a new type or feature, ask:

- Is this a domain concept, feature render state, or adapter detail?
- Does this belong to Hephaestus meta-harness or Foundry native runtime?
- Will Codex CLI and Claude Code need an equivalent concept?
- Is this reusable outside chat?
- Does this need a route contract?
- Is this package importing a concrete feature only to navigate to it?
- Could this create a dependency cycle later?

## Success Criteria

The refactor direction is working when:

- Projects and tasks can exist without depending on chat.
- Chat can be rendered as a panel inside a task workspace.
- Run inspection can inspect non-chat runs.
- Foundry can be selected as one backend among others.
- Codex CLI can be added as a backend without rewriting the app shell.
- Workflow builder UI can configure roles, tools, skills, hooks, approvals, and backend choices without importing runtime implementation details.
- Core runtime packages compile without SwiftUI or feature package dependencies.
- The app target remains a composition root instead of a feature implementation bucket.

## Guiding Principle

Hephaestus should be modular by concept, not merely modular by folder.

Packages should reflect stable product and runtime boundaries: projects, tasks, workflows, backends, observation, artifacts, and conversation. The current chat app should become one feature within that system, not the system itself.
