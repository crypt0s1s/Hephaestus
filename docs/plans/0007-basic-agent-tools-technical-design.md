# Basic Agent Tools Technical Design

**Status:** Draft
**Date:** 2026-04-28
**Owner:** Codex
**Related PRD:** [PRD-0008. Basic Agent Tools](../prd/0008-basic-agent-tools.md)
**Related ADR:** [ADR-0010. Tool Execution Context And Permission Boundary](../adr/0010-tool-execution-context-and-permission-boundary.md)
**Related Docs:** [Roadmap](../roadmap.md), [Run Inspection PRD](../prd/0006-run-inspection.md), [Chat Session Service Refactor Plan](./0006-chat-session-service-refactor-plan.md)

## Purpose

Define how [PRD-0008. Basic Agent Tools](../prd/0008-basic-agent-tools.md) should be implemented in the current Hephaestus runtime, provider, persistence, and inspection architecture.

Product behavior, scope, and acceptance criteria remain in the PRD. This design covers the runtime shape for model-requested tools, permission checks, structured tool results, persistence, and inspection with the smallest useful pair of tools.

## Current State

The current runtime has these useful boundaries:

- `Run` owns turn execution, messages, turns, status, and event sequence.
- `ProviderClient` streams assistant text from a `ProviderRequest`.
- `ProviderRequest` contains system/user/assistant/tool-capable message roles, but only text deltas are currently modeled.
- `RuntimeEvent` and `RunEvent` are the observation and persistence seam.
- `PersistentStreamUserMessageUseCase` persists messages, events, provider request summaries, and context traces.
- `ChatFeature` talks to runtime through use cases rather than constructing provider requests directly.

The missing pieces are:

- tool definitions available to the provider,
- provider output that can request a tool call,
- a runtime tool executor,
- permission policy,
- user-customizable model-facing tool descriptions,
- structured tool-call events,
- persistent tool-call inspection data,
- a workspace/file artifact model for write/edit results.

## Product Slice

Implement a v1 tool loop for a single assistant turn:

1. User sends a message.
2. Runtime prepares context and provider request.
3. Provider may request one or more tool calls.
4. Runtime canonicalizes affected paths.
5. Runtime auto-approves write/edit calls inside the session current directory.
6. Runtime creates an elevated permission request for write/edit calls outside the session current directory.
7. User approves or denies the elevated request.
8. Runtime executes approved calls or records denied results.
9. Runtime appends tool result messages.
10. Runtime sends a follow-up provider request with the tool results.
11. Assistant returns final text.
12. Events and persisted inspection data show what happened.

## Scope

### In Scope

- `write_file` tool that writes complete file contents.
- `edit_file` tool that applies a narrow text replacement or patch-like edit.
- Local workspace-root sandboxing.
- Default scoped allow for `write_file` and `edit_file` inside the session current directory.
- Elevated permission requests for write/edit attempts outside the session current directory, including explicit outside-workspace absolute paths.
- Refusal for traversal and symlink escape attempts that disguise outside-scope access.
- User-customizable model-facing descriptions for core tools.
- Structured tool definitions, arguments, results, and events.
- Provider support for OpenAI-compatible tool calls.
- Mock provider support for deterministic tests.
- Persisted summaries for tool calls/results.
- Run inspector readiness through persisted records, even if the UI view is added later.

### Out Of Scope

- Shell commands.
- File deletion.
- Directory-wide rewrites.
- Binary file editing.
- Multi-agent tool ownership.
- Background tool tasks.
- Rich approval preferences such as remember-for-session or remember-for-path.
- AST-aware editing or language-server integration.
- Merge/conflict resolution.

## Architecture

```text
Run
  -> ContextManaging
  -> ToolRegistry.availableTools(policy:)
  -> ProviderClient.stream(request with tools)
  -> ProviderToolCall deltas / completed tool call requests
  -> ToolPermissionAuthorizing
  -> ToolExecutor.execute(...)
  -> FileToolWorkspace
  -> RunEvent.toolCall*
  -> follow-up ProviderRequest with tool result messages
  -> final assistant message
```

