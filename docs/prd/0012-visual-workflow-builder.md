# PRD-0012. Visual Workflow Builder

**Status:** Draft
**Date:** 2026-05-11
**Owner:** Hephaestus engineering
**Related ADRs:** [ADR-0013. Visual Workflow Definition And Runtime Boundary](../adr/0013-visual-workflow-definition-and-runtime-boundary.md)
**Related Plans:** [Plan-0013. Visual Workflow Builder Technical Design](../plans/0013-visual-workflow-builder-technical-design.md)

---

## Summary

Add a graphical workflow builder that lets users visually compose multi-agent Codex workflows as connected steps. Users should be able to create steps, link them together, configure repeated loops, assign each step a role and actor, declare instructions and IO, scope allowed skills and MCP/tool access, and mark where user interaction or approval is required before execution continues.

The builder is not just a diagramming surface. It should create durable workflow definitions that can later be validated, persisted, inspected, and executed by a real orchestration runtime without rewriting the core model.

## Problem

Hephaestus is moving from single workflow prototypes toward reusable multi-agent workflow composition. Current workflow behavior is mostly represented by built-in runners, prototype-specific state, and timeline projections. That makes it hard for a user to:

- see how planning, implementation, review, terminal-assisted work, interactive collaboration, and automated execution fit together,
- reuse patterns such as planning loops, implementation loops, and review loops,
- understand which steps run automatically and which require user approval,
- control which actor, instructions, artifacts, skills, MCP servers, and tools each step can use,
- reason about how outputs and decisions flow from one step to the next,
- evolve a visual workflow into reliable runtime execution.

Without a durable workflow definition model, a visual builder risks becoming a box-and-arrow mockup that cannot safely execute real multi-agent workflows.

### Background

Existing docs intentionally deferred the full workflow builder while Hephaestus proved the kernel, harness, run inspection, nested workflow timeline, and interactive planning review workflow. The latest planning-review work has already identified the concepts that a builder-ready model needs next: first-class workflow runs, pauses, resume commands, durable workflow messages, event projection, runtime-owned artifacts, and a cleaner separation between UI state and orchestration state.

This PRD defines the product slice for that next layer.

### Users And Jobs

| User | Job To Be Done | Current Pain | Usage Context |
| --- | --- | --- | --- |
| Workflow author | Compose a reusable Codex workflow from roles, steps, loops, and handoffs | Built-in workflows are hardcoded and cannot be authored visually | Creating project-local workflow recipes |
| Hephaestus operator | Understand what will run automatically and where user approval is required | Automation boundaries are hidden in runner code or logs | Reviewing a workflow before running it |
| Agent-system builder | Model planning, implementation, review, and interaction patterns without coupling to one prototype | Prototype state mixes UI, execution, artifacts, and backend details | Designing durable orchestration primitives |
| Reviewer or approver | See which artifacts, decisions, and outputs gate the next step | Handoffs are difficult to inspect before continuing | Paused approval or review checkpoints |
| Backend/tool integrator | Scope actor capabilities and tool access per step | Tool and harness access are not represented as workflow definition data | Adding Codex, MCP, skills, and future backend adapters |

## Product Outcome

Users can create and inspect a project-scoped workflow graph where each node represents an executable or interactive workflow step and each edge represents a typed dependency or control handoff. The first usable slice should make workflow structure, loop behavior, actor responsibilities, IO contracts, approval gates, and tool/skill access explicit enough that the workflow can be validated before execution.

The workflow definition produced by the builder should be durable product data, not view state. Later execution should consume that same definition through a runtime orchestration layer.

### Success Metrics

| Metric | Baseline | Target | Measurement Method |
| --- | --- | --- | --- |
| Authorable workflow graph | No visual authoring surface | User can create, connect, save, reopen, and validate a workflow graph | Manual app validation and model tests |
| Runtime-ready definition | Built-in/prototype runner state | Saved definition includes steps, links, loops, actors, IO, gates, and capabilities | Definition validation tests |
| Automation clarity | Automation and approval boundaries are implicit | Builder visibly marks automated, interactive, approval-gated, and separate-Codex-instance work | UX review against acceptance criteria |
| Reusable patterns | Loops are hardcoded per workflow | User can start from planning, review, or implementation loop patterns and customize them | Manual app validation |

