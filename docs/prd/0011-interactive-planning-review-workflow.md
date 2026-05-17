# PRD-0011. Interactive Planning Review Workflow

**Status:** Draft
**Date:** 2026-05-07
**Owner:** Hephaestus engineering
**Related ADRs:** TBD
**Related Plans:** [Interactive Workflow Step Spike](../plans/0010-interactive-workflow-step-spike.md), [Interactive Step Review Gates And Exit Policy](../plans/0013-interactive-step-review-gates-and-exit-policy.md), [Interactive Runner Decoupling Plan](../plans/0014-interactive-runner-decoupling-plan.md)

---

## Summary

Add a concrete planning-review workflow whose primary purpose is to prove Hephaestus can support interactive workflow steps, resumable workflow state, and message passing between automated and interactive sessions. The workflow uses planning as the test vehicle: a user works with an interactive planner session, submits a draft plan into automated reviewer cycles, passes consolidated review feedback back to the planner session, repeats multiple automated refinement cycles, and later returns to an interactive user review step.

This is not primarily a formal planning-product workflow. It is a capability-expansion slice for the future workflow builder, where workflow steps can eventually output encodable objects and consume decodable objects.

## Problem

Hephaestus can run structured automated workflows, but it has not yet proved the harder workflow shape where:

- a workflow pauses for user interaction,
- an interactive session produces a structured output for later steps,
- automated sessions receive that output,
- automated sessions produce review or feedback messages,
- feedback is passed back into an interactive or long-lived session,
- the workflow returns to a later interactive step for human review and continuation.

Without this capability, Hephaestus risks growing one-off workflow runners instead of a workflow model that can eventually support typed step inputs and outputs.

### Background

The implementation-review workflow validates automated implementation/build/review loops. The next capability gap is interactive workflow participation. Planning is a useful concrete workflow because it naturally needs:

- an initial interactive step,
- typed or structured handoff from planner to reviewers,
- reviewer fan-out,
- consolidated feedback,
- planner response to feedback,
- multiple automated cycles,
- a later interactive review step where the user chooses whether to accept or continue.

The planning output is useful, but the larger product goal is to learn how Hephaestus should model interactive steps and cross-session messages.

### Users And Jobs

| User | Job To Be Done | Current Pain | Usage Context |
| --- | --- | --- | --- |
| Hephaestus builder | Prove interactive workflow steps and step-to-step message passing | Current workflows are mostly run-to-completion automation | Expanding the workflow runner toward a builder |
| Workflow author | Understand how future steps will pass structured outputs to later steps | No concrete model for typed step IO exists yet | Designing reusable workflow definitions |
| Hephaestus operator | Collaborate with a planner, get automated review pressure, and re-review later | Planning and review are not part of one visible workflow state | Before implementation or ADR/design work |
| Planner session | Produce and revise a draft plan across workflow phases | Continuity across automated feedback cycles is unresolved | Initial interactive planning and later feedback response |
| Reviewer session | Review a concrete submitted plan message | Review targets are ambiguous when only chat history exists | Automated review cycles |

## Product Outcome

Hephaestus can run a workflow with interactive and automated phases connected by explicit messages. The planning-review workflow should make these capabilities observable:

- an interactive step can pause the workflow and later submit a structured output,
- automated steps can consume that submitted output,
- multiple automated review/refinement cycles can run before returning to the user,
- a feedback message can be passed back to the planner session,
- a later interactive step can resume the workflow with prior workflow context,
- the timeline shows which phase owns control.

### Success Metrics

| Metric | Baseline | Target | Measurement Method |
| --- | --- | --- | --- |
| Interactive workflow step | No proven pause/resume step model | Workflow visibly pauses for initial planning and later user review | Manual app validation |
| Message passing | Session handoff is ad hoc | Submitted plan, reviewer feedback, and consolidated review are runtime-owned workflow messages | Timeline, inspector, and persistence validation |
| Automated cycle control | Existing loop is implementation-specific | Planning workflow can run multiple automated reviewer/planner-response cycles before returning to the user | End-to-end workflow run |
| Future builder learning | No concrete typed IO path | PRD/plan identify how this slice informs encodable-output and decodable-input step contracts | Technical plan review |

