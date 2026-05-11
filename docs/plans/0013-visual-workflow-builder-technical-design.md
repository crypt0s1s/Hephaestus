# Visual Workflow Builder Technical Design

**Status:** Proposed
**Date:** 2026-05-11
**Related PRD:** [PRD-0012. Visual Workflow Builder](../prd/0012-visual-workflow-builder.md)
**Related ADRs:** [ADR-0013. Visual Workflow Definition And Runtime Boundary](../adr/0013-visual-workflow-definition-and-runtime-boundary.md)

## 1. Purpose

PRD-0012 defines a graphical builder for visually composing multi-agent Codex workflows as connected steps. This plan proposes the first durable architecture for workflow definitions, step execution semantics, looping behavior, actor configuration, skills/MCP scoping, validation, storage, and SwiftUI UI ownership.

Product behavior, scope, acceptance criteria, and milestones remain in PRD-0012. This design describes how the accepted product slice should be built without expanding it into full arbitrary workflow execution.

## 2. Current Code Facts

- `WorkflowDefinition` and `WorkflowStepDefinition` currently describe runnable workflow cards, inputs, and simple step summaries for built-in and external workflows.
- `WorkflowRunnerModel` owns workflow selection, run state, planning interaction state, and side effects for starting built-in workflows.
- `PlanningReviewWorkflowRunner` and `PlanningReviewAutomation` prove interactive pause/resume and automated review cycles, but their models are still planning-specific.
- `InteractiveStepOutput` represents a prototype handoff artifact, not a durable workflow-wide message model.
- `WorkflowRunProgress`, `WorkflowStepRecord`, and `WorkflowTimelineProjection` are UI/run projection concepts, not workflow authoring schema.
- `HarnessBackendAdapter` and `CodexHarnessBackendAdapter` provide the first backend boundary for Codex-backed turns.
- Existing docs identify future builder-ready concepts: `WorkflowRun`, `WorkflowPause`, `WorkflowResumeCommand`, durable `WorkflowMessage`, and runtime-owned artifacts.

## 3. Design Goals

- Make workflow definitions durable, versioned, and independent of canvas UI state.
- Keep visual editor state separate from runtime orchestration state.
- Model steps, links, loops, IO, actor configuration, interaction gates, capability scopes, artifacts, and decisions as first-class data.
- Validate definitions before they can be treated as execution-ready.
- Keep the first implementation Codex-first while avoiding Codex-specific fields in the core graph model.
- Let existing built-in workflows continue while the builder model is introduced in parallel.
- Preserve a direct path from validated definitions to a future orchestration runtime.

## 4. Non-Goals

- No full arbitrary graph executor in the first builder slice.
- No replacement of current built-in runners during M1/M2.
- No marketplace or cross-project sharing.
- No multi-user collaboration.
- No full policy engine for organization-wide tool governance.
- No canvas feature race; graph correctness matters more than layout polish.

## 5. Proposed Ownership Boundaries

Use new feature-local boundaries first, with names adjusted during implementation as needed:

- `WorkflowDefinitions`: durable schema, pattern fixtures, schema versioning, storage, and encode/decode tests.
- `WorkflowValidation`: pure validation rules for graph shape, IO bindings, loops, actors, capabilities, and execution readiness.
- `WorkflowBuilder`: SwiftUI page, canvas/editor projection, interactor, editor state, and authoring actions.
- `WorkflowRuntime`: future orchestration concepts such as run, pause, resume command, message, artifact reference, step execution state, and event projection.
- `HarnessBackends`: backend adapters and backend capability declarations.
- `ArtifactStorage`: runtime-owned artifacts, messages, decision records, and export references.

The first implementation can keep these as folders under `Hephaestus/Features/` before package extraction. The important boundary is ownership: builder UI may edit definitions, validation may inspect definitions, runtime may execute definitions later, and backend adapters may launch work, but none of those layers should own all concerns at once.

## 6. Workflow Definition Model

Introduce a versioned project-local definition model. Exact Swift names can change, but the model should have this shape:

```swift
struct WorkflowGraphDefinition: Codable, Identifiable, Equatable {
    var id: WorkflowID
    var schemaVersion: Int
    var metadata: WorkflowMetadata
    var nodes: [WorkflowNode]
    var links: [WorkflowLink]
    var loops: [WorkflowLoop]
    var actors: [WorkflowActorProfile]
    var capabilities: WorkflowCapabilityCatalogReference?
}
```

### Step Nodes

