# Hephaestus Product UI Vision

## Purpose

This document pulls together the current product direction for the Hephaestus app interface. It is intentionally high level. The goal is to create a design base for future PRDs, wireframes, image concepts, and implementation plans without prematurely locking the app into the current chat UI.

## Product Frame

Hephaestus should feel like a native operator environment for agent work.

The app should organize work by local project, let users create configurable agent tasks, execute those tasks through different harness backends, and make every run inspectable.

The central object is not a chat. It is a task-shaped unit of work that may contain conversation, plan steps, backend runs, approvals, artifacts, and inspection data.

```text
Project
  Task
    Workflow state
    Runs
    Conversation
    Plan
    Timeline
    Artifacts
    Inspector
```

The UI can still expose "chats" where interaction is conversational, but chat should be one panel or mode inside a task rather than the whole product model.

## Naming Model

- Hephaestus: the meta-harness and operator app.
- Foundry: the native in-process Swift agent harness/runtime.
- Anvil: the UI framework.
- Project: a local filesystem root or workspace.
- Task: the user-facing unit of work inside a project.
- Run: one execution attempt inside a task.
- Workflow: the recipe or state machine that controls how a task progresses.
- Backend: the harness that executes a run, such as Foundry, Codex CLI, or Claude Code.

## Main Information Architecture

The app should eventually support this high-level structure:

```text
Projects
  Project Workspace
    Tasks
    Runs
    Workflows
    Profiles
    Skills and Hooks
    Artifacts
    Settings
```

For v1, this can be narrowed to:

```text
Projects
  Tasks
  Run Inspector
  Backends
  Profiles
  Settings
```

The important shift is that the left side of the app should orient around projects and their work, while the main surface should orient around the selected task's current workflow state.

## Project Workspace

A project represents a filesystem path, similar to how Codex groups work by project.

Project-level UI should answer:

- Which projects are available?
- Which project is active?
- What tasks exist in this project?
- Which tasks are running, failed, blocked, or recently completed?
- Which backend and configuration are commonly used here?
- What project-level skills, hooks, and policies are enabled?

The project workspace should eventually include:

- task list
- active runs
- recent artifacts
- project configuration
- backend availability
- workflow templates available for this project

## Task Workspace

A task is the primary unit of work.

A task may be interactive, non-interactive, workflow-driven, or comparison-oriented. The same task should be able to contain multiple runs, especially when retrying, comparing backends, or continuing after review.

Task-level UI should answer:

- What is the task trying to accomplish?
- What workflow is driving it?
- What state is it currently in?
- Which backend is executing it?
- What inputs, tools, roles, skills, and policies are active?
- What happened so far?
- What needs the user's attention?
- What artifacts or changes came out of it?

Suggested task workspace layout:

```text
Task Header
  title, project, workflow, backend, status, branch, duration

Primary State Surface
  changes based on workflow state

Panels
  Conversation
  Plan
  Timeline
  Artifacts
  Inspector
  Configuration
```

## Workflow-State Surfaces

The main surface should be rendered from the current workflow state.

Examples:

- Drafting: prompt, goal, workflow choice, configuration preview.
- Planning: plan outline, assumptions, questions, editable steps.
- Waiting for approval: approval request, risk summary, affected paths, allow/deny controls.
- Running: live output, active step, tool calls, timeline.
- Reviewing: findings, changed files, build/test results, accept/retry controls.
- Comparing: backend result matrix, differences, artifacts per run.
- Completed: final result, artifacts, changed files, replay/inspect actions.
- Failed: failure cause, last event, suggested recovery, retry controls.

This keeps the app from being a generic chat transcript with status badges bolted on.

## Conversation Panel

Conversation remains important, but it should support the workflow rather than define it.

The conversation panel should be useful for:

- clarifying the task
- giving steering input
- answering approval questions
- resuming interactive work
- asking follow-up questions about a run
- letting a backend continue from prior context when supported

For non-interactive steps, conversation can be collapsed or secondary while the run timeline and artifacts become primary.

## Workflow Creation

Workflow creation may start outside Hephaestus, including in ChatGPT, as a design and brainstorming workflow. The app should still leave room to import, edit, and eventually author workflows natively.