## Scope Boundaries

### In Scope

- A built-in Planning Review Workflow used as the first concrete interactive-step workflow.
- An initial interactive planner phase that pauses the workflow.
- A user action or command that submits the current draft plan from the interactive planner phase.
- A visible submitted plan message that reviewer steps consume.
- Automated reviewer sessions that review the submitted plan.
- Runtime-owned reviewer feedback messages from each reviewer session.
- A runtime-owned consolidated review message per review cycle.
- Passing the consolidated review message into planner-response work without requiring reviewer file-write permission.
- Multiple automated review/refinement cycles before returning to the next interactive user review step.
- A later interactive user review phase where the user can accept, continue planning, or request another automated cycle.
- Optional project-local `.hephaestus/` persistence/export for workflow messages and run-local debug outputs in this first slice.
- Timeline updates that distinguish interactive pause, submitted message, automated review, feedback handoff, planner response, and later interactive review.
- A first-slice harness adapter boundary with Codex as the only required backend implementation.

### Out Of Scope

- Building the full workflow builder UI.
- Generalizing every workflow step to arbitrary Codable input/output in the first implementation.
- Starting implementation automatically after the planning workflow completes.
- Rich plan diff/merge tooling.
- Multi-user collaboration.
- Durable cross-workflow message or artifact management.
- A full artifact browser.
- Implementing Claude, OpenCode, Gemini, or ACP backends in the first slice.

### Deferred

- Formal workflow-builder authoring surfaces.
- Generic step schemas with user-authored encodable outputs and decodable inputs.
- Configurable reviewer counts, reviewer personas, and rubrics.
- Direct accepted-plan handoff into implementation-review workflow.
- Plan version comparison UI.
- Branch or commit creation for accepted plans.
- Durable `.hephaestus/` message or artifact lifecycle across workflows.

### Scope Creep Watchlist

- Treating this as only a polished planning product instead of a capability-proving workflow.
- Solving generic typed workflow IO before this concrete message-passing workflow works.
- Making `.hephaestus/` a broad artifact platform in the first slice.
- Adding reliability/recovery behavior before the happy path proves useful.
- Hiding interactive step state in logs instead of making it part of the workflow timeline.

## User Experience

### Primary Flow

1. User selects a project.
2. User starts the Planning Review Workflow.
3. Hephaestus opens an interactive planner phase and shows the workflow as waiting for planner/user input.
4. User and planner session discuss the work and draft a plan.
5. User submits the draft plan using an explicit workflow action or command.
6. Hephaestus materializes the submitted plan as a runtime-owned workflow message.
7. Hephaestus runs automated reviewer sessions against the submitted plan.
8. Reviewer sessions return structured feedback messages to the workflow runtime without requiring file write permission.
9. Hephaestus consolidates reviewer output into one consolidated review message for the cycle.
10. Hephaestus passes the consolidated review message into planner-response work.
11. Hephaestus repeats automated review/planner-response cycles for the configured cycle count.
12. Hephaestus returns to an interactive user review phase.
13. User reviews the latest plan and feedback history.
14. User chooses to accept, continue interactive planning, or request another automated cycle.

### Workflow Shape

```text
Interactive planning
  User and planner session draft the plan
  User submits plan message

Automated cycle 0
  Reviewer A consumes submitted plan
  Reviewer B consumes submitted plan
  Consolidated feedback message is produced
  Planner response consumes consolidated feedback

Automated cycle 1
  Reviewer A consumes revised/submitted plan
  Reviewer B consumes revised/submitted plan
  Consolidated feedback message is produced
  Planner response consumes consolidated feedback

Interactive user review
  User reviews latest plan and feedback trail
  User accepts, continues planning, or requests another cycle
```