## Scope Boundaries

### In Scope

- A graphical editor for creating workflow steps and links.
- Step roles for planning, implementation, review, terminal-assisted work, interactive Codex collaboration, and automated execution.
- Step configuration for actor, instructions, inputs, outputs, allowed skills, MCP/tool access, sandbox/permission posture, and interaction requirements.
- Visual distinction between automated steps, user-approval gates, interactive collaboration steps, terminal-assisted steps, and steps that run in separate Codex instances.
- Reusable workflow patterns for planning loops, review loops, and implementation loops.
- Loop configuration for bounded repeat counts, repeat-until conditions, review/fix cycles, and human breakpoints.
- Durable workflow definition data that is separate from editor selection/viewport state.
- Validation that detects malformed graphs, missing step configuration, impossible loops, unresolved IO, and unsafe capability requests.
- First-slice save/reopen behavior for project-scoped workflow definitions.
- Runtime-oriented concepts for artifacts, decisions, messages, and handoffs, even if full execution is deferred.

### Out Of Scope

- Full production execution of every user-authored workflow in the first builder slice.
- A marketplace or sharing system for workflow templates.
- Multi-user collaborative editing.
- Automatic synthesis of workflows from natural language.
- Rich analytics across historical workflow runs.
- Supporting every backend on day one; Codex is the first target actor family.
- Replacing existing built-in workflow runners immediately.

### Deferred

- Full workflow execution, retry, cancellation, and resume controls for arbitrary custom graphs.
- Versioned workflow migrations and compatibility policy.
- Template publishing and import/export beyond project-local files.
- Visual diffing between workflow definition versions.
- Advanced graph layout, minimap, grouping, and nested subworkflow editing.
- Policy-driven organization-wide skill/MCP/tool allowlists.
- Execution simulation with cost/time estimates.

### Scope Creep Watchlist

- Building a polished diagramming product before the definition model is executable.
- Letting canvas state become the source of truth for workflow behavior.
- Modeling loops as informal back edges without explicit runtime semantics.
- Treating tool access as free-form text instead of validated capability scopes.
- Letting prototype planning-review concepts become global models without renaming and separating responsibilities.

## User Experience

### Primary Flow

1. User opens the workflow builder for a selected project.
2. User creates a workflow from an empty canvas or a reusable pattern.
3. User adds steps and assigns each step a role.
4. User configures actor, instructions, inputs, outputs, skills, MCP/tool access, and interaction requirements for each step.
5. User connects steps to define control flow and data/artifact handoffs.
6. User wraps selected steps in a loop or inserts a loop pattern.
7. Hephaestus validates the workflow and highlights missing or unsafe configuration.
8. User saves the workflow as a project-scoped durable definition.
9. User reopens the workflow and sees the same executable structure, not just the previous canvas layout.

### First Usable Product Slice

The first usable slice should be a builder-and-validation slice, not a full arbitrary graph executor:

- create a new workflow definition,
- insert one of three reusable patterns: planning loop, review loop, or implementation loop,
- edit step labels, roles, actors, instructions, IO names, capability scopes, and interaction gates,
- connect or disconnect steps within a bounded graph,
- configure loop bounds and stop conditions,
- save and reopen the workflow definition,
- run validation and see actionable errors,
- export or inspect the normalized workflow definition that future runtime execution will consume.

This slice is useful if it lets Hephaestus authors design durable workflows and catch model problems before execution exists.

### Core Concepts

- **Workflow definition:** Durable graph data containing metadata, steps, links, loops, actor assignments, IO contracts, capability scopes, validation state, and version information.
- **Step:** A unit of work with a role, actor, instruction body, input bindings, output declarations, execution mode, and capability policy.
- **Role:** The intent of the step, such as planning, implementation, review, terminal-assisted work, interactive Codex collaboration, or automated execution.
- **Actor:** The backend and agent profile that performs the step, initially Codex-oriented and later extensible to Foundry, Claude Code, OpenCode, Gemini, or ACP adapters.
- **Execution mode:** Whether a step runs automatically, pauses for user interaction, requires approval, assists with terminal work, or runs in a separate Codex instance.
- **Link:** A directed connection that carries control, data, artifacts, decisions, or approval state from one step to another.
- **Loop:** An explicit structure that repeats a contained step sequence with bounded count, repeat-until condition, review/fix semantics, and breakpoints.
- **Artifact reference:** A runtime-owned reference to files, plans, review feedback, decisions, messages, or other outputs passed between steps.
- **Capability scope:** The declared skills, MCP servers, tools, sandbox posture, and permission grants allowed for a step.
- **Validation issue:** A product-visible problem that must be fixed or acknowledged before execution is allowed.

