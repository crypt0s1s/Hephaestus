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

## Planning Workflow Boundary

This is a PRD-0011 boundary refactor, not a product expansion. It should make the existing
interactive planning workflow easier to grow without adding a new user flow, new workflow-builder
surface, or broad generic step schema.

The target shape is:

- generic runner state tracks that an interactive workflow activity exists,
- planning owns planning state, prompts, validation, artifacts, automation, and recovery behavior,
- the runner shell observes derived projections and dispatches user actions through registered
  workflow/session owners,
- temporary hardcoded planning behavior stays in planning-specific components and remains
  replaceable.

## Design Direction

### 1. Introduce A Generic Interactive Activity Projection

Replace `planningInteraction` on the generic runner state with a single workflow-owned interactive
activity projection. The projection is display and routing metadata only. It is not the source of
truth for planning state, and it should never be independently mutated.

Candidate shape:

```swift
struct WorkflowInteractiveActivity: Equatable {
    let workflowID: WorkflowDefinition.ID
    let activityID: String
    let stepID: String
    let sessionID: String
    let rendererID: String
    let title: String
    let subtitle: String
    let status: WorkflowInteractiveStatus
    let primaryUserAction: WorkflowInteractiveUserAction?
}

enum WorkflowInteractiveStatus: Equatable {
    case waitingForInput
    case waitingForOutputReview
    case runningAutomation
    case waitingForFinalReview
    case recoverableFailure
    case accepted
    case blocked(String)
}

struct WorkflowInteractiveUserAction: Equatable {
    let title: String
    let systemImage: String?
    let accessibilityIdentifier: String
}
```

`activityID` identifies the current interactive activity being rendered. `stepID` identifies the
workflow definition step that owns or produced the activity. They can be the same for the initial
planning pause, but later user review should be able to use a distinct activity such as
`interactive-user-review` while resolving the same planning session. Render adapters should use
`workflowID`, `activityID`, and `sessionID` to find typed feature state.

The status is a projection of feature-owned state and gates, not a replacement for them. Planning
still owns distinctions such as idle, sending, materializing, reviewing, completed, accepted,
failed automation recovery, duplicate draft recovery, and reopened planning. The generic projection
only gives the shell enough information to render the correct activity container and preserve
workflow-level affordances.

There should be no generic `WorkflowInteractivePayload` in this slice. If a renderer needs planning
render state, it resolves the typed state from the planning feature owner using `workflowID`,
`activityID`, and `sessionID`.

### 2. Keep Planning State Behind A Workflow Session Owner

Move planning-specific action handling and state mutation behind a planning workflow/session owner.
This owner is a runtime workflow service, not a SwiftUI page interactor.

Candidate responsibilities:

- own `PlanningInteractionState`
- expose `WorkflowInteractiveActivity` for the generic runner
- expose a read-only typed planning state lookup for render adapters
- process typed planning actions
- call planning backend, artifact materializer, and automation services
- emit generic runner updates: step records, timeline, output, status, active activity
- expose test support for seeding and observing planning state without reaching through
  `WorkflowRunnerState`

The generic model should delegate to this owner rather than directly exposing planning methods or
owning planning services. By the end of this refactor, generic runner files should not reference
`PlanningReviewServices`, `PlanningInteractionState`, `PlanningInteractionView`, or
`PlanningInteractionActionProcessor`. The registration boundary itself should live with the
planning workflow feature or app composition root, not inside the generic runner model/view files.

### 3. Add A Typed View Adapter Boundary

The runner view should render an interactive activity through a small adapter boundary. The first
adapter can stay planning-specific at the edge:

```swift
protocol WorkflowInteractiveActivityRendering {
    associatedtype Body: View

    func canRender(_ activity: WorkflowInteractiveActivity) -> Bool
    func makeView(activity: WorkflowInteractiveActivity) -> Body
}
```

The exact Swift shape can change during implementation, but the boundary must preserve these
rules:

- the generic runner view does not switch on `PlanningReviewWorkflowRunner.id`,
- planning owns the mapping from generic activity payload to `PlanningInteractionView`,
- the adapter can resolve `PlanningInteractionState` from the planning session owner,
- adapter-rendered views remain `state in/action out`,
- pasteboard copying, backend calls, artifact materialization, submission, retry, and automation
  stay behind the durable planning session owner, not the renderer or a page interactor,
