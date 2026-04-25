# Hephaestus Docs

This folder captures the current direction for Hephaestus as an agent system.

## Documents

- [Vision](./vision.md): the intended end state for the product and runtime.
- [Roadmap](./roadmap.md): the staged plan from kernel proof of concept to multi-agent workflows.
- [Next Step](./next-step.md): the immediate implementation target for the first kernel milestone.
- [ADR Template](./adr/template.md): template for recording architecture decisions as they are made.

## ADRs

- [0001. Record Architecture Decisions](./adr/0001-record-architecture-decisions.md): establishes the ADR process for this repository.
- [0002. Swift Kernel Baseline For Hephaestus](./adr/0002-swift-kernel-baseline.md): records the initial implementation baseline for the kernel and harness.
- [0003. Initial Agent Kernel POC](./adr/0003-initial-agent-kernel-poc.md): defines the first implementation phase with mock provider, Stitch DI, use cases, and a basic chat UI.
- [0004. SwiftUI Interactor Page Architecture](./adr/0004-swiftui-interactor-page-architecture.md): defines state/action page views, interactors, lifecycle binding, and the `Page(interactor:view:)` convention.
- [0005. SwiftUI Router And Modal Navigation](./adr/0005-swiftui-router-and-modal-navigation.md): defines route stack ownership, semantic modal presentation, and shell-level navigation rendering.
- [0006. Package Boundaries And Cross-Package Deep Links](./adr/0006-package-boundaries-and-cross-package-deep-links.md): defines local package boundaries and route-input based deep links across packages.

## Current Direction

Hephaestus should start as an `agent kernel` rather than a full workflow builder. The first goal is to prove the core turn lifecycle, context assembly, and provider integration before layering on multi-agent orchestration and richer UI concerns.