### Edge And Failure States

- Empty workflow shows an authoring surface with pattern starters.
- A workflow with no start step cannot be marked runnable.
- A step without required role, actor, instructions, or IO configuration is visibly incomplete.
- A link with no compatible output/input binding is invalid.
- A loop with no exit condition or unbounded repeat count is invalid for first-slice execution readiness.
- A step requesting skill, MCP, or tool access outside project policy is blocked or clearly marked as requiring approval.
- A workflow that requires user interaction must show where execution pauses and what user action resumes it.
- Conflicting changes while editing must not corrupt the durable definition; first slice may use last-write-wins with a visible reload warning.
- Unsupported runtime execution should be explicit: the builder may save and validate definitions even when arbitrary execution is not yet available.

## Functional Requirements

- **FR-1:** The system must provide a graphical workflow builder for a selected project.
- **FR-2:** The builder must let users create, edit, delete, and link workflow steps.
- **FR-3:** Each step must support role assignment for planning, implementation, review, terminal-assisted work, interactive Codex collaboration, and automated execution.
- **FR-4:** Each step must support actor, instruction, input, output, allowed skill, MCP/tool access, sandbox/permission, and interaction-gate configuration.
- **FR-5:** The builder must visually distinguish automated steps, approval-gated steps, interactive steps, terminal-assisted steps, and separate-Codex-instance steps.
- **FR-6:** The model must represent links as explicit control/data/artifact/decision handoffs rather than visual-only arrows.
- **FR-7:** The model must support reusable planning loop, review loop, and implementation loop patterns.
- **FR-8:** The model must represent loop semantics explicitly, including bounds, stop conditions, iteration inputs/outputs, and user breakpoints.
- **FR-9:** The workflow definition must be durable project-scoped data separate from visual editor state.
- **FR-10:** The builder must validate workflow definitions and surface actionable issues before execution.
- **FR-11:** The design must separate visual editor, workflow definition model, runtime orchestration, actor/tool configuration, artifact storage, and validation rules.
- **FR-12:** The workflow model must preserve a path to reliable execution by representing workflow pauses, approvals, messages, artifacts, actor instances, and step outputs as runtime-owned concepts.
- **FR-13:** The first usable slice must let users save, reopen, validate, and inspect a workflow definition created from a reusable loop pattern.
- **FR-14:** The technical design must explain how Codex-first actor configuration can evolve toward additional harness backends without changing the workflow definition model.

## Acceptance Criteria

