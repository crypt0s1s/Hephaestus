# UI Concept References

This folder contains rough visual concepts for the future Hephaestus app interface. They are not final designs, but they are useful references for product direction, information architecture, and future implementation planning.

## Files

- [UI Design Request.png](./UI%20Design%20Request.png): running task workspace with workflow state, live plan, logs, conversation, and inspector.
- [UI Design Request (1).png](./UI%20Design%20Request%20(1).png): planning-focused task workspace with editable steps and collapsed inspector.
- [UI Design Request (2).png](./UI%20Design%20Request%20(2).png): approval-focused task workspace with risk summary, command, affected files, and conversation.

## What To Preserve

- Project-scoped navigation: a local project list with tasks nested beneath each project.
- Task as the main object: the selected item is workflow-shaped, not just a chat.
- Workflow-state header: project, backend, workflow, status, branch, and duration are visible at the top.
- State-driven main surface: planning, running, and waiting-for-approval each get a different primary layout.
- Conversation as a panel: chat remains useful, but it is secondary to the task state and workflow surface.
- Inspector as a durable area: observability should be nearby, not hidden behind a transient popover.
- Approval UX: command, risk summary, affected files, and allow/deny controls are the right level of operational detail.
- Dense native workbench feel: tables, timelines, steps, status indicators, and compact controls fit the intended audience.

## Design Questions

- Should the far-left app navigation include `Agents`, or should that become `Workflows`, `Backends`, or `Profiles`?
- Should the main unit be named Task, Session, Work Item, or something else in the UI?
- What belongs in the project column versus a separate task list page?
- When should the inspector be always visible, collapsed, or opened as a full page?
- How should the UI adapt when a workflow has no conversation component?
- How should the UI represent multiple runs inside one task, especially retries or backend comparisons?
- How much backend configuration should be visible in the task header versus the configuration panel?
- Should focus mode hide project navigation, inspector, conversation, or all secondary panels?

## Implementation Implications

These concepts imply several architectural requirements:

- A project domain model independent of chat.
- A task domain model above runs and conversations.
- A workflow-state model that can drive the primary task surface.
- A reusable run inspector and observation model.
- A backend capability model so Foundry, Codex CLI, and Claude Code can render different available controls.
- A conversation feature that can render as a panel inside task workspace.
- A design system for dense panels, step lists, status chips, inspector rows, and command/risk summaries.

## Current Preferred Direction

Use the concepts as directional references, with this product shape:

```text
Project
  Task
    Workflow state surface
    Conversation panel
    Timeline panel
    Artifacts panel
    Inspector panel
    Configuration panel
```

The app should feel like an operator workbench for agent tasks. It should not regress into a chatbot layout with extra panels attached.
