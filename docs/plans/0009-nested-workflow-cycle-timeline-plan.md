# Nested Workflow Cycle Timeline Plan

**Status:** Proposed
**Date:** 2026-05-06
**Related PRD:** [PRD-0010. Nested Workflow Cycle Timeline](../prd/0010-nested-workflow-cycle-timeline.md)
**Related ADRs:** None

## 1. Purpose

PRD-0010 needs the Implementation Review Loop timeline to read as ordered cycles, not as repeated flat phases. This plan chooses a small metadata-backed implementation path that keeps the existing step inspector and log surfaces intact while making cycle order, parent rows, reviewer parallelism, and collapse behavior explicit.

This is not an ADR. The decision here is scoped to the first implementation slice for the current app target.

## 2. Current Code Facts

- `WorkflowRunOutput` builds rows through `TimelineDisplayRowsBuilder`, and leaf rows open `WorkflowStepInspector` by storing `selectedStepID`.
- `WorkflowStepRecord` currently has `id`, `title`, `status`, `summary`, previews, and a flat `sortOrder`.
- `WorkflowExecutor.runImplementationReviewLoop` emits setup records, then loops over `cycle in 0...request.maxReviewCycles`.
- Current cycle sorting uses phase-family offsets such as `10 + cycle`, `20 + cycle`, `30 + cycle`, and `40 + cycle`, so multiple cycles are ordered as implementers, builds, reviewers, then feedback rather than as complete cycle groups.
- `WorkflowRunnerModel` only transports `stepRecords` from progress/result into state; it should not need cycle-specific orchestration logic.
- `ExternalWorkflowRunner` also constructs `WorkflowStepRecord` values and must keep compiling without being forced to know about Implementation Review Loop-specific metadata.

## 3. Decision

Use explicit optional metadata on `WorkflowStepRecord`, then build a testable timeline projection for `WorkflowRunOutputView`.

Do not implement the nested timeline by parsing titles or summaries. The executor already knows cycle number, setup-vs-cycle grouping, reviewer parentage, phase order, and execution order at record construction time. Encoding that as metadata is less brittle and fixes the core ordering bug at the source. The local projection should remain responsible for aggregate rows, collapse state, and max-depth clipping because those are view concerns.

Keep all metadata optional with defaults so existing step records remain compatible:

```swift
enum WorkflowStepRecordCycleOutcome: Equatable {
    case running
    case succeeded
    case needsFix
    case terminalFailed
}

struct WorkflowStepRecordHierarchy: Equatable {
    var groupID: String?
    var parentID: String?
    var cycleIndex: Int?
    var depth: Int
    var phaseOrder: Int
    var sequenceOrder: Int
    var cycleOutcome: WorkflowStepRecordCycleOutcome?
}
```

The exact Swift names can change during implementation, but the fields should cover:

- `groupID`: `"setup"` or `"cycle-\(cycle)"`.
- `parentID`: parent row ID for reviewer children, for example `"cycle-0-review"`.
- `cycleIndex`: `nil` for setup, `0` for initial implementation, `1...` for fix cycles.
- `depth`: leaf record depth before UI clipping; setup leaves and cycle leaves are depth 1, reviewer leaves are depth 2.
- `phaseOrder`: stable order inside a group: plan validation/build command, implementer/build/review/feedback.
- `sequenceOrder`: monotonic emitted execution order for deterministic tie-breaking. It is assigned once when a logical record is first inserted and is preserved on later `upsertStep` updates.
- `cycleOutcome`: optional cycle-level outcome hint. It is populated on records that can determine the cycle aggregate, especially feedback relay and terminal failure paths. This lets the UI distinguish `needs fix` from terminal failure without guessing from child status alone.

`needsFix` is a display-level cycle aggregate state, not a new `WorkflowStepRecordStatus`. Reviewer children and the `Step 3 - Review` parent can still render as `failed`; the enclosing cycle renders as `needsFix` after feedback has been relayed and the workflow is continuing into a later fix cycle.

Continuing feedback is explicit:

- A cycle is `needsFix` when reviewer/build failure feedback was prepared successfully and either a later cycle has started or the executor knows a later cycle is ready to start.
- A cycle is `terminalFailed` when implementation/build/review/feedback failure stops the workflow with no continuing fix cycle.
- A cycle is `succeeded` when the build and required reviewers pass and the workflow completes.
- A cycle is `running` while its current child work is in progress.

Do not infer terminal-vs-continuing state only from failed children. Failed reviewer/build children are common inside a healthy feedback loop.