- **AC-1.1** (`FR-1`): Given a project is selected, when the user opens workflow authoring, then a graphical builder surface is available.
- **AC-2.1** (`FR-2`): Given the builder is open, when the user adds two steps and connects them, then both steps and the directed link appear in the workflow definition.
- **AC-2.2** (`FR-2`): Given a step is deleted, then links that reference that step are removed or reported as validation issues before save.
- **AC-3.1** (`FR-3`): Given a step is selected, when the user changes its role, then the definition records one of the supported step roles.
- **AC-4.1** (`FR-4`): Given a step is selected, then the user can configure actor, instructions, inputs, outputs, allowed skills, MCP/tool access, permissions, and interaction requirements.
- **AC-5.1** (`FR-5`): Given a workflow contains automated, approval-gated, interactive, terminal-assisted, and separate-instance steps, then the builder visually distinguishes those execution modes.
- **AC-6.1** (`FR-6`): Given a user connects an output-producing step to an input-consuming step, then the saved definition records the link type and IO binding, not just canvas coordinates.
- **AC-7.1** (`FR-7`): Given the user starts from a reusable pattern, when the user chooses planning loop, review loop, or implementation loop, then the builder creates an editable workflow graph with the expected steps and loop structure.
- **AC-8.1** (`FR-8`): Given a loop is selected, then the user can inspect and edit bounded repeat count, stop condition, iteration handoffs, and user breakpoints.
- **AC-9.1** (`FR-9`): Given a workflow is saved and reopened, then steps, links, loop semantics, actor configuration, IO, and capability scopes are restored independently of viewport position.
- **AC-10.1** (`FR-10`): Given a workflow has no start step, unresolved IO binding, missing actor, unsafe capability request, or loop with no exit condition, then validation reports actionable issues.
- **AC-10.2** (`FR-10`): Given validation has blocking issues, then arbitrary execution is disabled or marked unavailable.
- **AC-11.1** (`FR-11`): Given the technical design is reviewed, then it identifies separate ownership boundaries for visual editing, definition data, orchestration runtime, actor/tool configuration, artifact storage, and validation.
- **AC-12.1** (`FR-12`): Given a step requires interaction or approval, then the definition records the pause/resume requirement and the expected resume command or decision output.
- **AC-12.2** (`FR-12`): Given a step produces artifacts or decisions, then the definition records durable output declarations that can be bound to later inputs.
- **AC-13.1** (`FR-13`): Given the first slice is implemented, then a user can create a workflow from a loop pattern, edit it, save it, reopen it, validate it, and inspect the normalized definition.
- **AC-14.1** (`FR-14`): Given the technical design is reviewed, then Codex actor settings are modeled through actor/backend capability declarations rather than hardcoded directly into graph nodes.

## Dependencies

- Existing selected-project model and project-local storage direction.
- Existing `WorkflowDefinition`, `WorkflowStepDefinition`, `WorkflowRunProgress`, `WorkflowInteractionState`, and timeline projection concepts.
- Existing harness backend adapter direction and Codex adapter.
- Existing planning-review workflow lessons around interactive pauses, runtime-owned outputs, and `.hephaestus/` artifact materialization.
- Anvil design tokens and SwiftUI interactor page architecture for the authoring UI.
- A technical design that chooses the first durable workflow definition schema and validation boundary.

## Product Risks

- The builder could overfit to current planning-review prototype fields instead of introducing a workflow-wide definition model.
- A graph UI could make invalid workflows easy to draw and hard to explain.
- Loop behavior could become ambiguous if represented only by back edges.
- Capability scoping could be too vague to enforce at runtime later.
- Users may expect execution immediately after authoring unless the first slice clearly separates validated definitions from full arbitrary execution.
- Saving project-local workflow definitions introduces versioning and migration pressure.
- Actor configuration could leak Codex-specific assumptions into otherwise reusable workflow definitions.

## Technical Design Gate

PRDs define product need and product constraints. ADRs record durable architectural choices. Technical designs or implementation plans in `docs/plans/` describe how an accepted PRD will be built.

| Field | Value |
| --- | --- |
| Separate technical design required? | Yes |
| Rationale | The builder requires durable graph modeling, loop semantics, actor/tool capability scoping, validation, storage, SwiftUI editor architecture, and a path to runtime orchestration. |
| Plan link | [Plan-0013. Visual Workflow Builder Technical Design](../plans/0013-visual-workflow-builder-technical-design.md) |
| Blocks implementation until resolved? | Yes |
| Owner | Hephaestus engineering |

### Product Constraints For Technical Design

- The saved workflow definition must be independent of canvas selection, pan, zoom, and transient editor state.
- Visual links must correspond to typed control/data/artifact/decision handoffs in the workflow definition.
- Loops must be explicit model objects or subgraphs with defined runtime semantics, not unstructured cycles.
- Actor, skill, MCP, tool, sandbox, and approval requirements must be machine-validated.
- Interactive and approval-gated steps must have explicit pause/resume and decision-output semantics.
- The first slice may be Codex-first, but backend-specific launch details must remain behind actor/backend configuration boundaries.
- Runtime-owned artifacts, messages, decisions, and step outputs must be modeled separately from exported files.
- The UI must follow ADR-0004: state in, action out, with side effects in an interactor/model.

### Open Technical Questions

