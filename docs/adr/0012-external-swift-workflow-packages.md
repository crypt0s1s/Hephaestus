# 0012. External Swift Workflow Packages

**Status:** Proposed
**Date:** 2026-05-05
**Deciders:** Joshua Sumskas, Codex
**Technical Story:** Define how Hephaestus can move from built-in workflow POCs toward user-editable, reusable workflow packages without dynamically loading arbitrary Swift code into the app process.

---

## Context

Hephaestus now has an Implementation Review Loop POC: one implementer agent follows a markdown plan, a build runs after implementation/fix phases, two reviewers inspect the patch, and blocking findings feed back into the implementer. The POC is useful, but it is still mostly an app-owned procedural flow with text prompts and text parsing.

The next design pressure is workflow authoring. We want workflows to become reusable building blocks that users can customize and eventually edit from inside the app. At the same time, the most expressive way to model mappings, gates, loops, typed inputs, typed outputs, and reusable steps may be an actual programming language, not a YAML-style workflow DSL.

Swift is attractive because Hephaestus is already a Swift/macOS app, and because typed workflow definitions, typed step inputs/outputs, and mapping closures are natural in Swift. However, letting users write Swift that is dynamically loaded into the app process creates signing, sandboxing, dependency, versioning, security, and crash-isolation problems.

### Problem Statement

Hephaestus needs a path toward user-authored workflows and reusable workflow components while preserving a stable app/runtime boundary, inspectable UI events, and safe-enough execution semantics for early local development.

### Goals

- Let workflows eventually live outside the main app target.
- Keep workflow authoring expressive enough for typed inputs, outputs, mappings, loops, gates, and reusable steps.
- Avoid dynamically loading arbitrary user Swift into the Hephaestus app process.
- Give the app a stable protocol for discovering, describing, validating, running, and inspecting workflows.
- Let built-in workflows and external workflows share the same event and display model.
- Start with a constrained spike rather than a full plugin ecosystem.

### Non-Goals

- Build a full visual workflow editor now.
- Build a package marketplace, dependency resolver, signing model, or trust system now.
- Support arbitrary YAML/JSON workflow authoring for complex control flow in this slice.
- Hot-load Swift modules into the running app process.
- Define a final public API for third-party workflow packages.

---

## Decision Drivers

* Workflow steps need explicit input/output contracts rather than unstructured text blobs.
* Review gates need deterministic pass/fail criteria owned by Hephaestus, not by agent prose.
* Mapping one step output into another step input is a first-class workflow concern.
* Swift gives strong type checking and a natural home for mappings and reusable step composition.
* User-authored code should not run inside the app process for the first extensibility model.
* The UI needs a stable event stream independent of how the workflow is implemented internally.
* We need to learn from a small external-package spike before committing to a workflow DSL or editor.

---

## Considered Options

### Option 1: Built-In Swift Workflows Only

**Description:** Keep all workflow definitions inside the Hephaestus app target or internal Swift packages. Users can run shipped workflows but cannot author their own without rebuilding the app.

**Pros:**
- Strong type safety.
- Simple debugging inside the app codebase.
- No plugin discovery, process protocol, or external toolchain management.
- Good for proving the first workflow runtime and UI model.

**Cons:**
- Does not support user-authored workflows.
- Risks baking POC workflow shapes into the app.
- Makes reusable workflow packages and an eventual ecosystem harder to explore.
- Forces every workflow update through app development and release.

### Option 2: Dynamic In-Process Swift Plugins

**Description:** Let users provide Swift packages or compiled bundles that Hephaestus loads into the app process at runtime.

**Pros:**
- User-authored Swift can call native APIs directly.
- Potentially fast once compiled.
- Could feel like a first-class plugin system.

**Cons:**
- High complexity around code signing, sandboxing, ABI stability, crash isolation, permissions, dependency resolution, and app-store-style trust.
- User code can crash or hang the app process.
- Harder to constrain filesystem and process access.
- Premature for the current POC stage.

### Option 3: Declarative Workflow DSL First

**Description:** Define workflows in JSON, YAML, TOML, or another declarative format consumed directly by the app.

**Pros:**
- Easy to edit in-app.
- Easier to validate and sandbox than arbitrary code.
- Good fit for simple linear workflows.
- Could become a visual-editor backing format.