### Submitted Plan Behavior

The planner phase does not need to continuously create a plan file. The user chooses when to materialize the draft plan for the workflow. The first slice should provide an explicit submit action or command that turns the current draft into a workflow-visible runtime message.

A submitted plan qualifies as reviewable when the user can see or open it and it contains enough structure for reviewers to evaluate product intent and implementation readiness. The first slice should require:

- summary of the intended change,
- scope and non-goals,
- relevant user or operator flow,
- implementation approach or plan outline,
- validation expectations,
- open questions or assumptions.

The review phase must consume the submitted plan message, not only the full unstructured chat transcript.

### Message Passing Behavior

This workflow should explicitly surface message handoffs between sessions. Workflow messages should be runtime-owned encoded values, not files written by agents. The product direction is that future workflow steps should be able to output encodable objects and consume decodable objects.

Agents and sessions should produce structured results to the workflow runtime. The runtime owns message creation, routing, persistence, and optional export. This is important for permission boundaries: a reviewer session should not need file write permission just to pass feedback to the next workflow step.

The planning workflow should exercise at least these message shapes:

- planner interactive session outputs a submitted plan message,
- reviewer sessions consume the submitted plan message,
- reviewer sessions output review feedback messages,
- consolidation produces one consolidated review message for the cycle,
- planner-response work consumes the consolidated review message,
- later interactive user review consumes the latest plan and feedback history.

The PRD does not require a generic typed workflow IO system in this slice, but the technical design should explain how the chosen first-slice representation can evolve toward typed step outputs and inputs.

### Harness Backend Behavior

The first implementation may support only Codex as the backend for interactive planner, reviewer, and planner-response sessions. That Codex support should still sit behind a harness adapter boundary so workflow state does not depend on Codex-specific events or session mechanics.

The workflow runtime should consume normalized backend events and runtime-owned workflow messages. Backend-native details such as launch mode, session IDs, resume commands, raw event payloads, and approval plumbing should be adapter concerns.

Future Claude, OpenCode, Gemini, or ACP support should be additive adapter work, not a rewrite of the planning workflow or message-passing model.

### Review Feedback Message

Each automated review cycle should produce one consolidated review feedback message. The consolidated message should be the planner-response input for that cycle, so the planner does not have to reconcile multiple reviewer transcripts.

The consolidated review message should be structured for planning decisions:

- reviewed plan reference,
- cycle number,
- reviewer summaries,
- blocking issues,
- ambiguities or missing requirements,
- scope creep concerns,
- validation gaps,
- suggested plan edits,
- non-blocking suggestions.

The workflow may preserve individual reviewer logs elsewhere, but the primary planner feedback should be the single consolidated review message.

### Runtime Message Representation

The first-slice message representation should favor structured runtime-owned payloads. A practical shape to explore in the technical plan is an erased envelope with typed payload cases:

```swift
struct WorkflowMessage: Codable, Identifiable {
  let id: String
  let kind: WorkflowMessageKind
  let producerStepID: String
  let createdAt: Date
  let payload: WorkflowMessagePayload
  let summary: String?
}

enum WorkflowMessagePayload: Codable {
  case submittedPlan(SubmittedPlanPayload)
  case reviewerFeedback(ReviewerFeedbackPayload)
  case consolidatedReview(ConsolidatedReviewPayload)
  case plannerResponse(PlannerResponsePayload)
}
```

The exact Swift type names belong in the technical plan. The product constraint is that reviewer feedback and planner responses can move through the workflow without granting those sessions filesystem write access.

### `.hephaestus/` Persistence And Export Suggestions

`.hephaestus/` should be treated as runtime-owned persistence/export/debug storage, not the primary communication channel between agents. The runtime may persist encoded messages, exported markdown renderings, and logs there for inspection.

