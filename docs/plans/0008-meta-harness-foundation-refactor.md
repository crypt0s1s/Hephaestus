# Meta-Harness Foundation Refactor

**Status:** Implemented
**Date:** 2026-05-04
**Related PRD:** [PRD-0009. Meta-Harness Foundation](../prd/0009-meta-harness-foundation.md)
**Related docs:** [Vision](../vision.md), [Product UI Vision](../product-ui-vision.md), [UI Concepts](../UI/README.md), [Observability Objectives](../observability-objectives.md), [Modularization Objectives](../modularization-objectives.md), [ADR-0006](../adr/0006-package-boundaries-and-cross-package-deep-links.md), [Plan-0005](./0005-chat-log-runtime-architecture-map.md), [Plan-0006](./0006-chat-session-service-refactor-plan.md)

## 1. Purpose

This plan defines the first concrete refactor slice for reframing Hephaestus from a chat-first app into a meta-harness/operator app.

The slice should make the current code structurally compatible with the future product model:

```text
Project
  Task
    Workflow state
    Runs
    Conversation
    Timeline
    Artifacts
    Inspector
```

The goal is not to build the full product now. The goal is to introduce the smallest stable homes for project, task, backend, and observation concepts so new work does not keep accumulating inside a chat-owned feature.

Current conversation behavior must keep working during and after the refactor.

Product behavior, scope boundaries, and acceptance criteria are owned by [PRD-0009](../prd/0009-meta-harness-foundation.md). This plan describes the implementation structure and validation path for that accepted slice.

## 2. Current Problems In The App/Package Structure

- Before implementation, `Package.swift` exposed a chat-centered feature shape:
  - `Anvil`
  - `HephaestusKernel`
  - `HephaestusTools`
  - `HephaestusLLM`
  - `HephaestusRuntime`
  - `HephaestusComposition`
  - `ChatContracts`
  - `ChatFeature`
  - `HephaestusCLI`
- `Hephaestus/HephaestusAppShell.swift` is doing too much:
  - app startup
  - route registry setup
  - runtime construction
  - provider override resolution through `PersistentAppRuntime`
  - chat workspace construction
  - dependency lookup for many use cases
- The previous `ChatFeature` was still the user-facing application model:
  - the left rail is a chat history list, not project/task navigation
  - `ChatPageState` contains selected run state, messages, provider settings, inspector state, and session summaries
  - `ChatPage` renders the whole app as a chat page
- `ChatSessionService.swift` had a useful lifetime split, but it was still chat-shaped:
  - `ChatWorkspaceService` owns selected chat and sidebar summaries
  - `ChatSessionService` owns transcript projection and direct runtime stream consumption
  - run/task identity is still expressed as chat/session identity
- Run inspection was embedded as `RunInspectorPanelState`, `RunInspectorSheet`, and `RunInspectionContent` inside the chat feature.
- Provider settings lived in the chat page even though provider configuration is not conceptually chat-specific.
- Current runtime naming is still `HephaestusKernel`, `HephaestusRuntime`, and `HephaestusComposition`; these should eventually become the native Foundry backend, but not in this slice.
- Core product concepts such as `Project`, `Task`, `HarnessBackend`, `WorkflowState`, and reusable observation events do not yet have package homes.

## 3. Goals And Non-Goals

### Goals

- Preserve current conversation behavior.
- Add a small product/domain layer that can represent projects and tasks without SwiftUI, Anvil, or feature dependencies.
- Add a small harness/backend contract layer that can describe Foundry as the only implemented backend for now.
- Add a small observation contract layer that can wrap current persisted runtime inspection data without depending on chat UI.
- Make chat attach to a task-shaped model incrementally rather than remaining the root app concept.
- Keep the app target as the composition root.
- Keep package dependency direction clean and testable.
- Prefer extraction of current concepts over speculative new frameworks.

### Non-Goals

