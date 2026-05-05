# 0010. Tool Execution Context And Permission Boundary

**Status:** Proposed
**Date:** 2026-04-28
**Deciders:** Joshua Sumskas, Codex
**Technical Story:** Define the durable runtime boundary for tool calls, permission requests, context inclusion, and tool result persistence before adding basic write/edit tools.

---

## Context

PRD-0008 introduces basic agent tools: file write and file edit capabilities that can be requested during a single-agent run. This is more than a feature addition. Tool execution changes the shape of agent turns, provider requests, context assembly, persistence, inspection, and user trust.

Without a durable boundary, tool support could leak into the provider adapter, page interactor, or context manager in ways that are hard to undo. Tool calls also affect what should be included in later model context: raw tool arguments may contain entire file contents, tool results may become important run history, and permission decisions may need to be visible without becoming model instructions.

### Problem Statement

Hephaestus needs a tool execution architecture that supports model-requested tools while preserving:

- runtime ownership of turn execution,
- a scoped default grant for write/edit inside the session current directory,
- elevated permission requests for write/edit outside that directory, including explicit outside-workspace absolute paths,
- refusal for traversal and symlink escape attempts that disguise outside-scope access,
- inspectable but bounded persistence,
- context management that can include useful tool history without dumping raw arguments into every future turn, and
- provider adapters that translate wire protocol details without owning tool semantics.

### Goals

- Keep tool execution inside the runtime turn lifecycle.
- Auto-allow file write/edit only inside the session current directory by default.
- Require elevated permission for file write/edit outside the session current directory.
- Permit explicit outside-workspace absolute paths only through elevated one-shot approval.
- Refuse traversal and symlink escape attempts that disguise outside-scope access.
- Treat tool definitions as model-facing capability descriptions, not permission policy.
- Persist tool summaries for inspection and debugging.
- Keep full raw tool arguments out of normal app-state persistence by default.
- Give context management structured tool-result records it can select or omit.
- Allow user-customized core tool descriptions without changing executor behavior.

### Non-Goals

- Define every future tool type.
- Add shell execution.
- Add multi-agent tool sharing.
- Build a full artifact snapshot system.
- Decide the final approval UI shape beyond requiring a permission boundary.

## Decision Drivers

* Tool calls become part of the agent's causal history and must be inspectable.
* Context assembly must avoid unbounded replay of large or sensitive arguments.
* Provider-specific tool-call formats should not determine runtime architecture.
* File mutation requires a permission boundary that is harder to bypass than prompt text.
* Core tool descriptions need to be tunable without changing safety semantics.

## Considered Options

### Option 1: Provider-Owned Tool Execution

**Description:** Provider adapters parse tool calls and execute tools directly before returning final assistant output to the runtime.

**Pros:**
- Keeps `Run` simpler.
- Minimizes new kernel/runtime types at first.

**Cons:**
- Couples tool semantics to provider wire formats.
- Makes permission requests difficult to surface consistently.
- Hides tool events from the runtime event stream.
- Makes mock and live providers likely to diverge.

### Option 2: Runtime-Owned Tool Loop With Structured Tool Messages

**Description:** Provider adapters emit provider-neutral tool-call requests. `Run` owns permission checks, tool execution, tool result messages, follow-up provider requests, and events.

**Pros:**
- Keeps one turn lifecycle for mock and live providers.
- Makes permission requests and tool events first-class runtime behavior.
- Gives context management structured tool records.
- Keeps provider adapters focused on protocol translation.
- Supports persisted inspection and future replay.

**Cons:**
- Requires richer kernel/runtime data types.
- Makes `Run` more complex.
- Requires bounded loop guardrails to avoid runaway tool-call cycles.

### Option 3: UI-Owned Tool Execution

**Description:** The runtime emits a tool request event and the UI executes the tool or returns a result.

**Pros:**
- Permission UI is straightforward to attach.
- Keeps file-system work near app-level user interaction.

**Cons:**
- Breaks headless CLI and testability.
- Couples tool execution to SwiftUI/page lifecycle.
- Risks cancelling or losing tool work when views disappear.
- Conflicts with ADR-0009's service/runtime ownership direction.

## Decision

Hephaestus will use a runtime-owned tool loop with structured tool messages, a default current-directory grant for write/edit tools, elevated permission requests outside that grant, and refusal for traversal/symlink escape attempts that disguise outside-scope access.

**Chosen Option:** Option 2 - Runtime-Owned Tool Loop With Structured Tool Messages

### Rationale

Tool execution is part of a run, not a provider detail and not a page interaction detail. The runtime already owns turn sequencing, event ordering, cancellation, persistence handoff, and provider follow-up requests. Putting tool execution there keeps the behavior observable and testable across mock, CLI, and app paths.

Provider adapters should translate external tool-call protocols into provider-neutral `ProviderToolCall` values. They should not decide whether a tool is allowed, how file paths are sandboxed, or how tool results are persisted.

Permission checks are runtime decisions surfaced through the app or headless harness when elevation is required. A custom tool description can influence model behavior, but it cannot grant permission, change a schema, expand the current-directory default grant, or bypass sandboxing.

Context management should receive tool results as structured run history. Normal context assembly may include concise tool result messages and relevant summaries, but should not blindly include full raw arguments or full file contents.

