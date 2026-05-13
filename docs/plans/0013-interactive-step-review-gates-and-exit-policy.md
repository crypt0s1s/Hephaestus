# Interactive Step Review Gates And Exit Policy

## Context

The planning review workflow is testing interactive workflow pauses, user-controlled handoff, and
future workflow-builder IO. The current implementation proved the basic UI path, but its
`draftProvenance` model encodes the wrong rule: it blocks submission because a draft was generated
by an agent, when the real requirement is that the user explicitly reviews the interactive step
output before the workflow advances.

This plan replaces source-specific draft rules with reusable building blocks:

- host-owned output candidates
- required output validation
- explicit user review gates
- agent turn settlement adapters
- deterministic acceptance and promotion into the next workflow stage

The first implementation remains planning-specific, but the boundaries should be decoupled enough
to become generic interactive workflow primitives later.

Related PRD: [PRD-0011. Interactive Planning Review Workflow](../prd/0011-interactive-planning-review-workflow.md)

## Goals

- Remove `draftProvenance` and edit-required semantics.
- Treat agent output, user edits, and manually typed drafts as sources for the same host-owned
  output candidate.
- Require explicit user acceptance before the planning workflow starts automated review cycles.
- Distinguish initial draft acceptance from final workflow acceptance after automated review.
- Add host-enforced agent turn settlement so a turn can be marked incomplete when required output is
  missing or invalid.
- Keep the model compatible with both loose normal-harness interactions and stricter future
  capability-restricted interactions.
- Keep temporary planning-specific extraction, prompts, validators, and paths outside generic
  workflow runner models.

## Non-Goals

- Do not build the full generic workflow builder.
- Do not require interactive steps to be file-write-only handoff systems.
- Do not require all interactive agent turns to run in a restricted sandbox mode.
- Do not add automatic corrective agent turns in this slice.
- Do not make transcript parsing the durable output contract.
- Do not make planner-response output a hidden replacement for the accepted plan without an explicit
  host-owned output transition.

## Current Problems

- `draftProvenance` is a source-specific UI flag, not a workflow transition.
- `canSubmit` currently means "the user edited the generated draft"; it should mean "the required
  output is valid and waiting for user acceptance."
- The label "Submit Plan" hides two different gates:
  - accepting the draft so automated review can begin
  - accepting the workflow after automated review completes
- The current planning turn asks the agent for a plan but does not have a host-owned settlement
  contract for required outputs.
- Missing or invalid output states need actionable user recovery paths.
- Automated review currently risks continuing to use the original submitted output even when later
  planner-response work proposes a revised latest plan.

## Design Principles

- **Host owns workflow state.** Agents may propose, write, or stream content, but the host validates,
  records, and promotes workflow outputs.
- **Review gates belong to steps.** A user review requirement is inferred from the interactive step
  policy, not stored as provenance on the draft.
- **Make invalid states hard to represent.** Output readiness, user review, and acceptance should be
  owned by a gate aggregate instead of loosely synchronized booleans.
- **Separate output settlement from conversational behavior.** Required outputs and validators are
  host-enforceable; requirements such as "must ask a question" need separate turn policy and
  structured evidence before they can block workflow progress.
- **Prototype honestly.** Planning-specific names are acceptable for the first slice, but temporary
  coupling should sit in planning workflow services, not core runner models.
- **Acceptance is a transaction.** The exact candidate snapshot accepted by the user is the only
  content that can be promoted into the next stage.

## Type Ownership

Keep the first implementation conservative about what becomes generic.

Generic workflow runner types may include:

- neutral output IDs and required-output specs
- gate state and acceptance records that do not mention planning, Codex, markdown, or files
- provider-neutral turn result summaries
- projected UI/run-state summaries

Planning-specific types must stay under `PlanningReviewWorkflow` until another workflow needs them:

- prompts and Codex text parsing
- markdown validators
- `.hephaestus/planning-review/` paths
- draft-plan artifact storage
- planner/reviewer names and cycle rules
- request-changes prompt shaping