- planning layout controls such as presentation style pickers live in the planning renderer, not
  in the generic runner view,
- future workflows can add their own activity renderer without adding a new optional state field.

### 4. Keep Action Routing Typed In The First Slice

Do not introduce a stringly generic action envelope yet. The first slice should keep typed planning
actions in the planning adapter/session owner and route them by activity identity.

Candidate edge shape:

```swift
struct PlanningInteractiveActivityAdapter {
    func state(for activity: WorkflowInteractiveActivity) -> PlanningInteractionState?
    func handle(_ action: PlanningInteractionActionProcessor.Action, activity: WorkflowInteractiveActivity)
}
```

A generic `WorkflowInteractiveAction` can be reconsidered when a second interactive workflow needs
the same shell. Until then, a typed adapter is more consistent with ADR-0004 and avoids turning
the generic runner into a loose command bus.

### 5. Preserve Current Planning Behavior

This is a boundary refactor. The following behavior should remain unchanged:

- Run starts in interactive planning.
- Notes can produce a draft through the backend runner.
- User accepts a valid draft for automated review.
- Automated cycles return to user review.
- User can accept, continue planning, or request another cycle.
- Review handoff summary still shows latest plan plus cycle feedback/history.
- Failed automation leaves a recoverable planning session visible with its draft and error state.
- Duplicate accepted-draft recovery and reopened planning remain visible and editable where they
  are today.

### 6. Replace Run-Start Special Cases With Waiting Activities

Run start should not create planning state by comparing against `PlanningReviewWorkflowRunner.id`.
The built-in workflow boundary should be able to return or register an interactive waiting
activity when a workflow pauses.

Possible implementation shape:

```swift
enum BuiltInWorkflowRunResult {
    case completed(ProcessResult)
    case waiting(WorkflowRunProgress, output: String, activity: WorkflowInteractiveActivity)
}
```

The exact type can vary, but the handoff must make the waiting activity explicit. The generic
runner applies the returned projection; the planning owner keeps the typed session state.

## Migration Invariants

- `WorkflowInteractiveActivity` is derived-only.
- Initial planning and final user review are separate activities even if they share one planning
  session.
- While `planningInteraction` still exists, the projection and planning state must be updated from
  the same planning owner operation.
- The generic runner must not mutate planning draft, gate, artifact, or recovery state directly.
- A recoverable failed planning session must remain renderable even when the active workflow has
  stopped.
- Tests should migrate to planning owner/session APIs before `planningInteraction` is removed from
  `WorkflowRunnerState`.
- Each slice should reduce direct generic-runner references to planning types rather than creating
  a second path with the old path still active.

## Proposed Implementation Slices

### Slice 1: Activity Projection And Session Lookup

- Add `WorkflowInteractiveActivity`, status, and primary action models.
- Add a projection from `PlanningInteractionState` to `WorkflowInteractiveActivity`.
- Add a read-only planning session lookup that can resolve `PlanningInteractionState` by
  `sessionID`.
- Add minimal planning owner/session test APIs for seeding and observing planning state before
  moving action handling.
- Keep `planningInteraction` temporarily, but treat the activity projection as derived-only.
- Add tests for idle, sending, materializing, reviewing, completed, accepted, failed recovery, and
  reopened planning projections.

### Slice 2: View Adapter Without View-Layer Services

- Introduce a planning activity renderer/adaptor.
- Move the `PlanningInteractionView` special case out of `WorkflowRunnerView`.
- Ensure `WorkflowRunnerView` no longer constructs `PlanningInteractionActionProcessor`.
- Keep pasteboard, backend, artifact, automation, and recovery behavior behind the planning
  session owner.
- Move the planning presentation-style picker and `PlanningInteractionView.PresentationStyle`
  coupling out of `WorkflowRunnerView`.
- Keep existing accessibility identifiers stable.
- Add a test or assertion that `WorkflowRunnerView` no longer directly instantiates
  `PlanningInteractionView` or references planning view types.
- Run the existing planning UI/unit tests.

### Slice 3: Runtime Waiting Handoff And Service Ownership