The key rule: provider adapters parse tool-call protocol details, but `Run` owns the tool loop. Tools do not call the provider, and UI does not execute tools directly.

## Kernel Model Changes

Add tool-capable provider types in `HephaestusKernel`.

```swift
public struct ToolDefinition: Sendable, Hashable, Codable {
    public let name: String
    public let description: String
    public let inputSchema: ToolInputSchema
}

public struct ToolInputSchema: Sendable, Hashable, Codable {
    public let jsonSchema: String
}

public struct ProviderToolCall: Sendable, Hashable, Codable, Identifiable {
    public let id: String
    public let name: String
    public let argumentsJSON: String
}

public enum ProviderToolChoice: Sendable, Hashable, Codable {
    case auto
    case none
    case required
}

public enum ProviderDelta: Sendable, Hashable {
    case text(String)
    case toolCallCompleted(ProviderToolCall)
}
```

Provider adapters may assemble streamed tool-call deltas internally, but the kernel-facing runtime only needs completed, normalized `ProviderToolCall` values for v1. This keeps OpenAI-compatible delta details out of the provider-neutral model.

Update `ProviderRequest`:

```swift
public struct ProviderRequest: Sendable, Hashable, Identifiable, Codable {
    public let tools: [ToolDefinition]
    public let toolChoice: ProviderToolChoice
}
```

Add a richer message part so tool results can stay structured while still rendering as text:

```swift
public enum MessagePart: Sendable, Hashable, Codable {
    case text(String)
    case toolResult(ToolResultMessage)
}

public struct ToolResultMessage: Sendable, Hashable, Codable {
    public let providerToolCallID: String
    public let toolName: String
    public let status: ToolExecutionResult.Status
    public let text: String
}
```

For v1, it is acceptable to keep persisted display text as the primary UI representation and store full tool-call detail in dedicated persisted records.

## What Goes In `HephaestusTools`

If the project adds a separate tools module, it should own reusable tool infrastructure and concrete local tool executors. It should not own the run loop, provider transport, app UI, or persistence store.

Recommended `Core/HephaestusTools` contents:

- Tool catalog and registry implementations.
- Core tool definitions for `write_file` and `edit_file`.
- Tool description override models and resolution logic.
- Tool argument structs and JSON decoding/validation.
- File workspace sandbox helpers.
- Path normalization and symlink escape checks.
- Text-file safety checks such as UTF-8 validation and binary-content rejection.
- Concrete `WriteFileToolExecutor` and `EditFileToolExecutor`.
- Tool authorization helper types that turn policy into scoped grants or permission requests.
- Test fakes for tool execution.

Keep these outside `HephaestusTools`:

- `Run` orchestration and provider follow-up loops: `HephaestusKernel` / `HephaestusRuntime`.
- OpenAI-compatible tool-call wire encoding/parsing: `HephaestusLLM`.
- Persisted app-state records: `HephaestusRuntime`.
- Permission request UI: `ChatFeature` or app feature layer.
- Provider settings and app composition: `HephaestusComposition`.

This split keeps tools reusable without making the tools module responsible for the whole agent harness.

### Package Dependency Direction

Recommended dependency direction:

- `HephaestusKernel` owns provider-neutral tool contracts, tool-call/result value types, and runtime protocol shapes.
- `HephaestusTools` depends on `HephaestusKernel` and owns concrete local file-tool executors plus path/safety helpers.
- `HephaestusRuntime` depends on `HephaestusKernel` protocols and owns the run loop, permission events, persistence handoff, and context projection.
- `HephaestusLLM` depends on `HephaestusKernel` and translates provider wire formats into normalized tool calls.
- `HephaestusComposition` wires concrete `HephaestusTools` implementations into `HephaestusRuntime`.

`HephaestusRuntime` should not import concrete file-tool executors directly if the package split is introduced. Composition should provide the registry/executors.

## Tool Runtime Interfaces

Add a runtime-owned tool package or keep the v1 protocols in `HephaestusKernel` until the boundary proves itself. If split now, prefer `Core/HephaestusTools` so file tools do not inflate the kernel.