The exact layout belongs in the technical plan, but this PRD recommends considering one of these shapes:

Option A, run-scoped message persistence:

```text
.hephaestus/
  runs/
    <run-id>/
      messages.jsonl
      exports/
        submitted-plan.md
        cycle-0-review.md
        cycle-0-planner-response.md
        cycle-1-review.md
        cycle-1-planner-response.md
```

Option B, message-oriented layout:

```text
.hephaestus/
  runs/
    <run-id>/
      messages/
        000-planner-submitted-plan.json
        010-reviewer-a-feedback.json
        011-reviewer-b-feedback.json
        020-consolidated-review.json
        030-planner-response.json
      exports/
        000-planner-submitted-plan.md
        020-consolidated-review.md
      logs/
        reviewer-a-cycle-0.md
        reviewer-b-cycle-0.md
```

Option C, cycle-oriented layout:

```text
.hephaestus/
  runs/
    <run-id>/
      plan/
        submitted.json
        accepted.json
      cycles/
        0/
          review.json
          planner-response.json
          review.md
        1/
          review.json
          planner-response.json
          review.md
```

Option B best matches the future direction of explicit workflow messages. Option C may be easier to inspect by hand. The technical plan should choose one and define cleanup/lifetime expectations for first-slice runtime-owned persistence.

### Link Behavior

Review feedback links should be UI/debug references to runtime-owned persisted messages or exports, not the primary handoff mechanism. When a persisted export exists inside the selected project, links should prefer project-relative paths, for example `.hephaestus/runs/<run-id>/exports/020-consolidated-review.md`. Absolute paths are acceptable where needed for local execution, logging, or external process handoff. App routes can be deferred unless the UI needs deep links into an inspector.

### Interactive Review Behavior

After the configured automated cycles complete, the workflow returns to an interactive user review phase. The user should be able to inspect the latest plan, the consolidated feedback trail, and the planner responses before choosing:

- accept,
- continue interactive planning,
- request another automated cycle.

If the user continues interactive planning, the workflow resumes or opens an interactive planner context with the latest plan and feedback history available. How planner continuity is represented remains an architecture/design question.

### Edge And Failure States

- If the user exits before submitting a plan, the workflow remains in the interactive planning state.
- If the user attempts to submit an empty or incomplete plan, the workflow asks the user to continue planning.
- If runtime persistence or export to `.hephaestus/` fails, the workflow surfaces a clear persistence/export error.
- If a reviewer fails, the consolidated feedback message records the failed reviewer and includes available partial feedback.
- If all reviewers fail, the cycle fails visibly and does not run planner response against empty feedback.
- If consolidated review feedback cannot be encoded or persisted by the runtime, the cycle fails before planner response.
- If planner response fails, the workflow returns a visible failed state with review feedback still available.
- If the configured automated cycle count completes, the workflow returns to interactive user review instead of continuing automatically.
- If the user requests another automated cycle from the interactive review phase, Hephaestus starts one explicit additional cycle from the latest plan.

## Functional Requirements

- **FR-1:** The system must expose a built-in Planning Review Workflow for a selected project.
- **FR-2:** The workflow must support an initial interactive planner phase that pauses automated execution.
- **FR-3:** The user must be able to submit the draft plan from the interactive planner phase using an explicit workflow action or command.
- **FR-4:** The workflow must materialize the submitted plan as a visible runtime-owned workflow message.
- **FR-5:** Reviewer sessions must consume the submitted plan message rather than only the unstructured chat transcript.
- **FR-6:** The workflow must run multiple automated review/planner-response cycles before returning to the next interactive user review phase.
- **FR-7:** The workflow must consolidate reviewer feedback into a single runtime-owned review feedback message per cycle.
- **FR-8:** The workflow must pass the consolidated feedback message into planner-response work without requiring reviewer file-write permission.
- **FR-9:** The workflow must preserve enough message history for the later interactive user review phase to inspect latest plan, feedback trail, and planner responses.
- **FR-10:** The workflow must let the user accept, continue interactive planning, or request another automated cycle from the interactive user review phase.
- **FR-11:** The workflow runtime may persist or export first-slice messages under project-local `.hephaestus/` for inspection and debugging.
- **FR-12:** The workflow timeline must clearly distinguish interactive pause, submitted message, automated cycle, feedback handoff, planner response, and later interactive review states.
- **FR-13:** The technical design must describe how first-slice message representations can evolve toward encodable step outputs and decodable step inputs.
- **FR-14:** The first implementation must support Codex through a backend adapter boundary rather than coupling workflow state directly to Codex-specific events.