Workflow creation should cover:

- workflow name and purpose
- trigger or entry mode
- phases or steps
- agent roles
- backend choices per step
- model/profile choices per step
- tool access per role
- skill and hook configuration
- approval policy
- sandbox or workspace policy
- expected artifacts
- success and failure criteria
- review or validation gates

Early versions can treat workflows as templates or recipes. Later versions can provide a visual or structured editor.

Possible workflow creation surfaces:

- template picker
- guided form
- YAML/JSON-like advanced editor
- role and tool matrix
- step editor
- validation preview
- import from Markdown or generated workflow spec

The UI should make room for different configurations without requiring the user to understand every setting before starting a simple task.

## Profiles, Roles, Tools, Skills, And Hooks

The UI should separate durable configuration from per-run overrides.

Profiles define reusable behavior:

- instructions
- default model
- default context policy
- default backend preference
- default approval posture

Roles define responsibilities inside a workflow:

- planner
- implementer
- reviewer
- verifier
- researcher
- operator

Tools define executable capabilities:

- file read/write
- shell
- git
- browser
- documentation search
- project-specific tools

Skills define specialized operating knowledge:

- coding conventions
- workflow instructions
- domain-specific guidance
- tool usage recipes

Hooks define lifecycle observation or policy points:

- run start
- user prompt submitted
- pre-tool use
- post-tool use
- permission requested
- run stopped

The UI should eventually allow a user to see and edit what each role can access. A role/tool matrix is likely more understandable than burying this in separate dialogs.

## Backend Configuration

Backends should be visible because Foundry, Codex CLI, and Claude Code will not have identical capabilities.

Backend UI should show:

- backend name
- executable or service location
- detected version
- health status
- supported capabilities
- unavailable capabilities
- default sandbox and approval behavior
- supported event capture modes
- default profile mapping

The user should be able to choose a backend at task creation time and override it for specific workflow steps when the workflow allows it.

## Observability UI

Observability should be present throughout the app without becoming the whole app.

Every task should have access to:

- normalized timeline
- raw event details when available
- tool calls
- approvals
- file changes
- context decisions
- backend requests
- failures and retries

This can live as panels inside the task workspace and as a deeper run inspector page.

The user should never have to ask, "where did the agent go?" The app should always have a visible answer.

## Rough Page Groupings

### Projects

- project list
- add/open project
- active status per project
- recent task summaries

### Project Dashboard

- active tasks
- recent runs
- failed or blocked work
- backend health for this project
- frequently used workflows

### Task Workspace

- workflow-state main surface
- conversation panel
- timeline panel
- artifacts panel
- inspector panel
- configuration panel

### Workflow Library

- templates
- imported workflows
- workflow details
- create/edit workflow
- role/tool/skill matrix

### Backend Manager

- Foundry
- Codex CLI
- Claude Code
- capability matrix
- health checks
- adapter diagnostics

### Profiles And Roles

- reusable profiles
- role definitions
- default tool policies
- model/context settings

### Skills And Hooks

- installed skills
- project-enabled skills
- hook configuration
- passive observation settings
- future guardrail settings

### Run Inspector

- timeline
- messages/output
- tool calls
- approvals
- context
- artifacts
- raw events
- backend request summaries

## Design Direction

The visual design should feel like a focused native macOS workbench.

It should be:

- dense enough for repeated engineering use
- calm enough for long sessions
- explicit about state and risk
- excellent at scanning lists, timelines, and configuration
- restrained with decoration
- built around panels, tables, timelines, and inspectors rather than marketing-style cards

The app should not feel like a chatbot clone. It should feel like an environment for operating agent work.

## UI Concept References

Rough visual references live in [docs/UI](./UI/README.md). These images are not final designs, but they are the current best reference for the project-scoped, task-centered, workflow-state interface direction.

The most important ideas to preserve from those concepts are:

- project navigation with nested tasks
- task header with backend, workflow, status, branch, and duration
- primary state surfaces for planning, running, approval, review, completion, and failure
- conversation as a secondary panel
- inspector and timeline as persistent observability surfaces
- approval views with command, risk, affected files, and explicit allow/deny actions

