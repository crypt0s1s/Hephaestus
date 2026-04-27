# Subagent Implementation Review Loop

## Purpose

Use this workflow when an accepted PRD and technical design are ready to implement. The goal is to keep implementation, review, and orchestration responsibilities separate so changes are checked against the agreed product and technical documents before they are treated as complete.

This workflow is especially useful when the work touches multiple files, app targets, package boundaries, or user-visible behavior.

## Roles

### Orchestrator

The orchestrator manages the workflow and does not directly implement the change.

Responsibilities:

- Start implementer and reviewer subagents.
- Provide the PRD and technical design as source-of-truth inputs.
- Route reviewer findings back to the implementer.
- Decide when to request another review pass.
- Summarize the final outcome, validations, known caveats, and remaining manual checks.
- Avoid editing files directly during the loop unless the user explicitly changes the workflow.

### Implementer

The implementer makes code or documentation changes.

Responsibilities:

- Implement only the requested scope.
- Use the PRD and technical design as the source of truth.
- Avoid reverting unrelated worktree changes.
- Run relevant validation.
- Report changed paths, validation results, decisions, caveats, and blockers.
- Fix reviewer findings when sent back by the orchestrator.

### Reviewer

The reviewer checks the implementation against the PRD and technical design.

Responsibilities:

- Do not edit files.
- Compare implementation behavior against PRD acceptance criteria and technical design requirements.
- Report concrete findings with file and line references.
- Call out scope creep, missing acceptance criteria, build/runtime risks, and validation gaps.
- State `pass` only when no concrete issues remain.

## Source Documents

Each implementation loop should have:

- A PRD in `docs/prd/` describing product outcome, scope, acceptance criteria, and ship criteria.
- A technical design or implementation plan in `docs/plans/` describing module changes, implementation sequence, validation commands, and risks.
- Relevant ADRs in `docs/adr/` when durable architecture decisions constrain the implementation.

If any of these are missing or unclear, create or refine them before starting implementation.

## Workflow

1. Create an implementer subagent.
   - Give it the PRD and technical design paths.
   - Tell it what files or area it owns.
   - Tell it not to revert unrelated changes.
   - Tell it to validate and report changed paths.

2. Wait for implementation to complete.
   - The implementer must report changed paths, validation results, caveats, and blockers.

3. Create a reviewer subagent.
   - Give it the same PRD and technical design paths.
   - Ask it to compare the implementation against the documents.
   - Tell it not to edit files.
   - Require concrete findings with file and line references, or `pass`.

4. If the reviewer finds issues, send the findings back to the implementer.
   - The implementer fixes only the reported issues.
   - The implementer reruns relevant validation.
   - The implementer reports changed paths and validation results.

5. Repeat review and fix cycles with the same reviewer until that reviewer passes.

6. Create a new reviewer subagent for a fresh clean-pass review.
   - The new reviewer should not rely on previous review context.
   - It should review the full implementation against the PRD and technical design.

7. If the new reviewer finds issues, return to step 4.

8. Complete the workflow only after a fresh reviewer gives a clean initial pass.

## Pass Criteria

An implementation is complete when:

- The implementer has finished the requested scope.
- At least one reviewer has completed a fix/re-review loop and passed.
- A fresh reviewer has reviewed from scratch and passed with no findings.
- Required automated validation has passed or any inability to run it is explicitly documented.
- Required manual validation has either been completed or is explicitly listed as remaining.

## Validation Expectations

Validation should be specified in the technical design. Typical validation categories are:

- Unit or package tests.
- CLI or headless smoke tests.
- App target builds.
- Physical UI validation for user-visible behavior.
- Forced-failure checks for error handling paths when relevant.

When a command needs local environment adjustments, document the exact command used. For example, local macOS app compile validation may use `CODE_SIGNING_ALLOWED=NO` when signing certificates are not available.

## Finding Severity

Use simple severity labels:

- `P1`: Blocks correctness, buildability, PRD acceptance, or safe release of the slice.
- `P2`: Meaningful behavior, architecture, test, or maintainability issue that should be fixed before completion.
- `P3`: Minor issue, scope cleanup, documentation gap, or follow-up candidate.

The orchestrator should send `P1` and `P2` findings back for fixes by default. `P3` findings may be fixed immediately or explicitly accepted as follow-up, depending on context.

## Prompt Templates

### Implementer Prompt

```text
Implement [PRD/title] using [technical design path].

You are not alone in the codebase: do not revert or overwrite unrelated edits.
Ownership: [files/modules/area].
Use these documents as source of truth:
- [PRD path]
- [technical design path]

Do not broaden scope into [explicit non-goals].
Validate with [commands or validation categories] where feasible.

Final response must summarize:
- changed paths
- validation run and results
- blockers or decisions made
- any manual validation not performed
```

### Reviewer Prompt

```text
Review the current implementation against:
- [PRD path]
- [technical design path]

Focus on concrete deviations from PRD/TD, build/runtime risks, missing acceptance criteria, and scope creep.
Do not edit files.
Return findings with file/line references and severity, or say pass if no issues.
Mention validation you ran or inspected.
```

### Fix Prompt

```text
Reviewer found the following issues:
[findings]

Fix only these issues.
Do not revert unrelated changes.
Rerun relevant validation.

Final response must summarize:
- changed paths
- how each finding was resolved
- validation run and results
```

### Fresh Reviewer Prompt

```text
Fresh clean-pass review of the current implementation against:
- [PRD path]
- [technical design path]

You have not seen prior review context.
Focus on concrete deviations from PRD/TD, build/runtime risks, missing acceptance criteria, and scope creep.
Do not edit files.
Return findings with file/line references and severity, or say pass if no issues.
Mention validation you ran or inspected.
```

## Notes From PRD-0001

This workflow was first used for PRD-0001, the macOS mock chat shell. The loop caught:

- An unrelated project signing change.
- A local signed-build validation mismatch.
- A first-turn double-send race before `isRunning` was set.
- A need for physical UI validation to catch scroll behavior.

The useful pattern was not just "review once." The stronger gate was "review, fix, re-review, then fresh clean-pass review."