If a model needs `String` markdown content, `text/markdown`, or a project-relative export path to
make sense, treat it as a text-output or planning implementation detail unless the type name says so.

## Proposed Building Blocks

### Output Candidate

An output candidate is host-owned content for one required output. It may be seeded by the agent,
loaded from a host-owned artifact, pasted manually, or edited by the user. `source` is
informational/debugging metadata. It must not decide whether the workflow can advance.

```swift
struct InteractiveOutputCandidate: Equatable {
  let outputID: String
  var contentType: String
  var content: String
  var source: CandidateSource
  var revision: Int
}

enum CandidateSource: Equatable {
  case empty
  case agent
  case user
  case importedArtifact(projectRelativePath: String)
}
```

### Output Set

The first planning workflow requires one output, but the reusable primitive should not bake in
single-output assumptions. The interaction owns a set keyed by required output ID. Planning can
project the `draft-plan` candidate into the editor UI.

```swift
struct InteractiveOutputSet: Equatable {
  var candidatesByID: [String: InteractiveOutputCandidate]

  func candidate(id: String) -> InteractiveOutputCandidate?
}
```

If this proves too heavy during implementation, the fallback should be a planning-specific
`PlanningDraftCandidate` service, not a generic single-output model pretending to be reusable.

### Required Output Specification

Required outputs describe what the step needs before it can enter user review.

```swift
struct InteractiveRequiredOutput: Equatable {
  let id: String
  let title: String
  let contentType: String
  let validatorID: String?
  let exportPath: String?
}
```

For planning:

```swift
InteractiveRequiredOutput(
  id: "draft-plan",
  title: "Draft Plan",
  contentType: "text/markdown; artifact=plan",
  validatorID: "planning-draft",
  exportPath: ".hephaestus/planning-review/<session-id>/draft-plan.md"
)
```

The `exportPath` is host-owned. The first implementation can still instruct the planner to provide
structured markdown, but the host writes/updates draft and accepted artifacts after validation.
Agent file writes can be revisited later with explicit sandbox and approval policy.

### Initial Review Gate State

Use one aggregate for the initial interactive step so the UI cannot represent impossible states such
as "accepted with invalid output".

```swift
enum InteractiveStepGateState: Equatable {
  case interacting
  case needsOutput(RequiredOutputIssue)
  case awaitingUserReview(ReadyOutputSet)
  case accepted(AcceptanceRecord)
}

struct RequiredOutputIssue: Equatable {
  let outputID: String
  let title: String
  let message: String
  let recoveryActions: [InteractiveRecoveryAction]
}

enum InteractiveRecoveryAction: Equatable {
  case requestAgentRevision(outputID: String)
  case editOutput(outputID: String)
  case pasteOutput(outputID: String)
}

struct ReadyOutputSet: Equatable {
  let outputsByID: [String: InteractiveStepOutput]
  let candidateRevisionsByID: [String: Int]
}
```

Transitions should be explicit methods on a planning-specific gate service in this slice:

- `settleTurn(result:outputSet:)`
- `validateOutputs(outputSet:)`
- `acceptDraftForReview(outputSet:expectedRevision:)`
- `requestDraftChanges(feedback:outputSet:)`
- `returnToInteraction()`

### Acceptance Record

Acceptance is a transaction over a candidate snapshot. The accepted revision and content hash prevent
later planner output from silently changing what the user approved.

```swift
struct AcceptanceRecord: Equatable {
  let acceptedOutputsByID: [String: InteractiveStepOutput]
  let acceptedRevisionsByID: [String: Int]
  let contentHashesByID: [String: String]
  let acceptedAt: Date
  let idempotencyKey: String
}
```

The planning store should expose one atomic operation for user acceptance:

```swift
struct PlanningDraftAcceptanceRequest: Equatable {
  let candidate: InteractiveOutputCandidate
  let expectedRevision: Int
  let idempotencyKey: String
}

protocol PlanningDraftOutputStoring {
  func saveDraftSnapshot(_ candidate: InteractiveOutputCandidate) throws -> InteractiveStepArtifact
  func acceptDraftForReview(_ request: PlanningDraftAcceptanceRequest) throws -> AcceptanceRecord
}
```

`acceptDraftForReview` validates, writes/promotes the accepted `plan.md`, records the accepted
revision/hash, and returns the output that automated review will consume. Starting automation should
key off the returned `AcceptanceRecord` so the same user action cannot start duplicate cycles.

Retry and failure rules:

- same `idempotencyKey` and same content hash returns the existing `AcceptanceRecord`
- same `idempotencyKey` and different content hash fails without writing
- stale `expectedRevision` fails without writing
- validation failure fails without writing
- artifact write failure does not start automation
- automation start records the `AcceptanceRecord.idempotencyKey`; a later retry must not start a
  second automation run for the same acceptance

### Step Policy

Policy defines whether review is required, which outputs must exist, and how to handle unsatisfied
turn criteria.

```swift
struct InteractiveStepPolicy: Equatable {
  let requiredOutputs: [InteractiveRequiredOutput]
  let userReview: UserReviewPolicy
  let turnSettlement: TurnSettlementPolicy
}

enum UserReviewPolicy: Equatable {
  case none
  case requiredBeforeAdvance
}

struct TurnSettlementPolicy: Equatable {
  let requiredOutputIDs: [String]
  let behaviorOnUnsatisfiedCriteria: UnsatisfiedCriteriaBehavior
}

enum UnsatisfiedCriteriaBehavior: Equatable {
  case blockForUserAction
  case runCorrectionTurn(maxAttempts: Int)
}
```

The first slice should use `.blockForUserAction`.

### Turn Settlement Adapter

The reusable runtime boundary is a settlement service, not prompt parsing inside the model.

```swift
struct InteractiveTurnResult: Equatable {
  let textOutput: String
  let exitCode: Int
  let metadata: [String: String]
}

struct InteractiveTurnSettlement {
  let updatedOutputs: InteractiveOutputSet
  let gateState: InteractiveStepGateState
}

protocol InteractiveTurnSettling {
  func settle(
    turnResult: InteractiveTurnResult,
    currentOutputs: InteractiveOutputSet,
    policy: InteractiveStepPolicy
  ) throws -> InteractiveTurnSettlement
}
```

The first implementation should add a clearly named planning adapter, for example
`PlanningReviewPrototypeTurnSettlement`, that parses the Codex text result for fenced markdown or
plain markdown and updates the `draft-plan` candidate. That is a temporary replacement point. Later,
a structured backend event or typed tool output can replace only this adapter.

The harness adapter or interactor should translate current backend events into
`InteractiveTurnResult` before settlement. Generic settlement must not depend on Codex event names or
raw `ProcessResult`.

Planner turns may run read-only. Host-owned validation and artifact writes happen after the turn in
the output store, not inside the agent process.

Host-enforceable settlement criteria in this slice:

- required candidate content exists
- candidate passes the planning markdown validator
- the turn can produce `needsOutput` with recovery actions when content is absent or invalid

Promotion into `plan.md` is not a turn settlement criterion. Promotion happens only after the user
accepts a ready candidate.

Conversational requirements such as "must ask a question" are useful, but should be separated from
output settlement until we have structured evidence. The first implementation may include prompt
instructions for question-asking, but should not block workflow progress on transcript heuristics.

## Planning Workflow Shape

1. User interacts with the planner.
2. Planner response streams into the notes transcript.
3. `PlanningReviewPrototypeTurnSettlement` extracts proposed plan markdown from the turn result and
   updates the `draft-plan` candidate.