- Do not do a big-bang rewrite.
- Do not replace the current conversation mechanics with the full project/task/workflow UI in this slice.
- Do not rename all runtime packages to Foundry now.
- Do not implement Codex CLI or Claude Code adapters.
- Do not build a workflow builder.
- Do not introduce graph workflows or multi-agent orchestration.
- Do not make run inspection feature-complete.
- Do not make persistence perfect or migrate all existing stored data unless required for compatibility.

## 4. Proposed First Package/Module Split

Add three small core targets first:

```text
Core/
  HephaestusDomain/
    Project.swift
    Task.swift
    WorkflowState.swift

  HephaestusHarness/
    HarnessBackend.swift
    HarnessBackendCapability.swift
    HarnessRunRequest.swift
    HarnessRunIdentity.swift

  HephaestusObservation/
    ObservationEvent.swift
    RunInspectionSnapshot.swift
    RunInspectionUseCase.swift
```

Then add feature targets for the task workspace route and current task workspace surface:

```text
Features/
  TaskWorkspaceContracts/
    TaskWorkspaceRouteInput.swift

  TaskWorkspaceFeature/
    TaskWorkspaceFeature.swift
    TaskSessionService.swift
```

`TaskWorkspaceFeature` replaces the active `ChatFeature` package in this slice because the previous implementation no longer needs to hold back the new approach. Keep the extraction narrow: do not add `ProjectWorkspaceFeature`, `RunInspectorFeature`, `BackendManagerFeature`, or `ConversationFeature` yet.

Target dependency direction:

```text
Hephaestus app target
  -> TaskWorkspaceFeature
  -> TaskWorkspaceContracts
  -> HephaestusDomain
  -> HephaestusHarness
  -> HephaestusObservation
  -> HephaestusRuntime
  -> HephaestusComposition

TaskWorkspaceFeature
  -> Anvil
  -> TaskWorkspaceContracts
  -> HephaestusDomain
  -> HephaestusObservation
  -> HephaestusRuntime

HephaestusObservation
  -> HephaestusDomain
  -> no SwiftUI
  -> no Anvil
  -> no feature packages

HephaestusHarness
  -> HephaestusDomain
  -> HephaestusObservation
  -> no SwiftUI
  -> no Anvil
  -> no feature packages

HephaestusDomain
  -> Foundation only
```

Temporary compromise:

- `HephaestusRuntime` can still own `PersistedSession`, `PersistedRunInspection`, `RuntimeEvent`, and current use cases.
- `HephaestusObservation` can initially define UI-independent projections and adapter protocols over those runtime types rather than forcing all runtime storage to move immediately.
- `TaskWorkspaceFeature` can continue importing `HephaestusRuntime` until the inspector and provider settings are extracted.

## 5. Minimal Domain Concepts To Introduce First

### Project

Introduce a minimal `Project` model in `HephaestusDomain`.

Suggested shape:

```swift
public struct ProjectID: Hashable, Codable, Sendable {
    public var rawValue: UUID
}

public struct Project: Hashable, Codable, Identifiable, Sendable {
    public var id: ProjectID
    public var name: String
    public var rootURL: URL?
    public var createdAt: Date
    public var updatedAt: Date
}
```

First-slice behavior:

- Create one default local project if no project system exists yet.
- Do not build full project discovery, project settings, or workspace indexing.
- Keep `rootURL` optional so the current app can continue to run without forcing filesystem project selection.

### Task

Introduce a minimal `Task` model in `HephaestusDomain`.

Suggested shape:

```swift
public struct TaskID: Hashable, Codable, Sendable {
    public var rawValue: UUID
}

public enum TaskStatus: String, Codable, Sendable {
    case draft
    case running
    case waitingForInput
    case completed
    case failed
    case cancelled
}

public struct AgentTask: Hashable, Codable, Identifiable, Sendable {
    public var id: TaskID
    public var projectID: ProjectID
    public var title: String
    public var status: TaskStatus
    public var createdAt: Date
    public var updatedAt: Date
    public var activeRunID: UUID?
}
```

