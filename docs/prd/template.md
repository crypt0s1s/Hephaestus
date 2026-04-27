# PRD-[Number]. [Product Capability]

**Status:** [Draft | Proposed | Accepted | In Progress | Shipped | Deprecated]
**Date:** YYYY-MM-DD
**Owner:** [Product/engineering owner]
**Related ADRs:** [Links to relevant ADRs, if any]
**Related Plans:** [Links to technical design or implementation plans, if any]

---

## Writing Guidance

- Focus on product outcomes, user value, scope, acceptance criteria, and ship criteria.
- Keep implementation details out unless they are product constraints.
- Acceptance criteria should be user-observable where possible.
- Move implementation sequencing, module changes, package wiring, and validation commands to `docs/plans/`.
- Move durable technical decisions and tradeoffs to ADRs.

---

## Summary

[Describe the product capability in a short paragraph. Focus on the user-visible outcome, not the implementation.]

## Problem

[Describe the user problem, workflow gap, or product risk this PRD addresses.]

### Background

[Optional context that explains why this matters now.]

### Users And Jobs

| User | Job To Be Done | Current Pain | Usage Context |
| --- | --- | --- | --- |
| [Primary user/persona] | [What they are trying to accomplish] | [What blocks or slows them today] | [When/where this capability is used] |

## Product Outcome

[State the target behavior change or product outcome. This should explain what will be true for users when the PRD is successful.]

### Success Metrics

| Metric | Baseline | Target | Measurement Method |
| --- | --- | --- | --- |
| [Metric name] | [Current state or unknown] | [Minimum success threshold] | [How it will be verified] |

## Scope Boundaries

### In Scope

- [Capability included in this PRD]
- [Capability included in this PRD]

### Out Of Scope

- [Capability explicitly excluded]
- [Capability explicitly excluded]

### Deferred

- [Likely future phase, intentionally not included now]
- [Likely future phase, intentionally not included now]

### Scope Creep Watchlist

- [Tempting addition that should trigger a PRD update or new PRD]
- [Tempting addition that should trigger a PRD update or new PRD]

## User Experience

### Primary Flow

1. [User action]
2. [System response]
3. [User-visible result]

### Edge And Failure States

- [Empty/loading/error state]
- [Cancellation/retry/offline behavior, if relevant]
- [Permission/configuration issue, if relevant]
- [Non-regression behavior that must remain true]

## Functional Requirements

- **FR-1:** [The system must ...]
- **FR-2:** [The system must ...]
- **FR-3:** [The system must ...]

## Acceptance Criteria

Acceptance criteria should reference functional requirements. Use Given/When/Then where it improves clarity.

- **AC-1.1** (`FR-1`): Given [state], when [action], then [observable result].
- **AC-1.2** (`FR-1`): [Concrete product acceptance behavior.]
- **AC-2.1** (`FR-2`): [Concrete product acceptance behavior.]

## Dependencies

- [Architecture decision, external service, package, account, or local capability required]
- [Dependency that could block implementation]

## Product Risks

- [Risk to usability, correctness, trust, reliability, or delivery]
- [Risk to scope control]

## Technical Design Gate

PRDs define product need and product constraints. ADRs record durable architectural choices. Technical designs or implementation plans in `docs/plans/` describe how an accepted PRD will be built.

| Field | Value |
| --- | --- |
| Separate technical design required? | [Yes/No] |
| Rationale | [Why a plan is or is not needed] |
| Plan link | [Link or TBD] |
| Blocks implementation until resolved? | [Yes/No] |
| Owner | [Person responsible for the plan] |

Create a separate technical design or implementation plan when the implementation has one or more of:

- Multiple package or app-target changes.
- New persistence, networking, concurrency, or security behavior.
- A migration path.
- Non-trivial test strategy.
- Technical decisions that may need ADRs before implementation.

### Product Constraints For Technical Design

- [User/product constraint that the technical design must preserve]
- [Reliability, privacy, UX, performance, or compatibility constraint]

### Open Technical Questions

- [Question that should be resolved in an ADR or plan, not inside the PRD]

## Milestones

| Milestone | Outcome | Included FRs | Excluded Scope | Exit Criteria | Dependencies |
| --- | --- | --- | --- | --- | --- |
| M1 | [Smallest useful slice] | [FR-1, FR-2] | [What remains deferred] | [Concrete acceptance bar] | [Required dependency] |
| M2 | [Next increment, if known] | [FR-3] | [What remains deferred] | [Concrete acceptance bar] | [Required dependency] |

## Validation Plan

### Pre-Implementation Validation

- [Product review, design review, dependency check, or spike required before implementation]

### Implementation Validation

- [Manual validation]
- [Automated test coverage]
- [Build or runtime command]

### Ship Criteria

- [Minimum product behavior required to call this shipped]
- [Blocking bugs or gaps that must be absent]

## Open Questions

| Question | Owner | Blocks Implementation? | Resolve In PRD/ADR/Plan | Resolution |
| --- | --- | --- | --- | --- |
| [Question] | [Owner] | [Yes/No] | [PRD/ADR/Plan] | [TBD or decision] |

---

## Notes

[Additional product notes, links, or follow-up context.]

**Last Updated:** YYYY-MM-DD