4. Host validates the output set.
5. If missing or invalid, the initial gate becomes `needsOutput`.
6. If valid, the initial gate becomes `awaitingUserReview`.
7. User can:
   - `Accept draft for review`: atomically validate/promote the current candidate and start
     automation from the accepted output.
   - `Ask for changes`: provide feedback, preserve the current candidate as context, and return to
     interaction.
   - edit or paste manually, then accept once validation passes.
8. Automated review cycles run against the current latest plan output.
9. Planner-response work produces a reviewed-plan candidate for the cycle. If the candidate validates,
   the host promotes it to `cycles/<cycle>/plan.md` and updates the workflow's latest plan pointer. If
   it is missing or invalid, the latest plan remains the previous valid plan and the cycle records the
   planner response as advisory.
10. Workflow returns to a separate final review gate.
11. User can `Accept reviewed workflow`, request another automated review cycle from the latest
    valid plan, or continue planning.

## User-Facing States And Actions

### Initial Draft Gate

| Gate State | UI Message | Primary Action | Secondary Actions |
| --- | --- | --- | --- |
| `interacting` | Planning with the agent. | Send note | Edit draft manually |
| `needsOutput` missing | A draft plan is required before review can continue. | Ask planner to try again | Write draft manually |
| `needsOutput` invalid | The draft needs validation fixes before review. | Ask planner to fix | Edit draft |
| `awaitingUserReview` | Review the draft plan before automated review starts. | Accept draft for review | Ask for changes |
| `accepted` | Draft accepted. Automated review is running. | None | View run updates |

The button label for the first gate should be **Accept draft for review** with helper text:
"Starts automated review."

### Final Workflow Gate

The final gate is separate from the initial draft gate. It reviews the latest workflow-owned plan
state and the feedback trail after automated cycles.

```swift
enum PlanningReviewFinalGateState: Equatable {
  case automationRunning
  case awaitingFinalReview(FinalReviewSummary)
  case finalAccepted(FinalAcceptanceRecord)
  case continuingPlanning
  case runningAdditionalCycle(cycle: Int)
}
```

| Final State | UI Message | Primary Action | Secondary Actions |
| --- | --- | --- | --- |
| `automationRunning` | Automated review cycles are running. | None | View run updates |
| `awaitingFinalReview` | Review the latest plan and feedback trail. | Accept reviewed workflow | Continue planning, Run another cycle |
| `finalAccepted` | Workflow accepted. | None | View accepted plan |
| `continuingPlanning` | Planning has reopened with review context. | Send note | Edit draft manually |
| `runningAdditionalCycle` | Another review cycle is running. | None | View run updates |

`FinalReviewSummary` should reference:

- latest valid plan output
- accepted draft artifact path
- consolidated feedback links
- planner responses
- cycle count

The latest plan source is deterministic:

1. Initially, latest plan is the user-accepted draft.
2. After each planner-response cycle, latest plan advances only if the host validates and promotes a
   revised plan candidate.
3. If a planner-response cycle is advisory or invalid, latest plan remains the previous valid plan.
4. Final acceptance accepts the latest valid plan and the review history.
5. Additional cycles consume the latest valid plan.
6. Continue planning seeds the editor candidate from the latest valid plan and passes consolidated
   feedback history as planner context.

## Request Changes Flow

`Ask for changes` should be an explicit transition:

1. User enters feedback in a dedicated change-request composer shown while awaiting draft review.
2. The action is disabled until that feedback is non-empty.
3. Host sends the feedback plus the current candidate content to the planner.
4. Gate returns to `interacting` while the planner works.
5. Existing candidate remains visible but is not promoted.
6. After the turn, host validates the updated candidate and returns to `needsOutput` or
   `awaitingUserReview`.

If the user edited the draft before asking for changes, those edits are sent as context. The first
slice should not require immediate writeback to the draft artifact; the editor buffer remains the
source of truth until acceptance.

## Manual Recovery Flow

Manual edits and paste operations are first-class recovery paths:

1. User edits or pastes content for an output.
2. Host increments that output candidate's revision and sets `source = .user`.
3. Host validates the affected output set.
4. If required outputs are valid, the gate becomes `awaitingUserReview`.
5. If any required output is missing or invalid, the gate remains `needsOutput` with a specific
   recovery message.

Manual recovery does not require an agent turn. It also does not bypass user acceptance.

## Artifact Ownership

The host owns draft and accepted artifacts:

- `draft-plan.md`: optional exported snapshot of the current output candidate.
- `plan.md`: accepted artifact promoted into automated review.

Acceptance must validate and promote exactly the editor/output-candidate content. The promotion
operation records the accepted revision and content hash so later agent output cannot silently change
what was accepted.

Suggested planning-specific layout:

```text
.hephaestus/
  planning-review/
    <session-id>/
      draft-plan.md
      accepted/
        plan.md
        acceptance.json
      cycles/
        0/
          consolidated-review.md
          planner-response.md
        1/
          consolidated-review.md
          planner-response.md
```

This keeps filesystem details out of the model and lets future implementations replace markdown
files with encoded workflow messages or other output stores.

## Projection Rules

Projection should be a small service that turns interaction/runtime state into run-update records.
Views should consume projected state rather than recomputing workflow rules from transcript text.

Projection output should have a named shape:

```swift
struct WorkflowInteractionProjection: Equatable {
  let visibleStatus: String
  let pauseReason: PauseReason?
  let requiredAction: WorkflowInteractionRequiredAction?
  let availableActions: [WorkflowInteractionAvailableAction]
  let stepRecordStatus: WorkflowStepStatus
  let stepSummary: String
}
```

Projection output includes:

- visible status
- pause reason
- required user action
- available actions
- step record status

`WorkflowStepRecord` remains the timeline/inspector projection target. If pause reason and
available actions do not belong in `WorkflowStepRecord`, keep them in `WorkflowInteractionProjection`
and render them in the interaction panel.

Interaction activity is separate from gate state:

```swift
enum InteractionActivity: Equatable {
  case waitingForUser
  case agentTurnRunning
  case settlingTurn
}
```

Projection consumes both gate state and activity so `interacting + waitingForUser`,
`interacting + agentTurnRunning`, `awaitingUserReview`, and `needsOutput` produce visibly different
states.

Initial gate projection:

- `interacting`: interactive step record is `inProgress`; pause reason is user/agent interaction.
- `needsOutput`: interactive step record is `needsFix`; required action names the missing or invalid
  output.
- `awaitingUserReview`: interactive step record is `inProgress`; required action is user acceptance.
- `accepted`: interactive step record is `succeeded`; automation records begin after this point.

Final gate projection:

- `automationRunning`: automated cycle records are `inProgress`.
- `awaitingFinalReview`: final review step record is `inProgress`; required action is final user
  decision.
- `finalAccepted`: final review step record is `succeeded`.
- `continuingPlanning`: planning step record is reopened with review context.
- `runningAdditionalCycle`: an explicit additional cycle record is `inProgress`.

## Implementation Plan

### 1. Add Gate Service And Compatibility Projection

- Add planning-specific gate service and output set state.
- Make the candidate/gate aggregate the authoritative source immediately.
- Keep `draftProvenance`, `draftRequiresUserEdit`, and old `canSubmit` only as derived compatibility
  output while the UI is migrated.
- Add a single compatibility projection for existing UI booleans.
- Move button enablement and `canSubmit` behavior to the projection immediately.
- Add tests proving old provenance cannot affect submit enablement or promotion.
- Add tests for new gate transitions before deleting old behavior.

### 2. Add Planning Turn Settlement Adapter

- Add `PlanningReviewPrototypeTurnSettlement`.
- Parse current Codex text output as a temporary adapter contract.
- Keep prompt text, fenced markdown extraction, and planning validation outside
  `WorkflowRunnerModel`.
- Prove planner turns can run read-only while host settlement and artifact storage handle writes.

### 3. Host-Owned Candidate Validation