First-slice behavior:

- Treat each current chat session as a task-backed conversation for projection purposes.
- It is acceptable for the first task ID to match the current session/run UUID through a bridge initializer.
- Do not require a storage migration that permanently changes existing app-state files unless needed.
- Add mapping helpers such as `AgentTask.init(sessionSummary:projectID:)` in an adapter layer, not in the pure domain model.

### Workflow State

Introduce a small state enum rather than a workflow builder.

Suggested shape:

```swift
public enum WorkflowState: Hashable, Codable, Sendable {
    case drafting
    case running
    case waitingForApproval
    case reviewing
    case completed
    case failed
}
```

First-slice behavior:

- Map current chat running/error/completed state into this enum.
- Do not model workflow recipes, workflow graphs, step editors, or reusable templates yet.

### Harness Backend

Introduce backend identity and capabilities without external implementations.

Suggested shape:

```swift
public struct HarnessBackendID: Hashable, Codable, Sendable {
    public var rawValue: String
}

public struct HarnessBackendDescriptor: Hashable, Codable, Identifiable, Sendable {
    public var id: HarnessBackendID
    public var displayName: String
    public var capabilities: Set<HarnessBackendCapability>
}

public enum HarnessBackendCapability: String, Hashable, Codable, Sendable {
    case liveEvents
    case conversation
    case toolEvents
    case approvalEvents
    case fileChangeSummaries
    case structuredFinalOutput
    case resume
    case rawPayloadCapture
}
```

First-slice behavior:

- Register one backend descriptor for the current native runtime.
- Name it `foundry` in the meta-harness layer while leaving existing package names alone.
- Do not create Codex CLI or Claude Code descriptors unless the UI needs to show unavailable future options; if shown, mark them as not installed/unavailable through data, not through fake adapters.

## 6. What Remains Temporarily In TaskWorkspaceFeature

Keep these in `TaskWorkspaceFeature` for the first slice:

- `TaskWorkspacePage`
- `TaskWorkspaceInteractor`
- `TaskWorkspaceState`
- `TaskWorkspaceService`
- `TaskSessionServiceRegistry`
- `TaskSessionService`
- transcript rendering
- composer rendering
- task list/sidebar rendering backed by existing persisted sessions
- provider settings sheet
- run inspector popover UI
- current direct `streamUserMessage` ownership
- current tests around task workspace/session behavior

Temporary compromises to call out in code comments or follow-up docs:

- A persisted session is temporarily projected as a task, but storage remains session-based.
- The task sidebar is not a full project/task navigator yet.
- Provider settings stay in the task workspace until a backend/provider settings surface exists.
- The run inspector UI stays in the task workspace until `RunInspectorFeature` exists, but its data contract is now observation-shaped instead of feature-owned.

## 7. How Chat Becomes A Conversation Panel Later

The first slice should prepare this path without implementing the final UI:

```text
TaskWorkspaceFeature
  Header: task title, project, backend, status
  PrimaryStateSurface: current workflow state
  Panels:
    ConversationPanel
    TimelinePanel
    ArtifactsPanel
    InspectorPanel
    ConfigurationPanel
```

Incremental path:

1. Add `AgentTask` and task projection from existing sessions.
2. Add `TaskWorkspaceRouteInput(taskID:)` and make it the startup route.
3. Rename the active feature package from `ChatFeature` to `TaskWorkspaceFeature`.
4. Keep the existing transcript/composer as the first conversation panel inside the workspace.
5. Move the sidebar authority from persisted sessions to real project tasks later.
6. Keep conversation commands task-scoped:
   - send message to selected task conversation
   - cancel selected task run
   - inspect selected task run

Do not build a separate `ConversationFeature` in this first slice. The current conversation UI can remain inside `TaskWorkspaceFeature` until a stronger panel boundary appears.

## 8. How Run Inspection/Observability Starts Moving Out Of Chat

Add `HephaestusObservation` as the shared model and use-case home for run inspection contracts.