## Acceptance Criteria

- **AC-1.1** (`FR-1`): Given a project is selected, when the workflow list renders, then the Planning Review Workflow is available to start.
- **AC-2.1** (`FR-2`): Given the user starts the workflow, then the first workflow state is an interactive planner phase and automated reviewer work has not started.
- **AC-3.1** (`FR-3`): Given the user has a draft plan, when the user invokes the submit-plan action or command, then the workflow leaves the initial interactive planning phase and begins automated review.
- **AC-3.2** (`FR-3`): Given no reviewable draft exists, when the user invokes submit-plan, then the workflow remains interactive and explains what plan content is missing.
- **AC-4.1** (`FR-4`): Given submit-plan succeeds, then the submitted plan message is visible or inspectable from the run.
- **AC-5.1** (`FR-5`): Given reviewer sessions start, then their input includes the submitted plan message.
- **AC-6.1** (`FR-6`): Given the configured automated cycle count is two, when the first cycle completes successfully, then the second automated cycle starts before the workflow returns to interactive user review.
- **AC-6.2** (`FR-6`): Given the configured automated cycle count completes, then the workflow returns to interactive user review.
- **AC-7.1** (`FR-7`): Given a review cycle completes with reviewer output, then exactly one consolidated review feedback message is produced for that cycle.
- **AC-7.2** (`FR-7`): Given one reviewer fails and another succeeds, then the consolidated feedback includes successful feedback and records the failed reviewer state.
- **AC-8.1** (`FR-8`): Given consolidated feedback exists, when planner-response work begins, then it receives the consolidated feedback message as workflow input.
- **AC-8.2** (`FR-8`): Given reviewer sessions produce feedback, then they can return feedback to the workflow runtime without file write permission.
- **AC-9.1** (`FR-9`): Given automated cycles complete, then the interactive user review phase exposes the latest plan, consolidated feedback trail, and planner responses.
- **AC-10.1** (`FR-10`): Given the workflow is in interactive user review, when the user accepts, then the workflow records an accepted state and does not start implementation automatically.
- **AC-10.2** (`FR-10`): Given the workflow is in interactive user review, when the user continues planning, then an interactive planner context opens or resumes with latest plan and feedback history available.
- **AC-10.3** (`FR-10`): Given the workflow is in interactive user review, when the user requests another cycle, then one additional automated review/planner-response cycle starts from the latest plan.
- **AC-11.1** (`FR-11`): Given the runtime persists or exports workflow messages, then those runtime-owned files are stored under `.hephaestus/` in the selected project.
- **AC-12.1** (`FR-12`): Given the workflow is waiting for initial planning or later user review, then the timeline shows an explicit interactive waiting state.
- **AC-12.2** (`FR-12`): Given workflow messages are submitted or produced, then the timeline or inspector exposes their references.
- **AC-13.1** (`FR-13`): Given the technical plan is written, then it identifies the first-slice message representation and how it can evolve toward encodable outputs and decodable inputs.
- **AC-14.1** (`FR-14`): Given the first implementation runs planner or reviewer sessions, then workflow code consumes normalized backend events rather than Codex-specific event payloads.
- **AC-14.2** (`FR-14`): Given a future backend is added, then it can be introduced as a new adapter without changing the planning workflow's message model.