- Extend the built-in workflow run result or registry hook so workflows can return an interactive
  waiting activity at run start.
- Remove the `PlanningReviewWorkflowRunner.id` run-start special case from `WorkflowRunnerModel`.
- Move `PlanningReviewServices` ownership behind the planning workflow/session owner and compose it
  from the planning feature or app composition root, not from generic runner model/view files.
- Have `WorkflowRunnerModel` delegate planning actions by workflow/activity identity.
- Preserve existing public user flows.
- Add focused tests for run start, submit, continue, another cycle, and accept.

### Slice 4: Complete Test Support Migration

- Expand planning owner/session test APIs for seeding submitted output, failed recovery, and
  completed review state.
- Migrate existing planning workflow tests away from `model.state.planningInteraction`.
- Add focused tests for failed automation recovery, duplicate accepted draft recovery, renderer
  selection, and activity projection parity.

### Slice 5: Remove The Temporary Optional

- Remove `planningInteraction` from `WorkflowRunnerState`.
- Store only the generic interactive activity on the runner state.
- Keep planning-specific state inside the planning feature owner.
- Verify no generic runner files import or switch on planning-only models except through the
  app-level workflow registration boundary.

## Acceptance Criteria

- `WorkflowRunnerState` does not contain planning-specific interactive state.
- `WorkflowRunnerView` does not directly instantiate `PlanningInteractionView`.
- `WorkflowRunnerView` does not reference planning view types or own planning presentation controls.
- Planning-specific prompts, artifacts, validators, and review-cycle outputs remain under
  `PlanningReviewWorkflow`.
- Existing planning workflow tests still pass.
- At least one focused test proves the generic runner can hold an interactive activity without
  knowing planning-specific draft fields.
- No new mock behavior is added to production core files.
- `WorkflowRunnerModel` does not own `PlanningReviewServices`.
- Generic runner model/view files do not construct planning services or planning renderers.
- Run-start waiting behavior is represented by an explicit interactive activity, not a planning ID
  check in the generic runner.
- Initial planning and final user review can be represented as distinct activities for the same
  planning session.
- Failed/recoverable planning sessions remain visible after automation failure.
- Planning tests seed and inspect planning state through planning owner/session support APIs, not
  through `WorkflowRunnerState.planningInteraction`.

## Validation Plan

Run the default non-UI checks after each implementation slice:

```bash
./scripts/lint.sh
git diff --check
```

Run focused unit coverage for planning workflow behavior and projection/action routing:

```bash
xcodebuild -project Hephaestus.xcodeproj -scheme Hephaestus -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO MACOSX_DEPLOYMENT_TARGET=26.1 -only-testing:HephaestusTests/PlanningReviewWorkflowTests -only-testing:HephaestusTests/PlanningReviewWorkflowContinuationTests -only-testing:HephaestusTests/PlanningReviewWorkflowFailureTests -only-testing:HephaestusTests/PlanningReviewHandoffSummaryTests -only-testing:HephaestusTests/PlanningInteractionActionProcessorTests test
```

Run the existing planning UI tests with normal local signing when the view adapter changes:

```bash
xcodebuild -project Hephaestus.xcodeproj -scheme Hephaestus -destination 'platform=macOS' -only-testing:HephaestusUITests/HephaestusUITests/testPlanningReviewWorkflowStartsInteractiveWaitingState -only-testing:HephaestusUITests/HephaestusUITests/testPlanningReviewWorkflowSubmitsInteractivePlan test
```

Add source checks or focused tests that prove:

- `WorkflowRunnerState` has no planning-specific interactive state after Slice 5,
- `WorkflowRunnerView` does not directly instantiate `PlanningInteractionView` or reference
  `PlanningInteractionView.PresentationStyle`,
- generic runner files no longer reference `PlanningReviewServices`,
- generic runner code no longer mutates planning draft, gate, artifact, or recovery state.

## Review Questions

- How much of `WorkflowRunnerModel+PlanningInteraction` should move in one slice versus staged
  extraction?
- What should the exact waiting-result type be so a paused workflow can return progress, output,
  and an interactive activity without leaking planning details?
- Should typed planning session test APIs live with the planning owner or in test-only fixtures?
