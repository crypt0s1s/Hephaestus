# PRD-0010. Nested Workflow Cycle Timeline

**Status:** Draft
**Date:** 2026-05-06
**Owner:** Hephaestus engineering
**Related ADRs:** None
**Related Plans:** [Plan-0009. Nested Workflow Cycle Timeline](../plans/0009-nested-workflow-cycle-timeline-plan.md)

---

## Summary

Improve the workflow run updates UI so repeated implementation-review cycles are shown as nested execution groups instead of a flat list of repeated steps. The timeline should make loop progress, cycle order, and parallel reviewer work obvious at a glance while preserving the existing step inspector for prompts, feedback, and latest output.

## Problem

The current run updates UI flattens every emitted step record into one list. When the implementation review loop repeats, the UI shows multiple `Step 1 - Implementer`, `Step 2 - Build`, `Step 3.1 - Reviewer A`, `Step 3.2 - Reviewer B`, and `Step 4 - Feedback relay` rows.

This creates two user-facing problems:

- The UI does not clearly explain that the workflow is looping through review/fix cycles.
- Step order is visually misleading because repeated phases are grouped by phase sort order instead of by actual cycle execution order.

The result is an operational timeline that is technically populated but hard to trust during a real debugging or review session.

### Users And Jobs

| User | Job To Be Done | Current Pain | Usage Context |
| --- | --- | --- | --- |
| Hephaestus operator | Understand what the implementation-review workflow is doing now | Repeated rows hide cycle boundaries and parallel review state | Watching an active run or inspecting a failed run |
| Workflow developer | Debug orchestration behavior | Flat ordering makes it hard to tell whether execution order or UI projection is wrong | Improving workflow runner behavior |
| Reviewer/implementer | Inspect a specific failed step | Parallel reviewers appear as duplicated top-level steps | Opening prompt/output details in the side inspector |

## Product Outcome

Users can scan a run and immediately answer:

- Which cycle is active?
- Which cycles have already completed?
- Did a cycle fail because of implementation, build, review, or feedback relay?
- Which steps ran in sequence?
- Which steps ran in parallel?
- Which concrete child step should be opened in the inspector?

## Scope Boundaries

### In Scope

- Render setup steps separately from repeated review cycles.
- Render each implementation-review cycle as an indented group.
- Render parallel reviewer steps as children of a parent review step.
- Preserve clickable rows for leaf step inspection.
- Keep debug logs and full transcript access behind existing secondary surfaces.
- Keep rows compact and operational, not decorative.

### Out Of Scope

- Building a visual workflow editor.
- Changing how Codex agents execute.
- Adding cancellation controls.
- Showing full logs inline by default.
- Replacing the existing side inspector.
- Generalizing every possible workflow graph shape in this slice.

### Deferred

- Rich graph visualization for arbitrary workflows.
- Drag/drop workflow authoring.
- Historical analytics across runs.
- Timeline duration bars and per-step timing.
- Retry controls from individual rows.

## User Experience

### Primary Layout

The run updates section should render a nested execution timeline:

```text
Run updates
Click a step to inspect its prompt, feedback, and latest output.

Setup
  Plan validation
  Build command

Cycle 0 - Initial implementation
  Step 1 - Implementer
  Step 2 - Build
  Step 3 - Review
    Reviewer A
    Reviewer B
  Step 4 - Feedback relay

Cycle 1 - Fix cycle 1
  Step 1 - Implementer
  Step 2 - Build
  Step 3 - Review
    Reviewer A
    Reviewer B
  Step 4 - Feedback relay
```

### Visual Hierarchy

Use indentation to represent execution hierarchy:

- Depth 0: setup and cycle groups.
- Depth 1: sequential steps inside setup or a cycle.
- Depth 2: parallel child steps inside a parent step.

The run updates UI should use a maximum expandable depth of 2. Any workflow structure deeper than depth 2 must be summarized into the nearest visible depth-2 row and remain available through the inspector or debug log. This keeps nested workflows readable instead of turning the timeline into an endlessly indented tree.

Cycle rows should show an aggregate status:

- `in progress` if any child is in progress.
- `needs fix` if review found blocking issues, feedback was relayed, and a later cycle has started or is ready to start.
- `failed` if the cycle ended terminally because implementation, build, review, or feedback relay failed without a continuing fix cycle.
- `succeeded` if all required children succeeded.
- `pending` if no child has started.

Parallel parent rows should make concurrency visible. For the implementation-review loop, `Step 3 - Review` is the parent row and `Reviewer A` / `Reviewer B` are child rows.

Parallel parent rows should include a compact aggregate summary when children have mixed states, such as `1 running, 1 failed` or `2 reviewers complete`.

### Example Running State