Initial observation concepts:

```swift
public struct ObservationEvent: Hashable, Identifiable, Sendable {
    public var id: UUID
    public var runID: UUID
    public var taskID: TaskID?
    public var sequence: Int
    public var createdAt: Date
    public var kind: ObservationEventKind
    public var summary: String
    public var error: String?
}

public struct RunInspectionSnapshot: Hashable, Sendable {
    public var runID: UUID
    public var taskID: TaskID?
    public var events: [ObservationEvent]
}
```

First extraction:

- Keep `PersistedRunInspection` in `HephaestusRuntime`.
- Add a mapper from `PersistedRunInspection` to `RunInspectionSnapshot`.
- Add an observation-facing use case protocol such as:

```swift
public protocol LoadRunInspectionUseCase: Sendable {
    func loadRunInspection(runID: UUID) async throws -> RunInspectionSnapshot
}
```

- Have `PersistentAppRuntime` conform by delegating to the existing `inspectRun(sessionID:)` implementation and mapping the result.
- Keep `RunInspectorSheet` inside `TaskWorkspaceFeature`, but consume `RunInspectionSnapshot` rather than `PersistedRunInspection`.

Do not build replay, export, backend comparison, raw payload viewing, or redaction controls in this slice. The important move is that inspection data becomes task/run/backend-shaped instead of chat-shaped.

## 9. How This Sets Up Future Harness Backends

Add `HephaestusHarness` as a contract package, not as a process runner.

First-slice responsibilities:

- Define `HarnessBackendID`.
- Define `HarnessBackendDescriptor`.
- Define `HarnessBackendCapability`.
- Define a minimal run identity/request type if useful:

```swift
public struct HarnessRunIdentity: Hashable, Codable, Sendable {
    public var taskID: TaskID
    public var runID: UUID
    public var backendID: HarnessBackendID
}
```

- Define the current native runtime backend descriptor:

```text
id: foundry
displayName: Foundry
capabilities:
  - liveEvents
  - conversation
  - toolEvents, once current tool events exist
  - structuredFinalOutput, only when current runtime can prove it
```

Important constraints:

- Existing `HephaestusKernel`, `HephaestusRuntime`, `HephaestusLLM`, and `HephaestusComposition` remain named as-is.
- The meta-harness layer can call the current backend `Foundry` in descriptors and UI copy.
- Do not add executable discovery, shell process management, hook parsing, or Claude/Codex-specific schemas.
- Backend capabilities should make unsupported features explicit so the future UI can show unavailable controls without special-casing each backend.

## 10. Suggested Implementation Phases

### Phase 1: Add Pure Domain And Contract Targets

- Add `HephaestusDomain`.
- Add `HephaestusHarness`.
- Add `HephaestusObservation`.
- Wire them into `Package.swift`.
- Keep all new files Swift-only.
- Keep these targets free of SwiftUI, Anvil, and feature imports.

Acceptance criteria:

- `swift test` or at least `swift build` proves the new targets compile.
- Package dependencies still point downward.

### Phase 2: Add Session-To-Task Projection

- Add adapter helpers outside the pure domain model to project `PersistedSessionSummary` and `PersistedSession` into `AgentTask` summaries.
- Use a default `Project`/`ProjectID` for current data.
- Do not migrate stored sessions yet.
- Add focused tests for projection behavior.

Acceptance criteria:

- Existing saved chats can still load.
- A current chat session can be represented as a task summary.
- No UI behavior changes are required.

### Phase 3: Add Observation Snapshot Mapping

- Add `RunInspectionSnapshot` and `ObservationEvent`.
- Map `PersistedRunInspection.orderedEvents` into observation events.
- Add `LoadRunInspectionUseCase` or equivalent observation-facing protocol.
- Have app composition provide the observation use case through the route context.

Acceptance criteria:

- Current inspector data can be loaded through the new observation contract.
- `ChatFeature` can still display the same information.
- Existing inspector tests continue to pass or are updated only for type names.

