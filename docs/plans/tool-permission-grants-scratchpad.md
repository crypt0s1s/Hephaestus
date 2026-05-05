# Tool Permission Grants Scratchpad

**Status:** Scratchpad
**Date:** 2026-04-29
**Related PRD:** [PRD-0008. Basic Agent Tools](../prd/0008-basic-agent-tools.md)
**Related ADR:** [ADR-0010. Tool Execution Context And Permission Boundary](../adr/0010-tool-execution-context-and-permission-boundary.md)

## Purpose

Explore how Hephaestus should model permission requests and grants before turning the design into stable PRD, ADR, or implementation text.

The core idea is that a tool call should not directly imply execution. A tool call should produce an authorization problem, and the runtime should resolve that problem through one or more grant providers before executing the tool.

This is future exploration. PRD-0008 only needs the subset for `write_file` and `edit_file`: default current-directory grant, elevated one-shot approval outside the current directory, and refusal for traversal/symlink escape attempts.

## Base Flow

```text
ProviderToolCall
  -> normalize tool call
  -> classify operation and risk
  -> evaluate built-in current-directory grant and existing grants
  -> if no grant matches, create PermissionRequest
  -> resolve request through one or more GrantProviders
  -> execute only if the final decision approves
  -> persist decision and execution summary
```

## Permission Request

A permission request should describe the concrete action, not just the tool name.

```swift
struct PermissionRequest: Identifiable, Sendable, Codable {
    let id: UUID
    let runID: UUID
    let turnID: UUID
    let toolCallID: String
    let toolName: String
    let operation: ToolOperation
    let subject: PermissionSubject
    let argumentSummary: String
    let risk: ToolRisk
    let createdAt: Date
}

enum ToolOperation: String, Sendable, Codable {
    case read
    case search
    case write
    case edit
    case shell
}

enum PermissionSubject: Sendable, Codable {
    case paths([WorkspacePath])
    case shell(ShellCommandSummary)
}

enum ToolRisk: String, Sendable, Codable {
    case low
    case medium
    case high
    case unknown
}
```

The `subject` must be normalized before display and authorization. For file tools, this means workspace-relative canonical paths. For shell tools, this means a parsed command summary rather than raw command text only.

## Grant Providers

Different approval mechanisms can share one interface.

```swift
protocol GrantProvider: Sendable {
    var id: String { get }

    func resolve(
        _ request: PermissionRequest,
        context: PermissionContext
    ) async -> PermissionResolution
}

enum PermissionResolution: Sendable, Codable {
    case approved(PermissionGrant)
    case denied(reason: String?)
    case needsUserInteraction(PermissionChallenge)
    case abstain
}
```

Possible providers:

- `ExistingGrantProvider`: checks previously approved grants.
- `PopupGrantProvider`: asks the local user in the macOS app.
- `SMSGrantProvider`: sends an approval challenge to a phone.
- `ExternalLLMRiskProvider`: asks another model to classify risk or recommend approve/deny.
- `AlwaysConfirmProvider`: forces user confirmation even if a broad grant might match.
- `DenyListProvider`: immediately denies known-disallowed operations.
- `TestGrantProvider`: deterministic approval/denial for tests.

Important: provider output should be combined by policy. A low-risk recommendation from an external LLM should not bypass an explicit user-confirmation requirement.

## Grant Shape

```swift
struct PermissionGrant: Identifiable, Sendable, Codable {
    let id: UUID
    let grantedByProviderID: String
    let toolName: String
    let operations: Set<ToolOperation>
    let subjectScope: PermissionScope
    let lifetime: GrantLifetime
    let constraints: [GrantConstraint]
    let createdAt: Date
    let expiresAt: Date?
}

enum PermissionScope: Sendable, Codable {
    case exactPath(WorkspacePath)
    case directory(WorkspacePath)
    case workspaceRoot
    case shellCommand(ShellCommandPattern)
    case shellCommandClass(ShellCommandClass)
}

enum GrantLifetime: String, Sendable, Codable {
    case once
    case turn
    case session
    case project
}

enum GrantConstraint: Sendable, Codable {
    case maxRisk(ToolRisk)
    case requireNoNetwork
    case requireNoFileMutation
    case requireNoProcessSpawn
    case requireInteractiveConfirmation
}
```

The grant is scoped by both capability and subject. For example:

- approve `edit_file` for one exact file once,
- approve `read_file` in `Sources/` for this session,
- approve `bash` only for `git status` in this project,
- require confirmation for every `bash` command, even if command class is known.

## Built-In Current Directory Grant

For the initial write/edit tools, Hephaestus should create a built-in scoped grant at session start:

```swift
PermissionGrant(
    grantedByProviderID: "hephaestus.default-current-directory",
    toolName: "write_file/edit_file",
    operations: [.write, .edit],
    subjectScope: .directory(sessionCurrentDirectory),
    lifetime: .session,
    constraints: []
)
```

The grant should use the canonical session current directory, not raw `"."`.

Resolution rules:

- `write_file` and `edit_file` inside the canonical session current directory are allowed by default.
- `write_file` and `edit_file` outside the canonical session current directory become elevated permission requests.
- explicit absolute outside-workspace paths become elevated permission requests scoped to the exact resolved path and tool call.
- path traversal and symlink traversal must be evaluated after canonicalization.
- explicit absolute paths can request elevation; raw `..` segments are refused for v1 rather than elevated.
- if the canonical path cannot be resolved safely, deny rather than guessing.
- new-file writes must resolve the nearest existing parent, verify that parent is inside the approved scope, create missing components only below that parent, and revalidate immediately before writing.
- elevated approvals are `once` grants scoped to the exact resolved workspace path and tool call ID in v1.
- if arguments, current-directory identity, or resolved target change before execution, the approval is invalid and must be requested again.

This gives the agent useful local editing ability without requiring a prompt for every normal write/edit, while still making broader workspace access explicit.

## Always Confirm

Some requests should always require confirmation, even if a matching grant exists.

This is especially relevant for shell commands because a command line can do more than its first token suggests.

Examples:

- `bash` command contains command separators such as `;`, `&&`, `||`, `|`.
- command includes command substitution or redirection.
- command invokes an interpreter such as `sh`, `bash`, `python`, `ruby`, `node`, or `osascript`.
- command writes outside the workspace.
- command starts a network operation.
- command mutates git history or deletes files.
- command risk classifier returns `high` or `unknown`.

Represent this as policy, not a grant:

```swift
struct PermissionPolicy {
    let defaultMode: PermissionMode
    let alwaysConfirmRules: [AlwaysConfirmRule]
    let grantProviders: [GrantProviderConfiguration]
}

enum PermissionMode: String, Codable {
    case requireApproval
    case deny
}
```

For early Hephaestus, default mode should allow write/edit inside the canonical session current directory and require elevated approval outside it. Shell should still default to `requireApproval` and may stay out of scope until the permission system can parse and classify command lines.

## Shell Commands

Bash deserves a different model from file tools. File tools have constrained schemas and known subjects. Shell commands are open-ended and can combine many actions.

### Command Parsing

Before authorization, parse a shell command into independently inspectable command segments. Segment splitting alone is not sufficient for safety; future shell support needs a real parser plus process sandbox enforcement.

Examples:

```sh
git status
```

One segment:

```text
git status
```

```sh
git status && rm -rf build
```

Two segments:

```text
git status
rm -rf build
```

```sh
cat Package.swift | grep target
```

Two segments plus pipe relationship:

```text
cat Package.swift
grep target
```

Each segment should be classified. The final authorization should use the highest risk segment and should require confirmation if any segment triggers an always-confirm rule.

Future shell design must account for redirection-only writes, heredocs, process substitution, glob expansion, aliases/functions, interpreter wrappers such as `env sh -c`, and command substitution. The permission model should treat parser uncertainty as `unknown` risk and require confirmation.

### Shell Risk Classes

```swift
enum ShellCommandClass: Sendable, Codable {
    case readOnly
    case fileMutation
    case network
    case processControl
    case gitMutation
    case destructive
    case interpreter
    case unknown
}
```

Early allow rules should be narrow:

- `git status`
- `git diff`
- `ls`
- `pwd`
- `rg` without write flags

Even read-like shell commands should not be treated as equivalent to file read tools, because shell can bypass file-tool path checks unless the process sandbox enforces access.

## External LLM Risk Review

An external LLM can be a risk reviewer, not the authority of record.

Good use:

- summarize what a shell command appears to do,
- classify likely risk,
- flag suspicious patterns,
- recommend whether user approval should be required.

Risky use:

- allowing the external model to approve execution by itself,
- hiding the command from the user because the reviewer said it is safe,
- treating the reviewer as a sandbox.

Recommendation:

```text
External LLM review can raise risk or require confirmation.
It should not lower a request below the runtime's baseline policy.
```

## SMS Or Remote Approval

Remote approval is just another grant provider.

It should produce the same decision shape as a local popup:

- approve once,
- approve for turn,
- approve for session with scope,
- deny.

Remote approval should include a compact request summary:

- agent/session identity,
- tool name,
- operation,
- target paths or shell summary,
- risk level,
- expiration time,
- approve/deny actions.

The runtime should expire pending requests if no response arrives.

## Open Questions

- Should v1 implement only local popup approval and leave SMS/external review as provider interfaces?
- Should shell be excluded until command parsing exists?
- Should grants be persisted across app restarts, or should v1 grants be session-only?
- Should external LLM risk review be advisory only forever, or can it approve low-risk read-only requests later?
- How should approval decisions be represented in context: visible tool denial result only, or full permission metadata?

## Current Lean

- V1 should support a general grant-provider interface but ship only local popup and test providers.
- V1 grants should be `once`, `turn`, or `session`; avoid project-lifetime grants until trust behavior is proven.
- File write/edit should be allowed inside the canonical session current directory by default.
- File write/edit outside the canonical session current directory should require elevated permission.
- Explicit absolute outside-workspace paths should require elevated permission scoped to the exact resolved path and tool call.
- Shell should remain out of scope until command parsing, highest-risk aggregation, and always-confirm rules are designed.
- External LLM risk review should be advisory and able to increase friction, not reduce it.