```swift
public protocol ToolRegistry: Sendable {
    func availableTools(for policy: ToolPolicy) async -> [ToolDefinition]
    func resolve(name: String) async -> (any ToolExecutor)?
}

public protocol ToolExecutor: Sendable {
    var definition: ToolDefinition { get }
    func execute(_ request: ToolExecutionRequest) async -> ToolExecutionResult
}

public protocol ToolPermissionAuthorizing: Sendable {
    func authorization(
        for request: ToolExecutionRequest,
        policy: ToolPolicy
    ) async -> ToolAuthorizationDecision
}

public enum ToolAuthorizationDecision: Sendable, Hashable {
    case allow(PermissionGrant)
    case deny(String)
    case requireApproval(PermissionRequest)
}

public struct ToolExecutionRequest: Sendable, Hashable {
    public let id: UUID
    public let runID: UUID
    public let turnID: UUID
    public let providerToolCallID: String
    public let toolName: String
    public let argumentsJSON: String
    public let workspaceRoot: URL
    public let sessionCurrentDirectory: URL
    public let resolvedTarget: ResolvedWorkspacePath
}

public struct PermissionGrant: Sendable, Hashable, Codable {
    public enum Source: String, Sendable, Hashable, Codable {
        case defaultCurrentDirectory
        case elevatedUserApproval
        case test
    }

    public let source: Source
    public let toolName: String
    public let operations: [ToolOperation]
    public let scope: PermissionScope
    public let lifetime: GrantLifetime
}

public enum PermissionScope: Sendable, Hashable, Codable {
    case directory(String)
    case exactPath(String)
}

public enum GrantLifetime: String, Sendable, Hashable, Codable {
    case once
    case turn
    case session
}

public struct PermissionRequest: Sendable, Hashable, Codable {
    public let toolCallID: String
    public let toolName: String
    public let operation: ToolOperation
    public let rawPath: String
    public let resolvedWorkspacePath: String
    public let argumentSummary: String
}

public enum ToolOperation: String, Sendable, Hashable, Codable {
    case write
    case edit
}

public struct ResolvedWorkspacePath: Sendable, Hashable, Codable {
    public enum Location: String, Sendable, Hashable, Codable {
        case insideSessionCurrentDirectory
        case insideWorkspaceOutsideSessionCurrentDirectory
        case outsideWorkspace
        case unsafe
    }

    public let rawPath: String
    public let workspaceRelativePath: String?
    public let canonicalPath: String?
    public let location: Location
}

public struct ToolExecutionResult: Sendable, Hashable, Codable {
    public enum Status: String, Sendable, Hashable, Codable {
        case succeeded
        case failed
        case denied
        case awaitingApproval
    }

    public let status: Status
    public let outputText: String
    public let metadata: [String: String]
    public let error: String?
}
```

## Tool Description Customization

Each core tool should have a stable implementation identity and a model-facing description that can be overridden by user settings.

```swift
public struct CoreToolDescriptor: Sendable, Hashable, Codable {
    public let name: String
    public let defaultDescription: String
    public let inputSchema: ToolInputSchema
}

public struct ToolDescriptionOverrides: Sendable, Hashable, Codable {
    public var descriptionsByToolName: [String: String]
}
```

Resolution rule:

1. Start from the built-in `CoreToolDescriptor`.
2. If a non-empty override exists for that tool name, use it as `ToolDefinition.description`.
3. Keep the same tool name, argument schema, executor, permission behavior, and safety checks.
4. Reject empty override descriptions.
5. Offer a reset path that removes the override and restores the default description.

These descriptions are prompts for the model, not authorization policy. A custom description must never weaken sandboxing, expand the default current-directory grant, skip elevated permission requests, or change executor semantics.

## File Tools

### Path Model

V1 file tool paths support two explicit forms:

- workspace-relative paths for normal in-workspace operations,
- absolute paths only for elevated outside-workspace requests.

The session has two canonical directories:

- `workspaceRoot`: the outer sandbox for file tools.
- `sessionCurrentDirectory`: a canonical directory inside `workspaceRoot` that receives the default write/edit grant.

