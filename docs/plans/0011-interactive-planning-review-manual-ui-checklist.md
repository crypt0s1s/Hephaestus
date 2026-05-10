# Interactive Planning Review Manual UI Checklist

**Status:** Draft
**Date:** 2026-05-10
**Related PRD:** [PRD-0011. Interactive Planning Review Workflow](../prd/0011-interactive-planning-review-workflow.md)

## Purpose

This checklist translates PRD-0011 acceptance criteria into manual UI checks. Most checks are not executable yet because the current app only exposes the existing `hello-world` and `implementation-review-loop` workflows. The checklist should become the manual happy-path script as the Planning Review Workflow is implemented.

## Current Smoke Coverage

- [ ] Launch Hephaestus and verify the workflow runner opens.
- [ ] Select or confirm a project in the sidebar.
- [ ] Verify existing workflow rows render without layout regressions.
- [ ] Run the existing HelloWorld workflow against a disposable project and verify it still creates and deletes `HelloWorld.txt`.
- [ ] Verify the timeline/output surface updates during the run.
- [ ] Verify the run completes successfully and leaves no `HelloWorld.txt` behind.

## Planning Workflow Availability

- [ ] `AC-1.1`: Given a project is selected, when the workflow list renders, then the Planning Review Workflow is available to start.
  - Current status: testable in the first interactive-pause slice. The workflow should appear as `Planning Review Workflow`.

## Initial Interactive Planning

- [ ] `AC-2.1`: Starting the workflow enters an interactive planner phase and automated reviewer work has not started.
- [ ] `AC-12.1`: Timeline shows an explicit interactive waiting state while the planner phase is waiting.
- [ ] Verify the interactive chat surface is visibly attached to the workflow run rather than appearing as an unrelated task session.
- [ ] Verify navigating away and back preserves the waiting workflow state.
  - Current status: partially testable in the first interactive-pause slice. The workflow can enter a visible waiting state, but workflow-attached chat and real pause/resume are not implemented yet.

## Submit Plan

- [ ] `AC-3.1`: With a reviewable draft, invoking submit-plan leaves initial planning and begins automated review.
- [ ] `AC-3.2`: With no reviewable draft, invoking submit-plan keeps the workflow interactive and explains missing content.
- [ ] `AC-4.1`: The submitted plan message is visible or inspectable from the run.
- [ ] `AC-12.2`: The timeline or inspector exposes the submitted message reference.
  - Current status: not testable. Runtime-owned `WorkflowMessage` creation and submit-plan UI are not implemented yet.

## Automated Review Cycles

- [ ] `AC-5.1`: Reviewer inputs include the submitted plan message.
- [ ] `AC-6.1`: With configured cycle count of two, the second automated cycle starts after the first completes.
- [ ] `AC-6.2`: After configured cycles complete, the workflow returns to interactive user review.
- [ ] `AC-7.1`: Each completed review cycle produces exactly one consolidated review feedback message.
- [ ] `AC-7.2`: If one reviewer fails and another succeeds, consolidated feedback includes successful feedback and records the failed reviewer.
- [ ] `AC-8.1`: Planner-response work receives the consolidated feedback message.
- [ ] `AC-8.2`: Reviewer feedback returns to the runtime without granting reviewer sessions file write permission.
  - Current status: not testable for Planning Review Workflow. Existing Implementation Review Loop covers reviewer/build loop UI, but it does not use runtime-owned planning messages.

## Interactive User Review

- [ ] `AC-9.1`: After automated cycles, the interactive user review phase exposes the latest plan, consolidated feedback trail, and planner responses.
- [ ] `AC-10.1`: Accept records an accepted state and does not start implementation automatically.
- [ ] `AC-10.2`: Continue planning opens or resumes an interactive planner context with latest plan and feedback history.
- [ ] `AC-10.3`: Request another cycle starts one additional automated review/planner-response cycle from the latest plan.
  - Current status: not testable. Later interactive review state and controls are not implemented yet.

## Backend Adapter Boundary

- [ ] `AC-14.1`: Planner or reviewer sessions route through normalized backend events rather than Codex-specific workflow state.
- [ ] `AC-14.2`: The planning workflow message model remains independent of backend-specific event payloads.
  - Current status: partially covered by code/build tests. The current Codex command path routes through `HarnessBackendAdapter`, but Planning Review Workflow does not exist yet.