### Phase 4: Add Foundry Backend Descriptor

- Add a descriptor for the current native runtime backend using `HarnessBackendDescriptor`.
- Expose it through a small registry or static factory in composition.
- Do not surface Codex CLI or Claude Code as runnable options.

Acceptance criteria:

- Current app can identify the selected backend as Foundry at the product contract layer.
- No runtime package rename is required.

### Phase 5: Introduce Task Workspace State

- Replace the active chat route/contracts package with `TaskWorkspaceContracts`.
- Rename the active feature package to `TaskWorkspaceFeature`.
- Add task/project IDs to the task workspace snapshot or to a parallel projection object.
- Keep `runID` compatibility internally where persisted sessions still use run/session UUIDs.
- Update visible shell labels from chat-first to task-first.

Acceptance criteria:

- Conversation send, task switch, cancel, reload, and inspect behavior remains unchanged.
- The selected task has enough metadata to host the conversation panel and future workflow state.

### Phase 6: Update Documentation

- Update plan 0005 or add a short follow-up note that the chat service is now projected into task/domain concepts.
- Update modularization docs only if actual package names differ from this plan.

## 11. Validation Plan

Run targeted validation after each phase:

- `swift build`
- `swift test`
- Existing task workspace/session tests:
  - response continues with no interactor attached
  - switching chats does not leak events
  - page disappearance detaches without cancelling
  - explicit cancel affects only the selected chat
  - persisted session reload still works
  - sidebar summary refresh still avoids loading flashes on selection
- New domain/projection tests:
  - default project creation/projection is deterministic enough for current storage
  - session summary maps to `AgentTask`
  - task status maps from running/error/current chat state
- New observation mapping tests:
  - event order is preserved
  - run ID is preserved
  - event kind and error summaries survive mapping
- Manual smoke test:
  - launch app
  - start a new task
  - send a message
  - switch tasks while streaming
  - inspect the run
  - reopen a persisted task/session

## 12. Risks And Open Questions

### Risks

- Adding too many packages too early could create ceremony without product value. Keep first targets small and contract-focused.
- If `AgentTask` mirrors `PersistedSession` too closely, the task model may inherit chat-specific assumptions. Keep mapping helpers outside the pure domain model.
- If observation mapping is only a rename of `PersistedRunInspection`, it may not actually help future backends. Include backend/run/task identity even if some fields are optional now.
- If `PersistentAppRuntime` keeps expanding inside `HephaestusAppShell.swift`, the app shell will remain too heavy. This slice should avoid making it worse and can prepare a later composition extraction.
- Using `runID == sessionID == taskID.rawValue` is convenient, but it should be treated as a bridge, not a permanent invariant.
- Backend capability descriptors can become fictional if they describe future behavior. Only mark capabilities that the current backend actually supports.

### Open Questions

- Should the first default project be persisted immediately, or should it be a projection over existing app state until project selection exists?
- Should task IDs be independent from session IDs from day one, or should the first bridge use the same UUID to avoid storage churn?
- Should `HephaestusObservation` depend on `HephaestusRuntime` for the first mapper, or should the mapper live in `HephaestusComposition` to keep observation contracts runtime-agnostic?
- Should provider settings move toward a backend manager feature before or after the first task workspace shell?
- Should the initial task workspace route be introduced now as a dormant contract, or only when a real task workspace screen is implemented?
- How much of `PersistentAppRuntime` should move out of `HephaestusAppShell.swift` before adding more app-level services?

## First Slice Summary

The first refactor slice is:

1. Add pure domain concepts for `Project`, `AgentTask`, and `WorkflowState`.
2. Add harness backend descriptors with only the current native runtime represented as Foundry.
3. Add reusable observation snapshots and mapping from current persisted run inspection.
4. Project current chat sessions into task-shaped data.
5. Keep the existing chat UI and service behavior intact.

This makes Hephaestus structurally ready for project/task/workflow-state UI without pretending that the full operator workbench already exists.
