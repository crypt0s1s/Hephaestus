# 0013. Visual Workflow Definition And Runtime Boundary

**Status:** Accepted
**Date:** 2026-05-11
**Deciders:** Hephaestus engineering
**Technical Story:** Define the durable model boundary that lets the visual workflow builder create execution-ready workflow definitions without making canvas state or backend launch details the source of truth.

---

## Context

PRD-0012 introduces a visual workflow builder for composing multi-agent Codex workflows as connected steps. The builder needs to support planning, implementation, review, terminal-assisted work, interactive collaboration, automated execution, loops, actor configuration, IO, skills, MCP/tool access, approvals, and artifact handoffs.

The current app has useful workflow prototypes, but they are built around app-owned runners, planning-specific interaction state, and timeline projections. Those types are not durable workflow authoring schema. If the builder stores only boxes, arrows, and canvas positions, Hephaestus will still need a later rewrite before workflows can execute reliably.

## Decision Drivers

* Workflow definitions must be durable project data, not transient SwiftUI canvas state.
* Visual arrows must correspond to typed control, data, artifact, decision, or approval handoffs.
* Loops need explicit stop conditions and human breakpoints.
* Actor/backend launch details must not leak into the graph schema.
* Skills, MCP servers, tools, sandbox posture, and approval requirements need machine validation.
* Runtime-owned messages, artifacts, decisions, pauses, and resume commands must have a clear future home.
* The first implementation can be Codex-first but should not make Codex the permanent graph model.

## Considered Options

### Option 1: Canvas-First Diagram Model

Store nodes, arrows, and editor layout directly, then infer runtime behavior later.

**Pros:**
- Fastest way to draw a visible builder.
- Minimal upfront schema work.

**Cons:**
- Creates a diagramming surface instead of an orchestration model.
- Makes loops, IO, approvals, capabilities, and artifacts ambiguous.
- Requires a later rewrite before reliable execution.

### Option 2: Durable Declarative Graph Definition

Store a versioned workflow definition with semantic nodes, links, loops, actors, IO declarations, capability scopes, and validation issues. Store canvas layout separately.

**Pros:**
- The builder edits the same data future execution can consume.
- Validation can run independently from SwiftUI.
- Backend-specific launch details can remain behind adapters.
- Explicit loops and handoffs avoid accidental semantics.

**Cons:**
- More upfront model design.
- First slice must define enough schema before runtime execution exists.

### Option 3: Swift Workflow Package First

Require workflow authors to define workflows in external Swift packages and make the visual builder a later projection of those packages.

**Pros:**
- Strong type system for complex mappings.
- Aligns with ADR-0012 for external Swift workflow packages.

**Cons:**
- Does not deliver visual authoring now.
- Makes simple graph editing dependent on a source-code workflow.
- Harder to validate builder UX and project-local recipes.

## Decision

Hephaestus will use a durable declarative graph definition as the source of truth for visual workflow builder authoring.

**Chosen Option:** Option 2 - Durable Declarative Graph Definition

The graph definition will contain semantic nodes, links, loops, actor profiles, IO declarations, capability scopes, approval policies, and schema version. Canvas layout, selection, pan, zoom, and transient gestures remain separate editor state.

Runtime execution will later consume validated graph definitions and materialize runtime-owned runs, pauses, resume commands, messages, artifacts, and decisions. Backend launch details, Codex CLI flags, raw event payloads, approval plumbing, and resume identifiers stay behind harness backend adapters and runtime state.

## Consequences

### Positive

- The builder creates real workflow definitions rather than disposable diagrams.
- Validation can catch malformed graphs, missing IO, unsafe capabilities, and unbounded loops before execution.
- Codex-first actor configuration can evolve toward additional backends.
- Planning, review, and implementation loop patterns can share one schema.
- Future runtime orchestration has a stable input model.

### Negative

- The first implementation must carry schema and validation work before full execution exists.
- Some schema choices may need migration as runtime pressure increases.
- Advanced typed mappings remain limited until a later runtime or package integration layer exists.

### Neutral

- Existing built-in workflows continue to run through current runners.
- ADR-0012 external Swift packages remain a complementary path for code-authored workflows.
- Arbitrary graph execution remains explicitly deferred until a later PRD/plan accepts it.

## Implementation

The first slice should add:

- a versioned `WorkflowGraphDefinition`,
- semantic `WorkflowNode`, `WorkflowLink`, `WorkflowLoop`, `WorkflowActorProfile`, IO, execution mode, approval, and capability types,
- a pure validator,
- reusable planning/review/implementation loop pattern definitions,
- project-local storage under `.hephaestus/workflows/`,
- a SwiftUI builder whose semantic source of truth is the graph definition,
- tests for encoding, validation, storage, and pattern validity.

## Validation

This decision is validated when:

- a workflow created from a reusable pattern can be saved and reopened,
- viewport/editor state is not required to restore graph semantics,
- invalid links, missing actors, missing start nodes, unbounded loops, and unresolved capability scopes produce structured validation issues,
- Codex-specific process launch data does not appear in graph nodes,
- the builder can show normalized definition JSON for future runtime consumption.

## Related Decisions

- [ADR-0004](0004-swiftui-interactor-page-architecture.md) - SwiftUI interactor page architecture.
- [ADR-0012](0012-external-swift-workflow-packages.md) - External Swift workflow packages.

---

**Last Updated:** 2026-05-11
