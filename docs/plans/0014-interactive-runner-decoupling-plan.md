# Interactive Runner Decoupling Plan

## Context

The planning review workflow now proves a working interactive happy path: a workflow can pause for
planning, accept a validated output, run automated review cycles, and return to the user for a
final decision.

The remaining design pressure is in the generic workflow runner shell. Planning-specific state is
still wired directly into the reusable runner:

- `WorkflowRunnerState` owns `planningInteraction`.
- `WorkflowRunnerModel` owns planning review services and planning-specific actions.
- `WorkflowRunnerView` renders `PlanningInteractionView` as a special case.
- Run completion paths know when `PlanningReviewWorkflowRunner.id` should create or update an
  interactive planning session.

That is acceptable for the first proof of concept, but the next interactive workflow would likely
add another optional state and view branch. The next slice should introduce a reusable interactive
workflow boundary before more workflows depend on the planning-specific shape.

Related docs:

- [PRD-0011. Interactive Planning Review Workflow](../prd/0011-interactive-planning-review-workflow.md)
- [Interactive Workflow Model Refinement](0012-interactive-workflow-model-refinement.md)
- [Interactive Step Review Gates And Exit Policy](0013-interactive-step-review-gates-and-exit-policy.md)

## Goal

Create a reusable host-owned boundary for interactive workflow pauses while keeping the planning
workflow implementation concrete and replaceable.

The generic runner should know that an active workflow has an interactive pause, but it should not
need to know planning-specific draft fields, prompts, artifact paths, review cycles, or views.

## Non-Goals

- Do not build the full workflow builder.
- Do not replace planning-specific output validation, prompts, artifact storage, or review
  automation with generic abstractions yet.
- Do not introduce broad JSON-like workflow configuration.
- Do not redesign the planning review UX in this slice.
- Do not remove useful planning-specific types simply to make everything generic.

## Design Direction

### 1. Introduce A Generic Interactive Activity Slot

Replace `planningInteraction` on the generic runner state with a single workflow-owned interactive
activity projection.

Candidate shape:

```swift
struct WorkflowInteractiveActivity: Equatable {
    let workflowID: WorkflowDefinition.ID
    let stepID: String
    let sessionID: String
    let title: String
    let subtitle: String
    let phase: WorkflowInteractivePhase
    let payload: WorkflowInteractivePayload
}

enum WorkflowInteractivePhase: Equatable {
    case waitingForInput
    case running
    case waitingForReview
    case accepted
}
```

The payload can stay intentionally narrow for now. It should be a host-owned projection, not a
future-proof schema registry.

### 2. Keep Planning State Behind A Feature Controller

Move planning-specific action handling and state mutation behind a planning workflow controller or
session owner.

Candidate responsibilities:

- own `PlanningInteractionState`
- expose `WorkflowInteractiveActivity` for the generic runner
- process planning actions
- call planning backend, artifact materializer, and automation services
- emit generic runner updates: step records, timeline, output, status, active activity

The generic model should delegate to this owner rather than directly exposing planning methods.

### 3. Add A View Adapter Boundary

The runner view should render an interactive activity through a small adapter registry:

```swift
protocol WorkflowInteractiveActivityViewProviding {
    func canRender(_ activity: WorkflowInteractiveActivity) -> Bool
    func makeView(activity: WorkflowInteractiveActivity, action: @escaping (WorkflowInteractiveAction) -> Void)
}
```

The first implementation can be simpler than this exact protocol, but the boundary should mean:

- the generic runner view does not switch on `PlanningReviewWorkflowRunner.id`,
- planning owns the mapping from generic activity payload to `PlanningInteractionView`,
- future workflows can add their own activity renderer without adding a new optional state field.

### 4. Keep Action Routing Explicit

Use a generic action envelope at the runner boundary and keep typed planning actions in the planning
feature.

Candidate shape:

```swift
struct WorkflowInteractiveAction: Equatable {
    let workflowID: WorkflowDefinition.ID
    let stepID: String
    let kind: String
    let value: String?
}
```

Planning can map this to `PlanningInteractionActionProcessor.Action`. If this feels too stringly
during implementation, use a planning-specific adapter first and keep the generic action envelope
as a follow-up, but do not push planning actions into generic views.

### 5. Preserve Current Planning Behavior

This is a boundary refactor. The following behavior should remain unchanged:

- Run starts in interactive planning.
- Notes can produce a draft through the backend runner.
- User accepts a valid draft for automated review.
- Automated cycles return to user review.
- User can accept, continue planning, or request another cycle.
- Review handoff summary still shows latest plan plus cycle feedback/history.

## Proposed Implementation Slices

### Slice 1: State Projection

- Add `WorkflowInteractiveActivity` and phase models.
- Add a projection from `PlanningInteractionState` to `WorkflowInteractiveActivity`.
- Keep `planningInteraction` temporarily while wiring projection into the UI.
- Add tests for planning state to activity projection.

### Slice 2: View Adapter

- Introduce a planning activity renderer/adaptor.
- Move the `PlanningInteractionView` special case out of `WorkflowRunnerView`.
- Keep existing accessibility identifiers stable.
- Run the existing planning UI/unit tests.

### Slice 3: Model Delegation

- Move planning action handling out of `WorkflowRunnerModel` into a planning controller/session
  owner.
- Have `WorkflowRunnerModel` delegate planning actions by workflow/activity identity.
- Preserve existing public user flows.
- Add focused tests for run start, submit, continue, another cycle, and accept.

### Slice 4: Remove The Temporary Optional

- Remove `planningInteraction` from `WorkflowRunnerState`.
- Store only the generic interactive activity on the runner state.
- Keep planning-specific state inside the planning feature owner.
- Verify no generic runner files import or switch on planning-only models except through the
  registered built-in workflow/controller boundary.

## Acceptance Criteria

- `WorkflowRunnerState` does not contain planning-specific interactive state.
- `WorkflowRunnerView` does not directly instantiate `PlanningInteractionView`.
- Planning-specific prompts, artifacts, validators, and review-cycle outputs remain under
  `PlanningReviewWorkflow`.
- Existing planning workflow tests still pass.
- At least one focused test proves the generic runner can hold an interactive activity without
  knowing planning-specific draft fields.
- No new mock behavior is added to production core files.

## Review Questions

- Should the generic activity payload be type-erased render data, a small enum, or a registry key
  plus feature-owned state lookup?
- Should the planning controller live under `PlanningReviewWorkflow/Interactors` or under the
  built-in workflow catalog boundary?
- Is the generic action envelope useful now, or should action routing stay planning-specific until a
  second interactive workflow exists?
- How much of `WorkflowRunnerModel+PlanningInteraction` should move in one slice versus staged
  extraction?