```text
Setup
  [succeeded] Plan validation   Plan file loaded successfully.
  [succeeded] Build command     Build command resolved for this run.

Cycle 0 - Initial implementation
  [succeeded] Step 1 - Implementer      Finished initial implementation.
  [succeeded] Step 2 - Build            Build passed.
  [needs fix] Step 3 - Review           Blocking findings reported.
    [failed] Reviewer A                 Reported blocking findings.
    [failed] Reviewer B                 Reported blocking findings.
  [succeeded] Step 4 - Feedback relay   Prepared feedback for fix cycle 1.

Cycle 1 - Fix cycle 1
  [succeeded] Step 1 - Implementer      Finished fix cycle 1.
  [succeeded] Step 2 - Build            Build passed.
  [in progress] Step 3 - Review         Running in parallel.
    [in progress] Reviewer A            Checking the implementation.
    [in progress] Reviewer B            Checking the implementation.
```

### Expansion Behavior

Default expansion should optimize for operational scanning:

- Setup is expanded while running and after failure.
- Current cycle is expanded.
- Terminally failed cycles are expanded.
- Completed passing cycles collapse their substeps once the cycle is no longer current.
- Completed cycles with feedback relayed collapse their substeps once a later cycle starts.
- Parallel child rows are expanded when running or failed.
- Users may manually re-expand a completed cycle to inspect its substeps.

The first implementation should still honor completed-cycle collapse, because that is the main behavior that keeps long loops scannable.

### Inspector Behavior

- Leaf rows open the existing `WorkflowStepInspector`.
- Parent rows toggle expansion and show aggregate status inline.
- Parent rows do not open `WorkflowStepInspector` in the first implementation.
- Cycle rows should not replace the step inspector with full logs.
- Debug log reveal behavior must remain available.

## Functional Requirements

- **FR-1:** The run updates UI must render workflow setup separately from repeated cycles.
- **FR-2:** The UI must order repeated workflow work by actual cycle sequence, not by phase family.
- **FR-3:** The UI must show nested indentation for cycle steps and parallel child steps.
- **FR-4:** The UI must show aggregate status for setup, cycle groups, and parallel parent steps.
- **FR-5:** The UI must preserve click-through inspection for individual executable steps.
- **FR-6:** The UI must keep full logs secondary to summarized timeline rows.
- **FR-7:** The UI must cap expandable nesting depth so deeply nested workflow structure is summarized instead of rendered as unbounded indentation.
- **FR-8:** The UI must collapse substeps for completed non-current cycles by default.
- **FR-9:** The UI must distinguish terminal failures from normal review feedback that has been relayed into a continuing fix cycle.
- **FR-10:** Parent rows must toggle expansion and must not open leaf-step inspectors in the first implementation.

## Acceptance Criteria

- **AC-1.1** (`FR-1`): Given a run with plan validation and build command setup records, when the run updates UI renders, then those records appear under `Setup` rather than inside a review cycle.
- **AC-2.1** (`FR-2`): Given a run with initial implementation and two fix cycles, when the run updates UI renders, then each cycle shows `Implementer -> Build -> Review -> Feedback relay` in that order.
- **AC-2.2** (`FR-2`): Given multiple cycles, when the run updates UI renders, then all records for cycle 0 appear before cycle 1, and all records for cycle 1 appear before cycle 2.
- **AC-3.1** (`FR-3`): Given reviewer A and reviewer B records for the same cycle, when the run updates UI renders, then both reviewer rows appear indented under a shared `Step 3 - Review` parent.
- **AC-4.1** (`FR-4`): Given one running child under a cycle, when the cycle row renders, then the cycle status is in progress.
- **AC-4.2** (`FR-4`): Given failed reviewer children and no running children, when the review parent renders, then the review parent status is failed.
- **AC-4.3** (`FR-4`): Given reviewer A failed and reviewer B is still running, when the review parent renders, then its summary reports the mixed child state.
- **AC-5.1** (`FR-5`): Given a user clicks `Reviewer A`, when the inspector opens, then it shows Reviewer A's prompt/output record rather than the whole cycle log.
- **AC-6.1** (`FR-6`): Given full logs exist, when the run updates UI renders, then logs remain behind the existing disclosure or debug-log reveal surface.
- **AC-7.1** (`FR-7`): Given workflow records with hierarchy deeper than depth 2, when the run updates UI renders, then only depths 0 through 2 are expandable and deeper records are summarized by the nearest visible depth-2 parent.
- **AC-8.1** (`FR-8`): Given cycle 0 completed and cycle 1 is current, when the run updates UI renders, then cycle 0 appears as a collapsed cycle summary by default.
- **AC-8.2** (`FR-8`): Given a completed collapsed cycle, when the user expands it, then its direct substeps become visible without expanding deeper than the maximum depth.
- **AC-9.1** (`FR-9`): Given cycle 0 had blocking reviewer findings, feedback relay succeeded, and cycle 1 started, when cycle 0 renders, then cycle 0 is shown as `needs fix` or equivalent continuing-feedback state rather than terminally failed.
- **AC-9.2** (`FR-9`): Given a build failed and the workflow stopped because no fix cycle will run, when the cycle renders, then the cycle is shown as terminally failed and expanded by default.
- **AC-10.1** (`FR-10`): Given a user clicks a cycle row or review parent row, when the row is expandable, then the click toggles expansion instead of opening `WorkflowStepInspector`.