```swift
struct WorkflowNode: Codable, Identifiable, Equatable {
    var id: WorkflowNodeID
    var title: String
    var role: WorkflowStepRole
    var executionMode: WorkflowExecutionMode
    var actorRef: WorkflowActorRef
    var instructions: WorkflowInstructionSource
    var inputs: [WorkflowInputDeclaration]
    var outputs: [WorkflowOutputDeclaration]
    var capabilityScope: WorkflowCapabilityScope
    var approvalPolicy: WorkflowApprovalPolicy
    var artifactPolicy: WorkflowArtifactPolicy
}
```

Roles should cover the PRD-required set:

- planning,
- implementation,
- review,
- terminal-assisted,
- interactive Codex collaboration,
- automated execution.

Execution mode should be separate from role:

- `automatic`,
- `interactivePause`,
- `approvalGate`,
- `terminalAssisted`,
- `separateActorInstance`,
- `manualOnly`.

This avoids overloading role names with runtime lifecycle behavior. For example, a review step can be automatic or approval-gated; an implementation step can run in a separate Codex instance or be terminal-assisted.

### Links

Links should not be canvas arrows. They should describe the handoff:

```swift
struct WorkflowLink: Codable, Identifiable, Equatable {
    var id: WorkflowLinkID
    var from: WorkflowEndpoint
    var to: WorkflowEndpoint
    var kind: WorkflowLinkKind
    var binding: WorkflowBinding
    var condition: WorkflowTransitionCondition?
}
```

`WorkflowLinkKind` should include:

- control,
- data,
- artifact,
- decision,
- approval.

The validator should reject links that connect incompatible output and input declarations. A control-only link may not satisfy a required data input unless an explicit default or artifact binding exists.

### IO And Runtime Messages

Define IO declarations now, but keep payload schemas lightweight:

```swift
struct WorkflowInputDeclaration: Codable, Identifiable, Equatable {
    var id: WorkflowInputID
    var name: String
    var acceptedKinds: [WorkflowValueKind]
    var required: Bool
}

struct WorkflowOutputDeclaration: Codable, Identifiable, Equatable {
    var id: WorkflowOutputID
    var name: String
    var producedKind: WorkflowValueKind
    var durable: Bool
}
```

`WorkflowValueKind` should initially include:

- message,
- artifactReference,
- decision,
- plan,
- reviewFeedback,
- terminalTranscript,
- approvalResult,
- opaqueJSON.

The future runtime should materialize outputs as runtime-owned values:

```swift
struct WorkflowMessage: Codable, Identifiable, Equatable {
    var id: WorkflowMessageID
    var definitionOutputID: WorkflowOutputID
    var producerNodeID: WorkflowNodeID
    var runID: WorkflowRunID
    var kind: WorkflowValueKind
    var createdAt: Date
    var payload: WorkflowMessagePayload
    var artifactRefs: [WorkflowArtifactRef]
}
```

The definition declares what can be produced and consumed. The runtime owns concrete messages and artifacts.

## 7. Loop Model

Represent loops explicitly rather than as arbitrary graph cycles. The recommended first model is a structured loop region:

```swift
struct WorkflowLoop: Codable, Identifiable, Equatable {
    var id: WorkflowLoopID
    var title: String
    var memberNodeIDs: [WorkflowNodeID]
    var entryNodeIDs: [WorkflowNodeID]
    var exitNodeIDs: [WorkflowNodeID]
    var iterationInputBindings: [WorkflowBinding]
    var iterationOutputBindings: [WorkflowBinding]
    var stopCondition: WorkflowLoopStopCondition
    var userBreakpoints: [WorkflowLoopBreakpoint]
}
```

Stop conditions should support:

- max iterations,
- until approval,
- until review passes,
- until no blocking findings,
- until output satisfies validation,
- manual stop.

For first-slice execution readiness, every loop must have a bounded max iteration or an explicit human breakpoint. Unbounded autonomous loops should be invalid.

Reusable patterns should be bundled as definitions using the same schema:

- planning loop: interactive planning -> automated review -> planner response -> user review gate,
- review loop: implementation output -> parallel reviews -> consolidated feedback -> approval or fix request,
- implementation loop: implement -> build/test -> review -> feedback relay -> fix cycle.

## 8. Actor Configuration

Actor configuration should be referenced by nodes instead of embedded as free-form backend launch text:

```swift
struct WorkflowActorProfile: Codable, Identifiable, Equatable {
    var id: WorkflowActorID
    var displayName: String
    var backend: WorkflowBackendKind
    var rolePrompt: String
    var defaultModel: String?
    var instancePolicy: WorkflowActorInstancePolicy
    var defaultCapabilityScope: WorkflowCapabilityScope
}
```