**Cons:**
- Mappings, loops, parallelism, typed data transforms, and reusable abstractions become a language-design problem quickly.
- Complex workflows may require expression syntax, functions, imports, error handling, and versioning.
- Risk of inventing a worse programming language before we understand the runtime model.

### Option 4: External Swift Workflow Packages Run Out-Of-Process

**Description:** Workflows may be authored as Swift packages that expose a small command surface. Hephaestus discovers them via explicit manifests, asks them to describe/validate themselves, and runs them as child processes that emit structured JSON/JSONL events.

**Pros:**
- Keeps Swift authoring and type checking.
- Avoids loading arbitrary user Swift into the app process.
- Gives the app a narrow, inspectable boundary.
- Lets external workflows crash, hang, or fail without taking down the UI process.
- Allows built-in and external workflows to converge on the same metadata and event contracts.
- Enables early experimentation with external workflow shape before committing to an editor or ecosystem.

**Cons:**
- Requires a local Swift toolchain for external workflow authors.
- Startup and build times may be slower than in-process execution.
- Requires a process protocol, manifest format, and version compatibility story.
- User-authored code still runs locally, so permissions and trust are not solved by this alone.
- In-app editing of Swift workflows remains a later, harder problem.

---

## Decision

Hephaestus will pursue external Swift workflow packages as the preferred extensibility direction, but only as an out-of-process runtime boundary.

Built-in workflows may remain in the app while the workflow model is still forming. However, new workflow contracts should be shaped so built-in workflows and external Swift workflow packages can share:

- workflow descriptions,
- input definitions,
- step descriptions,
- run input payloads,
- structured run events,
- review/build/result objects,
- debug-log pointers, and
- completion summaries.

Hephaestus will not dynamically load user Swift packages into the app process for v1.

**Chosen Option:** Option 4 - External Swift Workflow Packages Run Out-Of-Process

### Rationale

This option preserves Swift as the expressive authoring language for complicated workflow logic while keeping the app/runtime boundary explicit. A process boundary lets Hephaestus supervise external workflows, stream events, capture logs, enforce timeouts, and recover from crashes without turning the app into a plugin loader.

The workflow package should expose a small command surface, for example:

```bash
swift run ImplementationReviewWorkflow describe
swift run ImplementationReviewWorkflow validate
swift run ImplementationReviewWorkflow run --input /path/to/input.json
```

`describe` returns workflow metadata:

```json
{
  "id": "implementation-review",
  "name": "Implementation Review Loop",
  "version": "0.1.0",
  "inputs": [
    { "id": "planPath", "type": "string", "label": "Plan path" },
    { "id": "buildCommand", "type": "string", "label": "Build command", "default": "swift build" }
  ],
  "steps": [
    { "id": "implement", "title": "Implement plan" },
    { "id": "build", "title": "Build" },
    { "id": "review-a", "title": "Reviewer A" },
    { "id": "review-b", "title": "Reviewer B" },
    { "id": "gate", "title": "Review gate" }
  ]
}
```

`run` emits JSON Lines events:

```jsonl
{"type":"workflowStarted","runID":"...","workflowID":"implementation-review"}
{"type":"stepStarted","stepID":"implement","title":"Implement plan"}
{"type":"stepFinished","stepID":"implement","status":"succeeded","summary":"Changed 3 files."}
{"type":"stepStarted","stepID":"review-a","title":"Reviewer A"}
{"type":"reviewResult","stepID":"review-a","status":"needsChanges","findings":[...]}
{"type":"workflowFinished","status":"failed","summary":"Reviewer A reported blocking findings."}
```

The app renders these events. It does not need to understand the workflow package's internal Swift graph to show progress, details, debug logs, or final status.

---

## Consequences

### Positive

- Workflow definitions can eventually live outside the app.
- Swift remains available for typed mapping and reusable step composition.
- The app gets a stable process/event protocol instead of a plugin ABI.
- Built-in workflows can migrate toward the same contracts incrementally.
- The first external workflow spike can validate discovery, metadata, inputs, and event streaming before real Codex/build/review work moves out.

### Negative