## Dependencies

- Existing project selection and workflow runner surfaces.
- Existing headless Codex workflow runner capability.
- Existing workflow timeline and step inspector surfaces.
- A first-slice Codex harness adapter for interactive workflow-attached sessions.
- A design exploration for interactive workflow pause/resume.
- A project-local `.hephaestus/` persistence/export location.
- A way to materialize a user-submitted plan from an interactive planner session.
- A first-slice message representation between workflow steps.

## Product Risks

- The workflow could be mis-scoped as a polished planning feature and fail to answer the underlying interactive-step questions.
- The first-slice message representation could accidentally become the permanent typed IO model without enough design pressure.
- File-based exports could accidentally become the handoff mechanism if runtime-owned messages are not kept central.
- Planner continuity may be harder than expected if interactive sessions and automated planner-response sessions cannot share context cleanly.
- Multiple automated cycles before user review may feel opaque unless the timeline makes message handoffs visible.
- `.hephaestus/` could become a broad artifact store before ownership and lifetime are designed.
- The first Codex integration could leak backend-specific assumptions into workflow state unless the adapter boundary is explicit from the start.

## Technical Design Gate

PRDs define product need and product constraints. ADRs record durable architectural choices. Technical designs or implementation plans in `docs/plans/` describe how an accepted PRD will be built.

| Field | Value |
| --- | --- |
| Separate technical design required? | Yes |
| Rationale | The workflow exists to explore interactive pause/resume, runtime-owned cross-session message passing, planner continuity, reviewer fan-out, optional message persistence/export, and the path toward typed workflow step IO. |
| Plan link | [Interactive Step Review Gates And Exit Policy](../plans/0013-interactive-step-review-gates-and-exit-policy.md) |
| Blocks implementation until resolved? | Yes |
| Owner | Hephaestus engineering |

### Product Constraints For Technical Design

- The workflow must not block a subprocess while waiting for user interaction.
- Interactive waiting states must be visible in the app, not hidden in logs.
- The user chooses when to materialize and submit the draft plan.
- Workflow messages must be runtime-owned encoded values rather than files written by agents.
- Reviewer sessions must consume the submitted plan message.
- Reviewer sessions must be able to return feedback without file write permission.
- Planner-response work must consume consolidated feedback through an explicit runtime-owned message.
- Multiple automated cycles should run before returning to the next interactive user review step.
- `.hephaestus/` storage is first-slice runtime persistence/export/debug storage; durable ownership and cross-workflow artifact semantics require a later decision before expansion.
- The technical plan should preserve a path toward future encodable step outputs and decodable step inputs.
- The first implementation may be Codex-only, but must use a harness adapter boundary so future backends can be adapter additions.
- Workflow definitions should depend on normalized backend events and runtime-owned workflow messages, not Codex-specific payloads.

### Open Technical Questions

| Question | Owner | Blocks Implementation? | Resolve In PRD/ADR/Plan | Resolution |
| --- | --- | --- | --- | --- |
| How should Hephaestus represent an interactive workflow pause and later resume? | Hephaestus engineering | Yes | Plan/ADR exploration | Needs further exploration. |
| How should the submit-plan action or command work in the interactive planner phase? | Hephaestus engineering | Yes | Plan | User chooses when to materialize the draft; exact UI/command TBD. |
| How is planner continuity represented across interactive planning and planner-response phases? | Hephaestus engineering | Yes | Plan/ADR exploration | Options need to be explored. |
| What first-slice runtime-owned message representation should connect submitted plans, review feedback, and planner responses? | Hephaestus engineering | Yes | Plan | Prefer encoded workflow messages, not file handoffs. |
| What is the minimal harness adapter contract for Codex-first interactive sessions? | Hephaestus engineering | Yes | Plan/ADR exploration | Codex only in first implementation; future backends should be adapter additions. |
| What is the exact `.hephaestus/` directory layout for runtime-owned persistence/export outputs? | Hephaestus engineering | Yes | Plan | Consider run-scoped message persistence, message-oriented, or cycle-oriented layouts. |
| Should persisted/exported review links be project-relative paths, file URLs, or app routes? | Hephaestus engineering | No | Plan | Prefer project-relative links; absolute paths acceptable where needed. |