`WorkflowBackendKind` should include `codex` first, with future cases for Foundry, Claude Code, OpenCode, Gemini, ACP, or custom adapter IDs.

Codex-specific details such as executable path, raw CLI flags, approval plumbing, resume identifiers, and event payloads should stay in `HarnessBackendAdapter` configuration and runtime state. The graph definition should declare desired actor behavior and capability requirements, not process invocation details.

## 9. Skills, MCP, Tools, And Permissions

Use a machine-readable capability scope per node:

```swift
struct WorkflowCapabilityScope: Codable, Equatable {
    var allowedSkills: [SkillID]
    var allowedMCPServers: [MCPServerID]
    var allowedTools: [ToolID]
    var filesystemPolicy: WorkflowFilesystemPolicy
    var networkPolicy: WorkflowNetworkPolicy
    var approvalPolicy: WorkflowApprovalPolicy
}
```

Validation should check:

- requested skills exist or are marked unresolved,
- requested MCP servers exist in the project or global catalog,
- tools are allowed by backend capability declarations,
- sandbox posture is compatible with the execution mode,
- approval-gated actions cannot be silently treated as automatic.

The first builder slice can use a static local catalog or mocked catalog adapter. Keep it behind a catalog protocol so real skill/MCP discovery can replace it later.

## 10. Runtime Orchestration Model

Do not execute arbitrary builder graphs in M1/M2, but design toward this runtime shape:

```swift
struct WorkflowRun: Codable, Identifiable, Equatable {
    var id: WorkflowRunID
    var definitionID: WorkflowID
    var definitionVersion: Int
    var status: WorkflowRunStatus
    var nodeStates: [WorkflowNodeExecutionState]
    var messages: [WorkflowMessage]
    var pauses: [WorkflowPause]
    var artifactRefs: [WorkflowArtifactRef]
}
```

```swift
struct WorkflowPause: Codable, Identifiable, Equatable {
    var id: WorkflowPauseID
    var nodeID: WorkflowNodeID
    var reason: WorkflowPauseReason
    var requiredResumeCommand: WorkflowResumeCommandKind
    var expectedDecisionOutputs: [WorkflowOutputID]
}
```

The runtime should:

- evaluate ready nodes from validated definitions,
- allocate actor instances through backend adapters,
- route runtime-owned messages and artifacts between nodes,
- pause on interactive and approval-gated nodes,
- emit normalized events for timeline projection,
- keep backend-native details behind adapters.

This model is intentionally separate from `WorkflowRunProgress` and `WorkflowStepRecord`, which can remain UI projection types.

## 11. Artifact Storage

Use project-local storage for app-owned workflow definitions and runtime artifacts:

```text
.hephaestus/
  workflows/
    <workflow-id>.workflow.json
  workflow-runs/
    <run-id>/
      run.json
      messages.jsonl
      artifacts/
      exports/
```

Definitions should be app-owned data under `.hephaestus/workflows/` in the first slice. Later export to source-controlled docs or workflow packages can be added without changing the runtime data model.

Artifacts and messages should be runtime-owned. Markdown files, transcripts, and links under `exports/` are inspectable renderings, not the communication mechanism between steps.

## 12. Validation Rules

Create a pure validator that returns structured issues:

```swift
struct WorkflowValidationIssue: Identifiable, Equatable {
    var id: String
    var severity: WorkflowValidationSeverity
    var location: WorkflowValidationLocation
    var code: WorkflowValidationCode
    var message: String
    var suggestedFix: String?
}
```

Initial rules:

- exactly one start node or explicit start policy,
- no dangling links,
- no duplicate IDs,
- required node fields are present,
- actor references resolve,
- instruction sources resolve,
- required inputs are bound or have defaults,
- output/input kinds are compatible,
- loops have entry, exit, member nodes, and bounded stop conditions,
- graph cycles are only allowed through explicit loop definitions,
- interactive and approval-gated nodes declare resume commands and decision outputs,
- capability scopes resolve and are compatible with actor backend,
- execution-readiness is false when blocking issues exist.

Validation should be independent from the SwiftUI editor so tests can cover it directly.

## 13. SwiftUI Builder Architecture

Follow ADR-0004:

- `WorkflowBuilderView` renders state and emits `WorkflowBuilderAction`.
- `WorkflowBuilderModel` or interactor owns editing state, validation calls, persistence calls, and pattern insertion.
- `WorkflowBuilderState` contains the selected workflow, editor selection, visible canvas projection, validation issues, save state, and inspector state.
- `WorkflowGraphDefinition` remains the semantic source of truth.
- `WorkflowCanvasState` stores viewport, selection, layout positions, and transient drag/link gestures separately.