## Open Questions

- Is the user-facing object called Task, Session, Work Item, or something else?
- Should workflow authoring be native in v1, imported from generated specs, or both?
- How much backend configuration should be shown during task creation versus hidden behind profiles?
- Should project dashboards show tasks first or active runs first?
- How should interactive chat and non-interactive workflow steps share one layout?
- What is the minimal workflow spec that can support roles, tools, skills, hooks, approvals, and backend choices?

## Image Generation Prompts

Use these prompts to generate rough visual directions. They are intended for internal design exploration, not final UI.

### Prompt 1: Project Workspace Overview

Create a high-fidelity macOS app concept for "Hephaestus", a native operator environment for agent workflows. The app is project-scoped like Codex: a left sidebar lists local filesystem projects, a second column lists tasks within the selected project, and the main workspace shows the selected task. The selected task is not a simple chat; it has a workflow-state header, a primary "Running" surface with live steps, and right-side tabs for Timeline, Artifacts, Inspector, and Configuration. Visual style: native macOS, calm engineering tool, dense but readable, light mode, restrained color, no marketing hero, no decorative blobs, no oversized cards. Emphasize tables, timelines, segmented controls, status chips, toolbar icons, and a professional operator-console feel.

### Prompt 2: Task Workflow State Screen

Design a native macOS task workspace for an agent meta-harness called "Hephaestus". The selected task is in "Waiting for Approval" state. The header shows project path, backend "Codex CLI", workflow "ADR Implementation", branch, status, and duration. The main surface shows an approval request with command, risk summary, affected files, and Allow/Deny buttons. A left panel shows workflow steps: Draft, Plan, Implement, Review, Validate, Complete. A right inspector panel shows recent timeline events and tool calls. Include a collapsed conversation panel at the bottom. Style should be quiet, utilitarian, and optimized for engineering decisions.

### Prompt 3: Workflow Creation Surface

Create a macOS app screen for building an agent workflow in Hephaestus. The screen is a structured workflow editor, not a node graph. It includes a workflow template list, a step editor, a role/tool/skill access matrix, backend selection per step, approval policy controls, and expected artifact settings. Example roles: Planner, Implementer, Reviewer, Verifier. Example backends: Foundry, Codex CLI, Claude Code. Example tools: Shell, Files, Git, Browser, Docs. The design should feel like Xcode settings meets a serious operations console: compact controls, tables, segmented pickers, checkboxes, disclosure sections, and clear validation warnings.

### Prompt 4: Run Inspector And Observability

Design a high-fidelity macOS run inspector for Hephaestus, focused on observability for agent runs. The layout has a run header with backend, project, status, duration, model, and branch. The main area is split into a chronological event timeline and a selected event detail pane. Include tabs or sections for Transcript, Tool Calls, Approvals, Context, Files Changed, Raw Events, and Backend Requests. Show sample events like prompt submitted, tool call started, permission requested, file changed, test failed, retry, run completed. The UI should be dense, readable, native macOS, with strong scanning hierarchy and minimal decoration.

### Prompt 5: Backend Manager

Create a native macOS settings-style screen for Hephaestus backend management. It shows configured harness backends: Foundry, Codex CLI, and Claude Code. Each backend row shows health, version, executable path, supported capabilities, event capture mode, sandbox support, approval support, and structured output support. The detail pane for Codex CLI shows command path, detected version, default profile mapping, hook/event capture settings, and a capability matrix. Style should be practical, crisp, and engineering-focused, using tables, status indicators, icons, and compact forms.

### Prompt 6: Backend Comparison Task

Design a Hephaestus task screen for comparing the same task across multiple agent harness backends. The header shows project and task goal. The main view is a comparison matrix with columns for Foundry, Codex CLI, and Claude Code, and rows for status, duration, tool calls, files changed, approvals, failures, final result, and artifacts. Below the matrix is a synchronized timeline scrubber. A side panel shows selected backend run details. Visual style: native macOS, analytical, dense, suitable for engineering evaluation, no decorative hero graphics.
