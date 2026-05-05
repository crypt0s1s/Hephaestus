# Hephaestus Docs

This folder captures the current direction for Hephaestus as an agent system.

## Documents

- [Vision](./vision.md): the intended end state for the product and runtime.
- [Roadmap](./roadmap.md): the staged plan from kernel proof of concept to multi-agent workflows.
- [Observability Objectives](./observability-objectives.md): high-level goals for live inspection, event capture, backend observability, and future replay.
- [Product UI Vision](./product-ui-vision.md): project/task/workflow UI direction and image-generation prompts for design exploration.
- [UI Concept References](./UI/README.md): rough visual references and design notes for the future app interface.
- [Modularization Objectives](./modularization-objectives.md): target package boundaries for projects, tasks, workflows, backends, observability, and feature modules.
- [Next Step](./next-step.md): the immediate implementation target for the first kernel milestone.
- [PRDs](./prd/README.md): product requirements that define user-facing capabilities, scope, acceptance criteria, and milestones.
- [Workflows](./workflows/README.md): repeatable collaboration processes for implementing and reviewing changes.
- [Feature Creation And Development Flow](./workflows/feature-creation-and-development-flow.md): PRD-first workflow for defining, designing, implementing, and validating feature work.
- [ADR Template](./adr/template.md): template for recording architecture decisions as they are made.
- [PRD-0009. Meta-Harness Foundation](./prd/0009-meta-harness-foundation.md): product scope for the first slice that moves Hephaestus from chat-first toward project/task/operator structure.
- [Chat Log Runtime Architecture Map](./plans/0005-chat-log-runtime-architecture-map.md): current-state data flow map for chat logs, streaming, persistence, and UI projection.
- [Chat Session Service Refactor Plan](./plans/0006-chat-session-service-refactor-plan.md): draft refactor sequence for moving long-lived chat IO out of page interactors.
- [Meta-Harness Foundation Refactor Plan](./plans/0008-meta-harness-foundation-refactor.md): first incremental package/domain/observability slice for moving from chat-first UI toward project/task/workflow-state structure.

## Documentation Routing

- Use a PRD when defining the product outcome, user value, scope, and acceptance criteria.
- Use an ADR when recording a durable architecture decision and its tradeoffs.
- Use a plan when describing how an accepted slice will be implemented and validated.

## ADRs

- [0001. Record Architecture Decisions](./adr/0001-record-architecture-decisions.md): establishes the ADR process for this repository.
- [0002. Swift Kernel Baseline For Hephaestus](./adr/0002-swift-kernel-baseline.md): records the initial implementation baseline for the kernel and harness.
- [0003. Initial Agent Kernel POC](./adr/0003-initial-agent-kernel-poc.md): defines the first implementation phase with mock provider, Stitch DI, use cases, and a basic chat UI.
- [0004. SwiftUI Interactor Page Architecture](./adr/0004-swiftui-interactor-page-architecture.md): defines state/action page views, interactors, lifecycle binding, and the `Page(interactor:view:)` convention.
- [0005. SwiftUI Router And Modal Navigation](./adr/0005-swiftui-router-and-modal-navigation.md): defines route stack ownership, semantic modal presentation, and shell-level navigation rendering.
- [0006. Package Boundaries And Cross-Package Deep Links](./adr/0006-package-boundaries-and-cross-package-deep-links.md): defines local package boundaries and route-input based deep links across packages.
- [0007. Headless Runtime Entrypoint](./adr/0007-headless-runtime-entrypoint.md): defines headless support so the runtime can be exercised from a CLI or tests without requiring the SwiftUI app.
- [0008. Local App State Storage](./adr/0008-local-app-state-storage.md): defines the first durable storage boundary for provider settings, chat history, context traces, and run inspection summaries.
- [0012. External Swift Workflow Packages](./adr/0012-external-swift-workflow-packages.md): defines the proposed out-of-process Swift package model for user-authored workflows.

## Current Direction

Hephaestus should start as an `agent kernel` rather than a full workflow builder. The first goal is to prove the core turn lifecycle, context assembly, and provider integration before layering on multi-agent orchestration and richer UI concerns.