## Milestones

| Milestone | Outcome | Included FRs | Excluded Scope | Exit Criteria | Dependencies |
| --- | --- | --- | --- | --- | --- |
| M1 | Interactive submit gate | FR-1, FR-2, FR-3, FR-4, FR-12, FR-14 | Reviewer fan-out, multiple cycles | User can start the workflow, work interactively, submit a plan, and see a submitted runtime message | Pause/resume design exploration and Codex adapter boundary |
| M2 | Message-backed automated cycles | FR-5, FR-6, FR-7, FR-8, FR-11, FR-12 | Final accept/continue controls, generic typed IO | Reviewers consume submitted plan, feedback is consolidated, planner-response consumes feedback, and multiple cycles run | M1 and message representation |
| M3 | Interactive user review return | FR-9, FR-10, FR-12, FR-13 | Full workflow builder, implementation handoff | Workflow returns to user review with latest plan and feedback trail; user can accept, continue planning, or request another cycle | M2 |

## Validation Plan

### Pre-Implementation Validation

- Explore pause/resume options for interactive workflow steps.
- Explore planner continuity options across interactive and automated phases.
- Choose the first-slice message representation.
- Define the minimal Codex-first harness adapter boundary.
- Choose `.hephaestus/` persistence/export layout.
- Define submit-plan action or command behavior.
- Confirm default automated cycle count before returning to user review.

### Implementation Validation

- Manually run the planning workflow through interactive planning, submit-plan, multiple automated cycles, and interactive user review.
- Verify the submitted plan message is visible or inspectable from the run.
- Verify reviewer inputs include the submitted plan message.
- Verify reviewer sessions can return feedback without file write permission.
- Verify `.hephaestus/` contains runtime-owned persisted messages or exported summaries when persistence/export is enabled.
- Verify planner-response work receives the consolidated feedback message.
- Verify the timeline shows interactive waiting states and message handoffs.
- Add focused tests for workflow state transitions, message/reference creation, review consolidation, cycle count, and user review choices.

### Ship Criteria

- User can complete the capability-proving happy path without leaving the app for orchestration decisions.
- Workflow visibly pauses for initial planning and later user review.
- Submit-plan materializes a workflow-visible runtime message.
- Reviewer and planner-response steps consume explicit runtime messages.
- Multiple automated cycles run before the later interactive user review phase.
- The technical plan captures what this teaches about future encodable outputs and decodable inputs.

## Open Questions

| Question | Owner | Blocks Implementation? | Resolve In PRD/ADR/Plan | Resolution |
| --- | --- | --- | --- | --- |
| Should the final accepted plan remain in `.hephaestus/`, be copied to `docs/plans/`, or both? | Hephaestus engineering | No | Plan | TBD. |
| Should the user be able to edit consolidated feedback before planner response? | Hephaestus engineering | No | Future PRD/Plan | TBD. |
| Should reviewer personas be fixed for the first slice? | Hephaestus engineering | No | Plan | TBD. |
| Should a formal ADR be written before implementation, or should the plan first explore options and then produce an ADR? | Hephaestus engineering | Yes | Plan/ADR | TBD. |

---

## Notes

This PRD intentionally uses planning as the concrete workflow because it stresses interactive pause/resume, message handoff, and session continuity. The first implementation should answer those capability questions before polishing this into a formal planning workflow product.

**Last Updated:** 2026-05-07