| Question | Owner | Blocks Implementation? | Resolve In PRD/ADR/Plan | Resolution |
| --- | --- | --- | --- | --- |
| What exact persisted schema should project-local workflow definitions use? | Hephaestus engineering | Yes | Plan/ADR | Proposed in Plan-0013; ADR may be needed before implementation. |
| Should loops be represented as first-class nodes, graph regions, or structured subgraphs? | Hephaestus engineering | Yes | Plan/ADR | Proposed in Plan-0013. |
| What is the first capability policy format for skills, MCP servers, tools, and sandbox posture? | Hephaestus engineering | Yes | Plan | Proposed in Plan-0013. |
| How much arbitrary graph execution is included in the first slice? | Hephaestus engineering | Yes | PRD/Plan | PRD limits first slice to authoring, validation, persistence, and normalized definition inspection. |
| Does the workflow definition model require an ADR before implementation? | Hephaestus engineering | Yes | ADR | Plan-0013 recommends an ADR for the durable definition and runtime boundary. |

## Milestones

| Milestone | Outcome | Included FRs | Excluded Scope | Exit Criteria | Dependencies |
| --- | --- | --- | --- | --- | --- |
| M1 | Durable definition and validation model | FR-3, FR-4, FR-6, FR-8, FR-9, FR-10, FR-11, FR-12, FR-14 | Graph canvas polish, arbitrary execution | Schema, validator, pattern definitions, and storage approach are accepted | Technical design and likely ADR |
| M2 | Builder authoring slice | FR-1, FR-2, FR-5, FR-7, FR-9, FR-10, FR-13 | Full execution runtime | User can create from a loop pattern, edit, save, reopen, validate, and inspect normalized definition | M1 |
| M3 | Execution-readiness bridge | FR-10, FR-11, FR-12, FR-14 | Full arbitrary runtime execution | Valid definitions can be translated into runtime planning objects or an execution preview without executing all steps | M2 and runtime design |

## Validation Plan

### Pre-Implementation Validation

- Review Plan-0013 against this PRD.
- Decide whether to add an ADR for the durable workflow definition and orchestration boundary.
- Validate reusable loop pattern definitions against planning-review and implementation-review workflows.
- Prototype the normalized definition shape with sample planning loop, review loop, and implementation loop fixtures.

### Implementation Validation

- Add model tests for workflow definition encoding/decoding, graph validation, IO binding validation, loop validation, and capability-scope validation.
- Add interactor tests for create, edit, link, delete, save, reopen, and validate actions.
- Add SwiftUI previews or manual fixtures for empty workflow, planning loop, review loop, implementation loop, validation errors, and read-only execution-unavailable state.
- Build the macOS app.

### Ship Criteria

- A user can author a workflow from a reusable loop pattern.
- Saved workflow definitions restore graph semantics, step configuration, loop semantics, IO, and capability scopes.
- Validation catches blocking graph, loop, actor, IO, and capability problems.
- The technical design and any required ADRs make the definition model clearly separate from the editor and runtime.
- Full arbitrary execution remains visibly deferred unless a later PRD/plan accepts it.

## Open Questions

| Question | Owner | Blocks Implementation? | Resolve In PRD/ADR/Plan | Resolution |
| --- | --- | --- | --- | --- |
| Should project-local workflow files live under `.hephaestus/workflows/` or source-controlled docs/config paths? | Hephaestus engineering | Yes | Plan/ADR | Plan-0013 recommends `.hephaestus/workflows/` for app-owned definitions with optional export later. |
| Should workflow patterns be built in code first or stored as bundled definition fixtures? | Hephaestus engineering | No | Plan | Plan-0013 recommends bundled definition fixtures once schema stabilizes. |
| Should M2 include drag-and-drop layout or simpler click-to-add/link interactions first? | Hephaestus engineering | No | Plan/UI implementation | TBD during UI implementation. |
| How should user-authored definitions be versioned before schema stability? | Hephaestus engineering | Yes | ADR/Plan | Plan-0013 proposes explicit schema version plus limited migration support. |

---

## Notes

This PRD intentionally keeps full arbitrary workflow execution out of the first usable slice. The immediate product value is making workflow structure, loops, actors, IO, approvals, and capabilities explicit as durable data that future runtime execution can trust.

**Last Updated:** 2026-05-11