Recommended UI structure:

- left pattern/library rail,
- central canvas for graph nodes and links,
- right inspector for selected workflow, node, link, or loop,
- bottom validation drawer or inline issue list,
- normalized-definition preview for M2.

Views should emit actions such as:

- createWorkflow,
- insertPattern,
- addNode,
- updateNodeRole,
- updateActor,
- updateInstructions,
- updateCapabilityScope,
- connectNodes,
- deleteSelection,
- createLoop,
- updateLoop,
- validate,
- save,
- reopen.

No backend launches, file IO, validation mutation, or runtime side effects should happen inside SwiftUI view bodies.

## 14. Implementation Sequence

1. Add the workflow definition schema, IDs, actor/capability types, loop types, and sample fixtures.
2. Add encoding/decoding tests for planning loop, review loop, and implementation loop fixtures.
3. Add the pure validator and validation tests.
4. Add project-local definition storage under `.hephaestus/workflows/`.
5. Add bundled pattern definitions using the same schema.
6. Add `WorkflowBuilderModel` and interactor tests for create, insert pattern, edit, link, loop, validate, save, and reopen.
7. Add SwiftUI builder screens following the state/action split.
8. Add normalized-definition preview and validation issue rendering.
9. Keep arbitrary execution disabled except for any explicitly supported built-in workflow bridge.

## 15. ADR Recommendation

[ADR-0013](../adr/0013-visual-workflow-definition-and-runtime-boundary.md) records the durable workflow definition and orchestration boundary. It decides:

- workflow definitions are versioned graph data, not canvas state,
- loops are explicit structured regions or first-class model objects,
- runtime-owned messages/artifacts carry step outputs,
- actor/backend launch details remain outside the graph definition,
- validation is a pure boundary before execution readiness.

This decision is durable enough to affect storage, runtime execution, adapters, templates, and UI architecture.

## 16. Test And Validation Plan

Unit tests:

- definition encode/decode round trips,
- schema version handling,
- pattern fixture validity,
- invalid graph and dangling link detection,
- IO kind compatibility,
- explicit loop validation,
- actor and capability scope resolution,
- interaction/approval pause requirement validation,
- storage save/reopen behavior,
- interactor action handling for create/edit/link/delete/loop/validate/save.

Manual validation:

- create a workflow from each reusable loop pattern,
- edit roles, actors, instructions, IO, skills, MCP/tool access, and gates,
- intentionally create validation failures and confirm issue locations,
- save and reopen definitions,
- inspect normalized definition output,
- confirm arbitrary execution is not offered when validation blocks it or runtime support is deferred.

Build validation:

```bash
xcodebuild -project Hephaestus.xcodeproj -scheme Hephaestus -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO build
```

## 17. Risks And Mitigations

- **Risk:** The schema becomes too broad before runtime pressure validates it.
  **Mitigation:** Start with three concrete loop patterns and strict validation fixtures.
- **Risk:** Canvas layout corrupts semantic graph data.
  **Mitigation:** Store semantic definition separately from `WorkflowCanvasState`.
- **Risk:** Codex-specific fields leak into nodes.
  **Mitigation:** Use actor/backend capability declarations and keep launch details in adapters.
- **Risk:** Loops are ambiguous.
  **Mitigation:** Reject raw cycles unless they are represented by explicit `WorkflowLoop` entries.
- **Risk:** Users expect arbitrary execution immediately.
  **Mitigation:** Make execution readiness and runtime support separate validation states.

## 18. Open Questions

| Question | Proposed Direction | Blocks Implementation? |
| --- | --- | --- |
| Should workflow definitions be source-controlled by default? | Store app-owned data under `.hephaestus/workflows/`; add export later. | Yes, for storage choice |
| Should loops be graph regions or loop nodes? | Use structured loop regions referencing member nodes; this keeps step roles intact. | Yes |
| Should pattern definitions be code or files? | Use bundled fixtures once schema is stable; code construction is acceptable during M1 tests. | No |
| What is the exact skill/MCP catalog source? | Start with a static/mock catalog behind a protocol. | No |
| Is an ADR required? | Yes, for definition/runtime boundary and loop semantics. | Yes |

## 19. Exit Criteria

- PRD-0012 is linked from the PRD index.
- This plan is linked from PRD-0012 and the docs index.
- The plan describes workflow definition model, step execution model, looping behavior, actor configuration, skills/MCP scoping, UI architecture, storage, validation, and runtime handoff.
- Open questions identify which decisions require an ADR before implementation.