Chats are created inside a workspace group. The group owns the canonical workspace directory, and new chats in that group inherit it as both `workspaceRoot` and initial `sessionCurrentDirectory`.

Resolution behavior:

- raw paths containing `..` segments are refused for v1,
- workspace-relative paths resolving inside `sessionCurrentDirectory` are eligible for the default grant,
- workspace-relative paths resolving inside `workspaceRoot` but outside `sessionCurrentDirectory` require elevated approval,
- explicit absolute paths require elevated approval and are scoped to the exact resolved absolute target,
- workspace-relative symlink escapes from an inside-looking path are refused rather than elevated.

For existing files, resolve the final target and compare its canonical location to the canonical workspace/current-directory roots.

For new files, resolve the nearest existing parent directory, verify it is inside the authorized scope, reject if any existing parent component is a symlink escape, create missing components only under that verified parent when requested, and revalidate the parent immediately before the atomic write.

If the session current directory itself no longer resolves inside the workspace root, disable the default grant and fail default-scoped tool calls until the session directory is repaired or reselected.

Recommendation: tool descriptions should strongly prefer workspace-relative paths for all in-workspace edits. Absolute paths should be described as exceptional and elevated, so the model does not use them for routine workspace edits.

### `write_file`

Arguments:

```json
{
  "path": "workspace/relative/path.txt",
  "content": "complete file contents",
  "createIntermediateDirectories": true,
  "overwrite": false
}
```

Behavior:

- Resolve `path` as workspace-relative unless it is an explicit absolute path.
- Reject `..` escapes, symlink escapes, directories, and binary-looking content.
- Auto-allow only when the resolved target is inside `sessionCurrentDirectory`.
- Request elevated approval when the resolved target is inside `workspaceRoot` but outside `sessionCurrentDirectory`.
- Request elevated approval when an explicit absolute path resolves outside `workspaceRoot`.
- Create parent directories only when requested.
- Fail if the file exists and `overwrite == false`.
- Write atomically.
- Return bytes written, created/overwritten status, and normalized relative path.

### `edit_file`

V1 should avoid inventing a full patch parser. Use exact replacement first:

```json
{
  "path": "workspace/relative/path.txt",
  "oldText": "exact text to replace",
  "newText": "replacement text",
  "expectedOccurrences": 1
}
```

Behavior:

- Apply the same path normalization and sandbox checks as `write_file`.
- Read UTF-8 text only.
- Count occurrences of `oldText`.
- Fail unless count matches `expectedOccurrences`.
- Write atomically.
- Return replacements applied, byte delta, and normalized relative path.

This gives deterministic edits and good failure messages. A unified-diff or structured patch tool can be added after this path is observable and tested.

## Permission Model

Introduce a session-scoped policy:

```swift
public struct ToolPolicy: Sendable, Hashable, Codable {
    public let workspaceRootPath: String
    public let sessionCurrentDirectoryPath: String
    public let grants: [PermissionGrant]
}
```

Initial defaults:

- Mock runtime: tests may use a temporary session current directory and inject elevated approval decisions deterministically.
- App runtime: `write_file` and `edit_file` are allowed inside the canonical session current directory by default.
- App runtime: `write_file` and `edit_file` outside the canonical session current directory create elevated permission requests.
- App runtime: explicit absolute outside-workspace write/edit attempts create elevated permission requests scoped to the exact resolved target and tool call.
- App runtime: workspace-relative traversal or symlink escape attempts are refused rather than elevated.
- CLI/dev harness: same default as app runtime, with explicit test-only hooks for deterministic elevated approvals.

The policy belongs with session-scoped runtime composition, matching the existing `ChatSessionService` plan note that tool permissions are per-chat/session policy.

For this PRD, the built-in default grant is path-scoped: it allows write/edit only inside the canonical session current directory. Elevated approvals are `once` grants scoped to the exact resolved path and provider tool call ID for v1. Raw relative paths such as `.` must be resolved once into a canonical directory for the session so the grant boundary does not drift with process state. The root must also be revalidated before each tool execution so directory replacement does not silently change the grant target.

### Approval State