File-tool authorization has a three-zone path model:

- inside the canonical session current directory: allowed by the default scoped grant,
- inside the canonical workspace root but outside the session current directory: requires elevated approval,
- explicit absolute path outside the workspace root: requires elevated approval scoped to the exact resolved path and tool call,
- workspace-relative escapes through `..` or symlinks: refused for v1.

Elevated approval is active-turn only in v1. If the pending decision is cancelled, expires, or is interrupted by app/session teardown, the runtime records a denied/cancelled tool result and does not execute the tool.

## Consequences

### Positive

- Tool events become visible in the same run timeline as messages, provider requests, and context traces.
- File tool usage has a consistent scoped grant and elevation boundary in app, CLI, and tests.
- Context policy can reason over tool messages separately from user and assistant text.
- Full raw arguments can be kept out of normal persistence and context by default.
- Provider adapters remain replaceable.
- User-customized descriptions are safe because they change model guidance only.

### Negative

- The `Run` execution path becomes a bounded state machine rather than a single provider pass.
- The runtime needs new guardrails such as maximum tool iterations and maximum tool calls per turn.
- Elevated permission request handling requires an app/service surface that can pause or await an active turn.
- The persistence model needs new tool-call records and event kinds.

### Neutral

- Tool result messages become part of run history.
- Context management must learn a new message/result type.
- Full artifact snapshots remain deferred.
- `HephaestusTools` may become a new module if file-tool implementation grows beyond core runtime contracts.
- Durable approval resume across app restarts is deferred.

## Context Management Rules

Tool calls introduce three different data categories:

- Tool request summary: tool name, target path, operation, and short argument summary.
- Tool result summary: status, affected path, byte counts or replacement counts, and short error/output text.
- Full arguments: raw JSON, potentially including full file contents.

Default future-turn context behavior should be:

- Include concise tool result messages when they help preserve turn continuity.
- Allow context policy to include or exclude tool summaries separately from user/assistant transcript text.
- Do not include full raw arguments by default.
- Do not include full file contents from write/edit arguments by default.
- Treat permission decisions as inspectable run metadata unless they are needed to explain an assistant-visible tool denial.

This keeps later turns aware that a tool succeeded or failed without making the context window a hidden file-content archive.

Immediate tool-loop continuation is separate from future-turn context. During the active tool loop, the runtime must preserve the provider-required ordering and correlation between tool calls and tool results. Later turns should receive a summary projection rather than a blind replay of the exact continuation payloads.

## Persistence Rules

Normal app-state persistence should store tool summaries:

- tool call ID,
- tool name,
- status,
- affected path when available,
- permission decision,
- permission source and scope,
- short argument summary,
- result or error summary,
- hashes for arguments/results where useful,
- timestamps and turn/run IDs.

Normal app-state persistence should not store full raw tool arguments by default. Full arguments may be enabled later through explicit diagnostics if the product has a redaction and retention story. V1 pending approval payloads may keep raw arguments in memory while the active turn is waiting, but they are not durable across app restarts.

## Implementation

High-level implementation notes:

- Add provider-neutral tool-call and tool-result types to the kernel/runtime boundary.
- Add a bounded runtime tool loop to `Run`.
- Add a canonical session current-directory grant for write/edit.
- Add elevated permission request records and events before write/edit execution outside that grant.
- Allow explicit outside-workspace absolute paths only through elevated one-shot approval.
- Refuse traversal and symlink escape attempts that disguise outside-scope access.
- Add `HephaestusTools` if concrete file-tool implementation would otherwise make `HephaestusKernel` or `HephaestusRuntime` own too much file-system detail.
- Add customizable tool descriptions as configuration used when building `ToolDefinition` values for provider requests.
- Keep executor semantics independent from customized descriptions.

## Validation

This decision is correct if:

- mock and live provider paths use the same runtime tool loop,
- write/edit inside the canonical session current directory can proceed under the default scoped grant,
- write/edit outside the canonical session current directory cannot proceed without an approval decision,
- explicit outside-workspace absolute paths cannot proceed without an approval decision scoped to the exact resolved path and tool call,
- denied tool calls are returned to the agent as structured tool results,
- tool summaries appear in run inspection data,
- context assembly distinguishes immediate tool-loop continuation from future-turn summaries, and
- customized core tool descriptions affect provider requests but do not affect permissions or executor behavior.

## Related Decisions

- [0002. Swift Kernel Baseline](./0002-swift-kernel-baseline.md)
- [0007. Headless Runtime Entrypoint](./0007-headless-runtime-entrypoint.md)
- [0008. Local App State Storage](./0008-local-app-state-storage.md)
- [0009. Persistent Chat Session Service And UI Subscription Boundary](./0009-persistent-chat-session-service.md)

## References

- [PRD-0008. Basic Agent Tools](../prd/0008-basic-agent-tools.md)
- [Basic Agent Tools Technical Design](../plans/0007-basic-agent-tools-technical-design.md)

---

## Notes

The main architectural consequence is that tools are not just provider features. They are run events, context inputs, permissioned workspace operations, and inspectable artifacts of a turn.

**Last Updated:** 2026-04-28