- External workflows require process management and JSON/JSONL protocol handling.
- Running external Swift packages may require local toolchain setup and first-run compilation.
- The app must handle malformed metadata, malformed events, nonzero exits, hangs, and version mismatches.
- Package trust, signing, dependency policy, and editing UX remain unsolved.

### Neutral

- Built-in workflows remain valuable for core shipped flows.
- External packages may initially be examples in the repo rather than user-installed packages.
- A declarative or visual editor may still emerge later, possibly generating Swift or a constrained intermediate model.

---

## Implementation

### Initial Package Shape

Start with an example package outside the app target:

```text
AgentPlayground/
  Hephaestus/
  HephaestusExampleWorkflows/
    Package.swift
    HephaestusWorkflow.toml
    Sources/
      ImplementationReviewWorkflow/
        main.swift
```

The package should first implement `describe`, `validate`, and a fake `run` that emits deterministic events. It should not call Codex or run builds in the first spike.

### Manifest

Use an explicit manifest to avoid scanning arbitrary folders as executable workflow code:

```toml
id = "implementation-review"
name = "Implementation Review Loop"
version = "0.1.0"
runtime = "swift-package"
entry = "ImplementationReviewWorkflow"
```

Hephaestus should only discover workflows from:

- built-in registered workflows,
- app-configured workflow roots, or
- user-selected workflow folders with stored access.

### Runtime Protocol

Define shared contracts before implementing the external runner:

- `WorkflowDescription`
- `WorkflowInputDefinition`
- `WorkflowStepDescription`
- `WorkflowRunInput`
- `WorkflowEvent`
- `WorkflowEventStatus`
- `ReviewResult`
- `ReviewFinding`
- `BuildResult`
- `ImplementationResult`

These should be `Codable` and stable enough for both built-in and external workflow runners.

### Early Spike

The first spike should:

1. Add `HephaestusExampleWorkflows` as a separate Swift package.
2. Add one executable workflow with `describe`, `validate`, and fake `run`.
3. Define the first version of shared workflow protocol types.
4. Teach the app to register one external workflow folder manually or from a hardcoded local path.
5. Render the external workflow beside built-in workflows.
6. Run it and stream fake JSONL events into the existing run updates UI.
7. Capture stdout/stderr to a debug log.

Only after this works should the real Implementation Review Loop move toward an external package.

### Future Editor Direction

Do not make the first in-app editor a raw Swift package editor. Treat editing as a later product layer.

A likely evolution is:

1. External Swift packages edited in a normal editor.
2. App renders package metadata and typed inputs.
3. Packages expose reusable step definitions.
4. App supports a structured workflow editor over a constrained model.
5. The editor can generate Swift, config, or an intermediate graph depending on what the spike teaches us.

---

## Validation

### Success Metrics

- The app can discover an example external workflow from an explicit manifest.
- `describe` metadata renders in the workflow list without app-specific knowledge of the package internals.
- `run` streams JSONL events that update the same run updates UI used by built-in workflows.
- A failed external workflow exits without crashing or freezing the app.
- Debug logs capture full stdout/stderr for external workflow runs.
- The protocol is sufficient to represent Implementation Review Loop phases at a summary level.

### Monitoring

For the spike, validation is local and manual:

- run the app target build,
- run workflow protocol unit tests,
- run the fake external workflow directly from Terminal,
- run the fake external workflow through the app,
- confirm malformed events and nonzero exit paths are visible in the UI.

---

## Related Decisions

- [ADR-0006](0006-package-boundaries-and-cross-package-deep-links.md) - Package boundaries and cross-package deep links.
- [ADR-0007](0007-headless-runtime-entrypoint.md) - Headless runtime entrypoint.
- [ADR-0010](0010-tool-execution-context-and-permission-boundary.md) - Tool execution context and permission boundary.
- [ADR-0011](0011-anvil-design-system-packages.md) - Anvil design system packages.

---

## References

- [Subagent Implementation Review Loop](../workflows/subagent-implementation-review-loop.md)

---

## Notes

This ADR intentionally chooses a narrow extensibility boundary before the workflow authoring product is fully known. The purpose is to learn from a real external workflow package without committing to a full package ecosystem, visual editor, or custom workflow language.

**Last Updated:** 2026-05-05
