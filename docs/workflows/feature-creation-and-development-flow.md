# Feature Creation And Development Flow

Use this reference whenever a new Hephaestus feature, product capability, or substantial behavior change is being proposed, designed, implemented, or reviewed.

## Purpose

Keep product definition, technical design, architecture decisions, implementation, and validation separate enough that each artifact answers the right question:

- PRD: what should exist, who it helps, why it matters, what is in scope, and how we know it is done.
- Technical design or implementation plan: how an accepted product slice will be built in this codebase.
- ADR: which durable architecture decision was made, why, and what tradeoffs were accepted.
- Implementation: code changes that satisfy the PRD and follow the design/ADR constraints.
- Review: confirmation that the implementation matches the PRD, design, tests, and scope boundaries.

## Default Flow

1. Define the product capability in a PRD.
2. Add the PRD to `docs/prd/README.md`.
3. Use the PRD's technical design gate to decide whether a plan is required.
4. Create a technical design or implementation plan in `docs/plans/` when required.
5. Create an ADR in `docs/adr/` only for durable architecture decisions.
6. Implement the feature after the needed PRD/design/ADR questions are resolved.
7. Validate against PRD acceptance criteria and the plan's validation section.
8. Review for PRD/design drift, missing tests, and scope creep before considering the work complete.

## Stage 1: Product Definition

Start with a PRD when any of these are true:

- The user is proposing a new capability.
- The product outcome is not already written down.
- Scope boundaries or non-goals need to be clarified.
- User-visible behavior, acceptance criteria, or ship criteria are unclear.
- The work may change roadmap priority or feature sequencing.

Use `docs/prd/template.md`.

The PRD should define:

- summary and problem,
- users and jobs,
- product outcome,
- in-scope and out-of-scope behavior,
- user experience and failure states,
- functional requirements,
- acceptance criteria,
- dependencies and product risks,
- technical design gate,
- milestones,
- validation and ship criteria.

The PRD should not define:

- package wiring,
- concrete type sketches,
- implementation order,
- build commands,
- code-level migration details,
- provider wire-format specifics.

Those belong in a plan or ADR.

## Stage 2: Technical Design

Write a design or implementation plan after the PRD exists when the implementation has one or more of:

- Multiple package or app-target changes.
- New persistence, networking, concurrency, provider, or security behavior.
- Non-trivial runtime state transitions.
- Migration or compatibility concerns.
- A meaningful test and validation strategy.
- Open technical questions that should not live in the PRD.

Plans live in `docs/plans/`.

The design should:

- link back to the PRD,
- explicitly state that product behavior, scope, and acceptance criteria remain in the PRD,
- describe current-state code boundaries,
- propose implementation architecture,
- define sequencing,
- identify validation commands and test coverage,
- call out risks and unresolved technical questions.

The design should not expand PRD scope unless the PRD is updated too.

## Stage 3: Architecture Decisions

Write an ADR when the work requires a durable architecture decision, such as:

- A new long-lived ownership boundary.
- A package/module boundary change.
- A provider/runtime protocol direction.
- A persistence model choice.
- A concurrency or lifecycle model that future work must preserve.

Use `docs/adr/template.md`.

Do not use an ADR for ordinary implementation sequencing, temporary tactical choices, or feature requirements.

## Stage 4: Implementation

Before writing implementation code:

- Confirm the PRD exists.
- Confirm the PRD is listed in `docs/prd/README.md`.
- Confirm whether the PRD requires a plan.
- Confirm required plans and ADRs exist and are linked.
- Confirm acceptance criteria are testable.
- Confirm validation commands are known.

During implementation:

- Stay inside the accepted PRD scope.
- Follow the technical design unless new evidence requires updating it.
- Update the PRD or plan when implementation discoveries change scope or design.
- Keep unrelated refactors out of the feature unless they are required to complete the slice.
- Add tests that map back to acceptance criteria and technical risk.

## Stage 5: Validation And Review

Validate against both product and technical sources:

- PRD acceptance criteria.
- PRD ship criteria.
- Technical design validation plan.
- ADR constraints.
- Existing test and build expectations.

For review-heavy implementation work, use:

- [Subagent Implementation Review Loop](./subagent-implementation-review-loop.md)

Review should focus on:

- behavioral mismatches with the PRD,
- implementation drift from the plan,
- missing acceptance criteria,
- missing or weak tests,
- safety or persistence risks,
- scope creep.

## Artifact Rules

- PRDs live in `docs/prd/` and use `docs/prd/template.md`.
- Plans live in `docs/plans/`.
- ADRs live in `docs/adr/` and use `docs/adr/template.md`.
- Workflows live in `docs/workflows/`.
- Update the relevant index when adding a new durable doc.
- Keep PRDs product-focused; move module wiring, type sketches, validation commands, and implementation order to plans.
- Keep plans implementation-focused; do not let them redefine PRD scope.
- Keep ADRs decision-focused; do not use them as feature specs.
- Keep `AGENTS.md` as a short entrypoint that links to this reference instead of duplicating it.

## Agent Checklist

Before creating a design:

- Is there already a PRD for this capability?
- If not, should the next artifact be a PRD instead of a technical design?
- Is the product outcome clear enough to design implementation safely?

Before writing code:

- Is there a PRD for the capability?
- Is the PRD listed in `docs/prd/README.md`?
- Does the PRD technical design gate say a plan is required?
- If a plan is required, does it exist and link back to the PRD?
- Are durable architecture decisions captured in ADRs or explicitly marked as not needed?
- Are acceptance criteria and validation steps clear enough to test the work?

Before finalizing:

- Did the implementation satisfy each relevant acceptance criterion?
- Were validation commands run or explicitly skipped with a reason?
- Did any implementation discovery require updating the PRD, plan, or ADR?
- Is the new behavior discoverable from the relevant docs indexes?

If the answer to "Is there a PRD for this capability?" is no, create or propose the PRD before writing a technical design.
