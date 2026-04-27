# PRD-0006. Run Inspection

**Status:** Draft
**Date:** 2026-04-25
**Owner:** Joshua Sumskas
**Related ADRs:** [ADR-0008](../adr/0008-local-app-state-storage.md)
**Related Plans:** [Complete Single-Agent Harness PRDs](../plans/0003-complete-single-agent-harness-prds.md)

---

## Summary

Add a basic run inspection surface so users can understand what happened during an agent run: messages, runtime events, provider requests, errors, and context decisions.

## Problem

Agent behavior is hard to debug if the only visible output is the final transcript. Hephaestus should make execution observable before it adds more complex capabilities like tools, skills, or multi-agent workflows.

## Users And Jobs

| User | Job To Be Done | Current Pain | Usage Context |
| --- | --- | --- | --- |
| App builder | Debug why a run behaved a certain way | Runtime details are hidden in code/logs | Runtime development |
| Power user | Inspect what happened during a run | Transcript alone is not enough | Longer or failed runs |

## Product Outcome

The user can open a run inspector and see a readable timeline of the important events and data behind a chat run.

## Success Metrics

| Metric | Baseline | Target | Measurement Method |
| --- | --- | --- | --- |
| Event visibility | Hidden | Timeline shows runtime events | Manual validation |
| Error debuggability | Error text only | Inspector shows failed turn details | Forced-failure validation |
| Context discoverability | Separate/hidden | Inspector links or displays context details | Manual validation |

## Scope Boundaries

### In Scope

- Show a run event timeline.
- Show messages and turn status.
- Show provider request/response summary.
- Show errors for failed turns.
- Link to or embed context details where available.

### Out Of Scope

- Editing or replaying runs.
- Tool execution inspection.
- Multi-agent workflow visualization.
- Export/import.
- Full raw network traffic viewer.

### Deferred

- Replay mode.
- Artifact browser.
- Workflow graph visualization.
- Advanced filters and search.

## User Experience

### Primary Flow

1. User opens a chat or prior run.
2. User opens the run inspector.
3. App shows a timeline of run events.
4. User selects an event or turn.
5. App shows details relevant to that event.

### Edge And Failure States

- Empty run shows an empty inspector state.
- Failed run highlights the failed turn.
- Missing provider/context details are clearly marked unavailable.

## Functional Requirements

- **FR-1:** The app must expose a run inspector for a chat run.
- **FR-2:** The inspector must show a timeline of important runtime events.
- **FR-3:** The inspector must show messages and turn status.
- **FR-4:** The inspector must show provider request/response summaries where available.
- **FR-5:** The inspector must make failures visible and inspectable.

## Acceptance Criteria

- **AC-1.1** (`FR-1`): Given a chat run exists, when the user opens inspection, then a run inspector is visible.
- **AC-2.1** (`FR-2`): Given a completed run, then the inspector shows ordered runtime events.
- **AC-3.1** (`FR-3`): Given a turn exists, then the inspector shows its user/assistant messages and status.
- **AC-4.1** (`FR-4`): Given provider request details are available, then the inspector shows a readable summary.
- **AC-5.1** (`FR-5`): Given a failed turn, then the inspector highlights the failure and shows available error detail.

## Dependencies

- Persistent or observable runtime events.
- Basic navigation or presentation surface for inspector.
- Context trace availability if context details are included.

## Product Risks

- Inspector can become too technical or too broad.
- Event data may not be persisted deeply enough for meaningful inspection.
- UI could drift into workflow visualization before single-run inspection is useful.

## Technical Design Gate

| Field | Value |
| --- | --- |
| Separate technical design required? | Yes |
| Rationale | Run inspection depends on event data shape, persistence/observation, UI navigation, and failure handling. |
| Plan link | [Complete Single-Agent Harness PRDs](../plans/0003-complete-single-agent-harness-prds.md) |
| Blocks implementation until resolved? | Yes |
| Owner | Joshua Sumskas |

### Product Constraints For Technical Design

- Inspector must be readable without reading source code.
- V1 should focus on one run, not multi-agent workflows.
- Missing details should be explicit rather than hidden.

## Milestones

| Milestone | Outcome | Included FRs | Excluded Scope | Exit Criteria | Dependencies |
| --- | --- | --- | --- | --- | --- |
| M1 | Inspector opens for a run | FR-1 | Full details | User can open inspector | Navigation surface |
| M2 | Event and message timeline visible | FR-2, FR-3 | Provider detail | User can inspect turn timeline | Runtime events |
| M3 | Provider/error details visible | FR-4, FR-5 | Replay/export | User can inspect provider summary and failures | M2 |

## Validation Plan

### Pre-Implementation Validation

- Confirm what event data is available for inspection.
- Confirm where inspector opens from.

### Implementation Validation

- Inspect a successful two-turn run.
- Inspect a forced failed run.
- Inspect a run with missing details.

### Ship Criteria

- User can open inspector for a run.
- Timeline is readable.
- Failures and provider summaries are visible where available.

## Open Questions

| Question | Owner | Blocks Implementation? | Resolve In PRD/ADR/Plan | Resolution |
| --- | --- | --- | --- | --- |
| Does inspector require persistence first? | Joshua Sumskas | Yes | Plan | Yes. V1 inspector reads persisted runtime summaries. |
| Should context details be part of this inspector or a separate view? | Joshua Sumskas | No | Plan | Part of the run inspector for v1. |

---

## Notes

This PRD supports the long-term "observable execution" principle.

**Last Updated:** 2026-04-25