- Treat editor content as the `draft-plan` candidate.
- On planner turn completion, update the candidate from proposed output when available.
- On manual edit, update candidate revision and revalidate.
- On invalid/missing candidate, show `needsOutput` with recovery actions.

### 4. Accept And Promote Draft

- On `acceptDraftForReview`, validate current candidate again.
- Call the atomic output-store acceptance operation with expected revision and idempotency key.
- Promote current candidate to `plan.md`.
- Create `InteractiveStepOutput` from the promoted artifact.
- Start automated review cycles exactly once from the returned acceptance record.

### 5. Request Changes

- Add explicit `requestDraftChanges(feedback:)`.
- Disable the action until feedback is non-empty.
- Send feedback and current candidate content to the planner.
- Preserve candidate during the turn.
- Re-settle the gate after the turn.

### 6. Model Final Review Gate

- Add final gate state after automated cycles complete.
- Add workflow-owned latest-plan state:
  - accepted draft is the initial latest plan
  - valid planner-response revised plans advance latest plan
  - invalid/advisory planner responses leave latest plan unchanged
- Ensure `Accept reviewed workflow`, `Continue planning`, and `Run another cycle` operate on the
  latest valid plan.

### 7. Remove Draft Provenance

- Remove `DraftProvenance`.
- Remove `draftRequiresUserEdit`.
- Delete provenance-specific tests and replace them with gate-state tests.

### 8. Project Into Run Updates

- Route initial and final gate states through the projection service.
- Keep projection separate from chat transcript text.
- Make waiting-for-user-review visually distinct from agent-turn-running.

## Tests

Add focused unit tests for:

- valid candidate enters `awaitingUserReview`
- accept as-is promotes candidate and starts automation
- user edit before accept promotes edited content
- missing output enters actionable `needsOutput`
- invalid output enters actionable `needsOutput`
- manual paste can recover from missing/invalid output
- ask-for-changes requires non-empty feedback
- ask-for-changes returns to `interacting` without promoting
- automation has not started before draft acceptance
- accepting draft starts automation exactly once
- acceptance validates the exact content that is promoted
- later planner output cannot mutate an already accepted revision
- settlement adapter parses fenced markdown and plain markdown
- read-only planner turns still result in host-owned artifact writes
- old provenance cannot drive UI after the projection switch
- editor/candidate divergence is impossible or reconciled deterministically
- stale revision acceptance fails without writing
- same idempotency key and same content returns the existing acceptance
- same idempotency key with different content fails
- acceptance artifact write failure does not start automation
- app reload or retry does not restart automation for an already accepted record
- final workflow acceptance remains distinct from draft acceptance
- another automated cycle starts from the documented latest-plan source
- projection differentiates `needsOutput`, `awaitingUserReview`, agent-turn-running, and final review

Update UI tests for:

- valid draft -> `Accept draft for review` -> automated review starts
- invalid/missing draft shows recovery actions
- ask-for-changes is disabled without feedback
- final review gate exposes accept, continue planning, and run another cycle actions

## Validation

- `./scripts/lint.sh`
- `git diff --check`
- App build:
  `xcodebuild -project Hephaestus.xcodeproj -scheme Hephaestus -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO build`
- Full unit tests:
  `xcodebuild -project Hephaestus.xcodeproj -scheme Hephaestus -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO MACOSX_DEPLOYMENT_TARGET=26.1 -only-testing:HephaestusTests test`
- Focused unit tests while iterating:
  `xcodebuild -project Hephaestus.xcodeproj -scheme Hephaestus -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO MACOSX_DEPLOYMENT_TARGET=26.1 -only-testing:HephaestusTests/PlanningReviewWorkflowTests test`
- Focused UI tests with normal signing:
  `xcodebuild -project Hephaestus.xcodeproj -scheme Hephaestus -destination 'platform=macOS' -only-testing:HephaestusUITests/HephaestusUITests/testPlanningReviewWorkflowStartsInteractiveWaitingState test`