## Product Constraints For Implementation

- Treat the timeline as an operational surface. Prefer compact rows, clear status icons, and short summaries.
- Do not render repeated cycles as large accent tiles.
- Do not inline full logs inside cycle groups.
- Preserve the current side inspector pattern.
- Cap timeline indentation at depth 2.
- Collapse completed non-current cycles by default, including cycles where feedback was relayed and a later cycle continued.
- Keep current cycles and terminally failed cycles expanded by default.
- Prefer explicit workflow record metadata over parsing human-readable summaries when changing the model is reasonable.
- If using a derived grouping layer first, keep it local to run-output projection so it can be replaced by explicit metadata later.

## Technical Design Gate

| Field | Value |
| --- | --- |
| Separate technical design required? | Yes |
| Rationale | The required behavior depends on cycle identity, parent/child relationships, sequence ordering, max depth, aggregate status, and collapse state. The technical design must choose either a narrowly scoped Implementation Review Loop projection from today's records or explicit workflow record metadata. |
| Plan link | [Plan-0009. Nested Workflow Cycle Timeline](../plans/0009-nested-workflow-cycle-timeline-plan.md) |
| Blocks implementation until resolved? | Yes |
| Owner | Hephaestus engineering |

### Open Technical Questions

| Question | Owner | Blocks Implementation? | Resolve In PRD/ADR/Plan | Resolution |
| --- | --- | --- | --- | --- |
| Should cycle and parent relationships be explicit fields on `WorkflowStepRecord`? | Engineering | Yes | Plan | Resolved in [Plan-0009](../plans/0009-nested-workflow-cycle-timeline-plan.md): use optional explicit metadata on `WorkflowStepRecord`, with a local UI projection for aggregate rows and collapse behavior. |
| Should collapsed state be persisted per run? | Engineering | No | Future PRD/Plan | First slice can use local view state or default expansion only. |
| Should parent rows be selectable? | Engineering/Product | No | Implementation | Resolved for this PRD: parent rows toggle expansion; leaf rows open inspectors. |
| What exact maximum depth should general workflow timelines support? | Engineering/Product | No | Implementation | Resolved for this PRD: use depth 0 through depth 2. Revisit only if a concrete workflow needs more. |
| Should M1 use hardcoded Implementation Review Loop projection or explicit metadata? | Engineering | Yes | Plan | Resolved in [Plan-0009](../plans/0009-nested-workflow-cycle-timeline-plan.md): use explicit metadata populated by `WorkflowExecutor`; keep parsing/title-based grouping only as legacy fallback. |

## Milestones

| Milestone | Outcome | Included FRs | Excluded Scope | Exit Criteria | Dependencies |
| --- | --- | --- | --- | --- | --- |
| M1 | Correct grouped timeline projection | FR-1, FR-2, FR-3 | Persisted collapse state, arbitrary graph support | Setup, cycles, and reviewer children render in correct hierarchy/order | Existing step records |
| M2 | Aggregate statuses, collapse rules, and inspector polish | FR-4, FR-5, FR-6, FR-7, FR-8, FR-9, FR-10 | Retry controls, duration bars | Parent statuses match child state, completed cycles collapse by default, max depth is bounded, normal feedback cycles are not terminal failures, and leaf clicks open correct inspector records | M1 |

## Validation Plan

### Pre-Implementation Validation

- Confirm sample runs with at least two repeated cycles.
- Confirm the UI can represent both reviewer failures and active parallel review.

### Implementation Validation

- Add focused unit coverage for grouping/order projection if the grouping logic is extracted.
- Add or update preview/sample data for:
  - no records,
  - one passing cycle,
  - multiple failing cycles,
  - active parallel reviewers,
  - completed collapsed cycles,
  - completed feedback cycles that collapsed after a later fix cycle started,
  - terminal build or implementation failure,
  - a deeper-than-supported hierarchy summarized at the max depth.
- Build the macOS app:

```bash
xcodebuild -project Hephaestus.xcodeproj -scheme Hephaestus -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO build
```

### Ship Criteria

- Repeated cycles are visually grouped and ordered by cycle.
- Parallel reviewers are nested under a shared review parent.
- Current cycle and failed cycle states are scannable without opening full logs.
- Existing debug log and step inspector workflows still work.

## Notes

This PRD intentionally stops short of requiring a general graph renderer. The immediate problem is the implementation-review loop: repeated sequential cycles with one known parallel review phase.

**Last Updated:** 2026-05-06
