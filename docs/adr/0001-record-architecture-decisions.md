# 0001. Record Architecture Decisions

**Status:** Accepted
**Date:** 2026-04-20
**Deciders:** Joshua Sumskas, Codex
**Technical Story:** Establish an ADR process for documenting significant architectural decisions in Hephaestus.

---

## Context

As Hephaestus grows, the project needs a reliable way to capture why important architectural decisions were made.

Without a formal process, this context would be spread across chat history, PR discussions, and memory. That makes it harder to understand why the system is shaped a certain way, especially as the project moves from a simple SwiftUI app scaffold toward an agent kernel, a single-agent harness, and later multi-agent workflow capabilities.

The repository already contains an ADR template, and architectural decisions are now important enough that they should be recorded consistently and kept close to the code.

### Problem Statement

Hephaestus needs a lightweight, version-controlled way to record important architectural decisions and their rationale.

### Goals

- Make architectural decisions transparent and easy to find.
- Preserve historical context for future work.
- Reduce repeated discussion about already-settled architectural questions.
- Keep design rationale in the repository alongside the code and supporting docs.

### Non-Goals

- Documenting every implementation detail or small code change.
- Replacing inline code comments or normal technical documentation.
- Creating heavyweight process overhead for small or reversible decisions.

---

## Decision Drivers

* The project is still early and major architecture choices are actively being made.
* Future work will span kernel design, context management, persistence, tools, skills, and later workflow composition.
* Architectural context will otherwise be easy to lose.
* Documentation should stay in version control and be reviewable like code.
* The process must stay lightweight enough that it is actually used.

---

## Considered Options

### Option 1: Architecture Decision Records (ADRs)

**Description:** Use lightweight Markdown files in `docs/adr/` to document significant architectural decisions.

**Pros:**
- Keeps architectural rationale in the repository.
- Easy to diff, review, search, and link.
- Lightweight enough for regular use.
- Establishes a chronological record of the system's evolution.

**Cons:**
- Requires discipline to keep current.
- Can become stale if later decisions do not supersede or update earlier ADRs.

### Option 2: Rely On General Docs Only

**Description:** Capture architecture decisions informally in general documentation files without a formal ADR process.

**Pros:**
- Less process overhead.
- Fewer document types to manage.

**Cons:**
- Decisions are harder to find and track over time.
- Historical rationale is easier to lose.
- No clear pattern for superseding old decisions.

### Option 3: Keep Decisions In PRs Or Chat Only

**Description:** Let pull requests, commit messages, and discussion threads serve as the decision record.

**Pros:**
- No additional documentation work.
- Context is often available at the time the decision is made.

**Cons:**
- Hard to discover later.
- Discussion history is noisy and fragmented.
- Rationale is not maintained as part of the project's durable docs.

### Option 4: External Wiki Or Notes Tool

**Description:** Keep architecture decisions outside the repo in a separate documentation platform.

**Pros:**
- Potentially better browsing and editing tools.
- Easy to expand with broader project notes.

**Cons:**
- Separates architecture rationale from the codebase.
- Easier for docs to drift out of sync.
- Adds another system to maintain.

---

## Decision

Hephaestus will use Architecture Decision Records in `docs/adr/` to document significant architectural decisions.

**Chosen Option:** Option 1 - Architecture Decision Records (ADRs)

### Rationale

ADRs provide the right balance for this project:

1. They are lightweight enough to use regularly during an early-stage build.
2. They live in version control alongside the code and supporting docs.
3. They create a durable, ordered history of architectural choices.
4. They make it easier to understand why the system is evolving in a particular direction.
5. They provide a clean place to record when a decision changes or is superseded.

This is especially useful for Hephaestus because the project is still defining its architecture. The team is making foundational choices now, and those choices will affect later work on the agent kernel, harness, context system, and workflow model.

---

## Consequences

### Positive

- Important architectural decisions will be easier to discover and understand.
- Future work can reference prior rationale instead of re-deriving it.
- The repository will accumulate a clear history of architectural evolution.
- Design discussions can result in concrete, reviewable records.

### Negative

- Significant architectural changes now carry a small documentation cost.
- ADR quality depends on discipline and follow-through.
- Old ADRs may need to be superseded or updated as the system evolves.

### Neutral

- ADRs become part of the normal design process for major architecture work.
- Not every technical choice needs an ADR; judgment is still required.

---

## Implementation

### Process

1. Create a new numbered ADR for significant architectural decisions.
2. Start from `docs/adr/template.md`.
3. Record the context, options, decision, rationale, and consequences.
4. When a decision changes, add a new ADR that supersedes the old one rather than rewriting history.
5. Keep ADRs referenced from the main docs index so they remain discoverable.

### What Warrants An ADR?

Create an ADR when a decision:

- affects multiple parts of the system
- defines a core abstraction or boundary
- has long-term consequences
- involves meaningful tradeoffs
- would be expensive to reverse later

Examples for this project include:

- choosing the language/runtime model
- defining provider abstraction boundaries
- deciding how context management is structured
- choosing the persistence model for runs and artifacts
- defining the workflow or messaging model

Do not create ADRs for:

- small tactical implementation details
- local refactors with no architecture impact
- trivial defaults that are easy to change later

---

## Validation

### Success Metrics

- New architectural decisions are consistently captured as ADRs.
- Design discussions can reference prior ADRs instead of relying on memory.
- Contributors can understand major architectural choices by reading `docs/adr/`.

### Monitoring

- Review whether major design changes are shipping without ADRs.
- Check whether ADRs remain understandable and referenced during planning work.
- Supersede outdated ADRs instead of silently drifting away from them.

---

## Related Decisions

- [0002. Swift Kernel Baseline For Hephaestus](./0002-swift-kernel-baseline.md)

---

## References

- [Architecture Decision Records](https://adr.github.io/)
- [Documenting Architecture Decisions - Michael Nygard](http://thinkrelevance.com/blog/2011/11/15/documenting-architecture-decisions)
- [ADR GitHub Organization](https://github.com/joelparkerhenderson/architecture-decision-record)
- [Reference ADR From Forge](https://github.com/entrhq/forge/blob/main/docs/adr/0001-record-architecture-decisions.md)

---

## Notes

This ADR establishes the ADR process itself. It should remain `0001` even if later ADRs are more technically substantial.

**Last Updated:** 2026-04-20