V1 elevated approvals are active-turn only. If the page detaches, the run is cancelled, the app exits, or the pending request expires before a decision, the runtime records a denied/cancelled tool result and does not execute the tool.

This avoids durable resumable side effects in the first slice. A later ADR can introduce persisted pending approvals, but v1 should not imply that approval survives reload.

For multiple tool calls in one provider response, v1 should authorize the full batch before executing any side-effecting file tool. If any elevated request is denied, the runtime returns denied results without partial mutation for that batch.

## Run Event Changes

Extend `RunEvent` and `RuntimeEvent`:

```swift
case toolCallRequested(EventHeader, ToolCallRecord)
case toolCallPermissionEvaluated(EventHeader, ToolCallPermissionRecord)
case toolCallStarted(EventHeader, ToolCallRecord)
case toolCallCompleted(EventHeader, ToolCallResultRecord)
case toolCallFailed(EventHeader, ToolCallResultRecord)
case toolCallDenied(EventHeader, ToolCallResultRecord)
```

Keep event payloads summary-sized. Large content should not be duplicated into every event. Store enough to inspect:

- tool call ID,
- tool name,
- normalized path when applicable,
- status,
- short argument summary,
- short output/error summary,
- timestamps and sequence.

## Persistence

Add to `PersistedSession`:

```swift
public var toolCalls: [PersistedToolCall]
```

`PersistedToolCall` should include:

- `id: UUID`
- `runID`
- `turnID`
- `providerToolCallID`
- `toolName`
- `status`
- `argumentSummary`
- `resultSummary`
- `affectedPath`
- `permissionDecision`
- `permissionScope`
- `permissionSource`
- `argumentHash`
- `resultHash`
- `createdAt`
- `completedAt`
- `error`

Update `PersistedRuntimeEvent.Kind` with tool event kinds. `PersistedSession.apply(...)` should append/update `toolCalls` when tool events arrive.

For v1, do not store full file content in app state. The file itself is the artifact. Later artifact tracking can store hashes, previews, and file snapshots. Pending approval payloads may retain raw arguments in memory while the active turn is waiting, but routine persisted audit records should store summaries and hashes.

### Full Arguments Persistence

"Should full arguments be persisted?" means: when the model calls a tool, should Hephaestus store the entire raw argument payload, or only a summary?

For example, a `write_file` call might include:

```json
{
  "path": "Sources/App/Main.swift",
  "content": "...entire file contents..."
}
```

Persisting full arguments would save both `path` and the complete `content` string in app state. That improves replay/debugging, but it can duplicate large files, capture sensitive code or secrets, and bloat the JSON store. Persisting a summary would save fields such as tool name, path, byte count, content hash, and status, but not the full content.

Recommendation for v1:

- Persist summaries by default.
- Persist full arguments only in opt-in debug builds or behind an explicit diagnostic setting.
- Never persist full file contents for routine app usage until the artifact model and redaction policy are stronger.

### Context Projection

Tool data has two projections:

- Immediate continuation projection: the provider-specific follow-up payload required to continue the active tool loop. This preserves provider ordering requirements and includes the exact tool result needed by the model for that pass.
- Future-turn summary projection: concise run-history summaries that the context manager may include in later turns. This should include tool name, status, affected path, permission decision, and result/error summary, but not full raw arguments or full file contents by default.

The context manager should not reconstruct future-turn context by blindly replaying the immediate continuation payloads.

## Provider Adapter Changes

### OpenAI-Compatible Adapter

Update `OpenAICompatibleProviderClient` to:

- encode `tools` in chat-completions compatible format,
- encode `tool_choice`,
- parse streamed tool-call deltas,
- emit completed `ProviderToolCall` once the call name and arguments JSON are complete,
- support follow-up messages with role `tool` and `tool_call_id`.

The kernel should not expose OpenAI wire names directly. The adapter translates between OpenAI-compatible JSON and kernel-native `ToolDefinition`, `ProviderToolCall`, and `RunMessage`.

### Mock Provider

Add deterministic trigger behavior for tests:

