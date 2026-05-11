# Interactive Workflow Model Refinement

## Context

The planning review workflow is primarily a capability spike for interactive workflow pauses,
session handoff, and later workflow-builder IO. The first implementation proved the UI path, but
the models were too planning-specific and too close to presentation state.

## Review Findings

- `WorkflowInteractionState` was mixing identity, UI copy, draft editing, backend progress, and
  submitted output state.
- `InteractiveStepMessage` was named like a durable workflow-wide message but only represented
  an interactive artifact handoff.
- `PlanningReviewWorkflowRunner` was mixing definition, pause state, record projection, and
  automated review behavior.
- Submit-plan was treated like workflow completion instead of a resume transition into automation.
- The planning surface was buried in the normal workflow list, making the active interactive step
  feel like a widget instead of the current task.

## Current Slice

- Keep `WorkflowInteractionState` as a UI-facing interaction state, but split its concerns enough
  for this spike: phase, backend session, transcript entries, draft text, and submitted output.
- Rename the handoff type to `InteractiveStepOutput` and make its primary payload an
  `InteractiveStepArtifact` with optional project-relative export path.
- Send planning notes to a Codex-backed backend adapter instead of fabricating planner replies in
  the model.
- Materialize submitted plans to `.hephaestus/planning-review/<session-id>/plan.md`.
- Validate the markdown artifact before resuming automation.
- Run two automated planning review cycles, then return to an interactive user-review state.
- Let the user accept the reviewed plan, reopen planning, or request another automated review
  cycle from the user-review pause.
- Move automated review helper behavior out of `PlanningReviewWorkflowRunner` into
  `PlanningReviewAutomation`.
- Add an editor-primary planning layout with a local layout switcher for comparing the older split
  view against a more focused plan editor.
- Run reviewer and planner-response Codex turns with a read-only sandbox mode in this slice.

## Still Not Final

- The long-lived builder model should introduce first-class `WorkflowRun`, `WorkflowPause`,
  `WorkflowResumeCommand`, and durable `WorkflowMessage` concepts.
- Workflow messages should be Codable and persisted separately from exported markdown artifacts.
- Codex interactive continuity is still bounded by the current `codex exec` adapter; the cleaner
  direction is a streaming session contract closer to the Task Workspace runtime event model.
- `WorkflowInteractionState` still carries backend session identity; a future `WorkflowRun`
  runtime model should own session lifecycle and project interaction state into the UI.
- `PlanningReviewWorkflowRunner` still emits `WorkflowStepRecord` UI projections directly. A
  workflow-builder-ready runtime should emit events/transitions first and project them separately.