Implementation note: the executor currently creates feedback records before some max-cycle terminal checks. Populate `terminalFailed` only after the executor has decided no later fix cycle will run, or explicitly update the relevant cycle metadata after that decision.

## 4. Shippable Implementation Scope

PRD-0010 should not ship as a partial grouped-only timeline. The first shippable implementation must include grouping, aggregate status, completed-cycle collapse, terminal-vs-feedback distinction, and parent-row toggles.

If the work is split into multiple PRs, an initial scaffolding PR may add metadata and projection tests, but it should be treated as non-shippable until the full behavior below is complete.

## 5. Implementation Steps

1. Extend `WorkflowStepRecord` with optional hierarchy metadata and a nonisolated initializer defaulting metadata to `nil` or flat values.
2. Update `WorkflowExecutor.upsertStep` to accept hierarchy metadata and assign it for all Implementation Review Loop records. On updates, preserve first-insert `sequenceOrder` and existing hierarchy unless a caller explicitly replaces those fields.
3. Populate `cycleOutcome` or equivalent cycle summary information in the executor:
   - mark cycles with relayed feedback as `needsFix` before continuing,
   - mark max-cycle build/review failures and implementer failures as `terminalFailed`,
   - mark the passing final cycle as `succeeded`,
   - keep the active cycle `running`.
4. Replace the current phase-family `sortOrder` values for loop records with cycle-major ordering, or derive display order from metadata in the projection. Recommended display key:

```text
setup: sequenceOrder
cycle: cycleIndex, phaseOrder, parent/child order, sequenceOrder
```

5. Extract the projection into an internal pure type that tests can call directly. Do not leave the main grouping logic as a `private` helper inside `WorkflowRunOutputView.swift`. A practical shape:

```swift
struct WorkflowTimelineNode: Identifiable, Equatable {
    enum Kind { case group, parent, leaf, summary }
    var id: String
    var label: String
    var detail: String?
    var status: TimelineDisplayStatus
    var depth: Int
    var isExpandable: Bool
    var record: WorkflowStepRecord?
    var children: [WorkflowTimelineNode]
}

struct WorkflowTimelineProjection {
    var nodes: [WorkflowTimelineNode]
}
```

6. Add synthetic parent rows in the projection:
   - `Setup`
   - `Cycle 0 - Initial implementation`
   - `Cycle N - Fix cycle N`
   - `Step 3 - Review` under each cycle when reviewer children exist
7. Aggregate status rules:
   - `inProgress` wins if any child is running.
   - `needsFix` applies only to a cycle group after feedback has been relayed and the workflow is continuing.
   - `failed` applies to failed leaf rows, failed review parents, and terminal cycle failures.
   - `succeeded` when required children succeeded.
   - `pending` when no child has started.
8. Add `needsFix` to `TimelineDisplayStatus` rather than overloading `failed`; map it to existing status icon/color styling in a restrained way. This is display-only and should not become a `WorkflowStepRecordStatus`.
9. Update all exhaustive status switches, including `TimelineStatusIcon` and any status color/label helpers in `WorkflowStepInspectorView.swift` or nearby timeline views.
10. Track collapsed state locally in `WorkflowRunOutput`, keyed by synthetic row ID. Do not persist collapse state.
    - Reset or namespace collapsed state when a new run/result is shown, because synthetic IDs such as `cycle-0` are reused across runs.
    - Default expansion must be recomputed per displayed run before applying any manual expansion overrides.
11. Default expansion:
   - Expand setup while running or failed.
   - Expand the current cycle.
   - Expand terminally failed cycles.
   - Collapse completed non-current cycles, including cycles that successfully relayed feedback into a later fix cycle.
   - Expand reviewer children when running or failed.
12. Parent click behavior:
   - Parent and cycle rows toggle expansion.
   - Leaf rows open `WorkflowStepInspector`.
   - Parent rows do not select or replace the inspector in this slice.
   - This requires row action to be driven by node kind and expandability; rows without records must no longer be blanket-disabled.
13. Keep legacy fallback behavior: if no records have hierarchy metadata, render today's flat `stepRecordRows` path. This protects existing external workflows and any old in-memory results.
14. Cap visible expandable depth at 2. If future metadata reports deeper children, summarize them into the nearest depth-2 row and rely on the inspector/debug log for detail.

## 6. Nested Cycle Handling

Nested cycles are allowed in metadata but are clipped in the main timeline at depth 2. The first implementation only needs to handle the top-level Implementation Review Loop cycle plus the Reviewer A/B parallel group.

If a future step contains its own retry loop, render it as a summary row at depth 2 rather than expanding a deeper tree:

```text
Cycle 1 - Fix cycle 1
  Step 2 - Build
    Build retry loop        2 attempts, passed
```

Detailed nested attempts remain available through the inspector or debug log. This reserves space for future nested cycles without building an arbitrary graph visualizer.

## 7. Exit Criteria

- Setup records render under `Setup`.
- Cycle 0 records render before cycle 1 records.
- Each cycle renders `Implementer -> Build -> Review -> Feedback relay`.
- Reviewer A and Reviewer B render under the review parent.
- Parent rows show aggregate state and mixed reviewer summaries such as `1 running, 1 failed`.
- Completed older cycles collapse by default after a later cycle starts.
- Parent/cycle clicks toggle expansion only.
- Leaf rows still open the existing inspector.
- Terminal failures remain expanded and visibly distinct from normal feedback loops.
- `needsFix` appears only as a continuing cycle aggregate, not as a replacement for failed reviewer rows.
- Deeper-than-depth-2 structure is summarized into the nearest visible depth-2 row.

## 8. Compatibility And Migration

- No persistent migration is needed for existing `stepRecords`; they appear to be run-state values transported through `WorkflowRunProgress` and `ProcessResult`, not a stored schema.
- Keep metadata optional and defaulted so `ExternalWorkflowRunner` and tests that construct `WorkflowStepRecord` directly continue to compile with small initializer updates at most.
- Preserve `sortOrder` for flat consumers. New nested rendering should prefer hierarchy metadata when present and fall back to `sortOrder` when absent.
- Avoid changing `WorkflowRunnerModel` beyond passing through the richer records it already receives.
- Do not change debug log paths, full log disclosure, or inspector data fields.

## 9. Test And Preview Plan

Unit tests:

- Add projection tests for setup grouping, cycle-major ordering, review parent creation, depth clipping, and legacy flat fallback.
- Add executor tests that assert emitted Implementation Review Loop records carry expected `groupID`, `cycleIndex`, `parentID`, `phaseOrder`, `sequenceOrder`, and `cycleOutcome`.
- Add sequence stability tests: repeated `upsertStep` calls update status/summary without changing first-insert `sequenceOrder`.
- Add collapse-default tests against projected nodes: current cycle expanded, completed previous cycle collapsed, continuing feedback cycle collapsed after a later cycle starts, terminal failure expanded, review parent expanded when running/failed.
- Add collapse-state reset or namespacing tests so manual expansion from one run cannot affect another run that reuses synthetic IDs like `cycle-0`.
- Add parent action tests or preview checks: cycle/review rows toggle expansion and do not open `WorkflowStepInspector`; leaf rows open the inspector.
- Add debug-log availability checks so full logs remain secondary and reachable after the timeline refactor.

Preview/manual fixtures:

- Add or extend a `WorkflowRunOutput` preview fixture with setup, two cycles, failed reviewers in cycle 0, feedback relay, and running reviewers in cycle 1.
- Include a terminal build or implementer failure fixture.
- Include a deeper-than-depth-2 nested cycle summary fixture.
- Include one legacy flat fixture so fallback rendering remains inspectable.

Build validation:

```bash
xcodebuild -project Hephaestus.xcodeproj -scheme Hephaestus -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO build
```

State/orchestration validation:

```bash
xcodebuild -project Hephaestus.xcodeproj -scheme Hephaestus -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO MACOSX_DEPLOYMENT_TARGET=26.1 -only-testing:HephaestusTests test
```

## 10. Suggested File Touches

- `Hephaestus/Features/WorkflowRunner/Models/WorkflowRunTypes.swift`: add optional hierarchy metadata.
- `Hephaestus/Features/ImplementationReviewLoop/Runtime/WorkflowExecutor.swift`: populate metadata and fix cycle-major ordering at emission.
- `Hephaestus/Features/WorkflowRunner/Views/WorkflowRunOutputView.swift`: render projected nodes, indentation, collapse state, and parent click handling.
- `Hephaestus/Features/WorkflowRunner/Views/WorkflowStepInspectorView.swift`: update `TimelineStatusIcon` and any exhaustive status switches for display-only `needsFix`.
- A new or extracted workflow timeline projection file near the workflow runner feature, if needed: keep projection internal and pure so tests can instantiate it directly.
- `HephaestusTests/HephaestusTests.swift`: add focused executor/projection tests unless the current reorganization creates a better test file.

## 11. Non-Goals For This Slice

- No persisted collapse state.
- No arbitrary graph visualizer.
- No new ADR.
- No changes to Codex agent execution.
- No full-log inline expansion inside cycle rows.
- No retry or cancellation controls.