- If the last user message starts with `write:`, request `write_file`.
- If it starts with `edit:`, request `edit_file`.
- After receiving a tool result message, return final assistant text summarizing success/failure.

This keeps tests local and avoids depending on model behavior.

## Turn Loop

Modify `Run.executeUserMessage` from a single provider pass to a bounded loop:

```text
provider pass 1
  text only -> complete assistant message
  tool calls -> execute tools, append tool result messages, provider pass 2
provider pass N
  repeat until final text or maxToolIterations reached
```

Add guardrails:

- `maxToolIterations`, default `4`.
- `maxToolCallsPerTurn`, default `8`.
- Stop and fail the turn if provider asks for an unknown tool.
- Return a denied tool result if the user denies a permission request.
- Keep the active turn waiting on the permission decision; if the active turn is cancelled or detached without a decision in v1, record a denied/cancelled tool result.
- Authorize a provider response's full side-effecting tool-call batch before executing any write/edit call.

## Inspection

The run inspector should eventually show:

- provider request,
- tool requested,
- permission result,
- permission source and scope,
- execution result,
- affected path,
- follow-up provider request,
- final assistant response.

This design stores enough data for that UI without forcing the UI into the first implementation slice.

## Testing Plan

Add tests for:

- `write_file` creates a new file inside the session current directory under the default grant.
- `write_file` requests elevated approval for workspace-relative paths outside the session current directory.
- `write_file` requests elevated approval for explicit absolute paths outside the workspace.
- `write_file` refuses `..` paths and symlink escapes.
- `write_file` resolves the nearest existing parent for new files and revalidates before atomic write.
- `write_file` rejects existing files without overwrite.
- `edit_file` replaces exactly one occurrence.
- `edit_file` fails on zero or multiple unexpected occurrences.
- permission request denial prevents file changes and returns a denied tool result.
- batch tool calls do not create partial side effects before required elevated approvals are resolved.
- a mock run executes `write_file`, appends a tool message, and receives final assistant text.
- persisted runtime records include ordered tool events, permission decision details, and a `PersistedToolCall`.
- OpenAI-compatible request encoding includes tools and tool messages.
- OpenAI-compatible parser reconstructs streamed tool-call arguments.

Validation commands:

```sh
CLANG_MODULE_CACHE_PATH="$PWD/.build/clang-module-cache" swift test -Xswiftc -strict-concurrency=complete -Xswiftc -warnings-as-errors
CLANG_MODULE_CACHE_PATH="$PWD/.build/clang-module-cache" swift run HephaestusCLI "write: docs/scratch.md hello"
xcodebuild -workspace Hephaestus.xcworkspace -scheme Hephaestus -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO build
```

The CLI command should be adjusted to whatever explicit dev-harness syntax is implemented for enabling file tools.

## Implementation Order

1. Add kernel tool data types and provider request fields with no behavior change.
2. Add `ToolExecutor`, `ToolRegistry`, `ToolPolicy`, scoped grants, and local file workspace helpers.
3. Implement and test `write_file` and `edit_file` executors.
4. Add tool event types and persistence records.
5. Teach `MockProviderClient` to request tools deterministically.
6. Update `Run` to execute a bounded tool loop.
7. Update OpenAI-compatible encoding/parsing.
8. Add inspector-ready persisted summaries.
9. Wire policy through persistent runtime composition.
10. Add minimal CLI/dev harness path for manual validation.

## Open Questions

- Should full tool argument JSON be persisted, redacted, or only summarized?
- Should file tools live in a separate `HephaestusTools` module immediately?
- Should the app expose a workspace picker before enabling write/edit tools?
- Should `edit_file` later support unified diffs, or should Hephaestus keep exact replacement as the stable primitive and layer smarter planning above it?

## Recommendation

Build this in two milestones.

Milestone 1 should stay fully local and deterministic: tool types, file executors, mock-provider tool loop, permission request approval/denial, persistence, and tests.

Milestone 2 should add OpenAI-compatible tool-call parsing plus the first UI affordance for enabling a workspace/tool policy. That avoids coupling safety UX to the low-level runtime proof while still keeping the model-facing protocol close behind.
