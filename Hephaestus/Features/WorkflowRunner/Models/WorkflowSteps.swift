import Foundation

struct CodexAgentInvocation: Equatable {
  let name: String
  let project: WorkflowProject
  let prompt: String
  let timeoutSeconds: TimeInterval?

  init(name: String, project: WorkflowProject, prompt: String, timeoutSeconds: TimeInterval? = 300) {
    self.name = name
    self.project = project
    self.prompt = prompt
    self.timeoutSeconds = timeoutSeconds
  }
}

struct CodexAgentStep {
  private let processRunner: WorkflowProcessRunning

  init(processRunner: WorkflowProcessRunning) {
    self.processRunner = processRunner
  }

  func run(_ invocation: CodexAgentInvocation) async -> ProcessResult {
    let result = await processRunner.run(
      executable: Self.codexExecutableURL,
      arguments: [
        "exec",
        "--cd", invocation.project.path,
        "--skip-git-repo-check",
        "--sandbox", "workspace-write",
        invocation.prompt,
      ],
      currentDirectoryURL: nil,
      timeoutSeconds: invocation.timeoutSeconds
    )
    let timeoutNote =
      result.timedOut
      ? """

        Timed out after \(Int(invocation.timeoutSeconds ?? 0)) seconds. \
        Treat this as a failed agent step and inspect the debug log.

        """
      : ""
    return ProcessResult(
      exitCode: result.exitCode,
      output: """
        == \(invocation.name) ==
        \(result.output)
        \(timeoutNote)
        """
    )
  }

  private static var codexExecutableURL: URL {
    let appBundledCodex = URL(fileURLWithPath: "/Applications/Codex.app/Contents/Resources/codex")
    if FileManager.default.isExecutableFile(atPath: appBundledCodex.path) {
      return appBundledCodex
    }
    return URL(fileURLWithPath: "/usr/bin/env")
  }
}

struct ShellValidationInvocation: Equatable {
  let name: String
  let project: WorkflowProject
  let command: String
  let timeoutSeconds: TimeInterval?

  init(name: String, project: WorkflowProject, command: String, timeoutSeconds: TimeInterval? = 600) {
    self.name = name
    self.project = project
    self.command = command
    self.timeoutSeconds = timeoutSeconds
  }
}

struct ShellValidationStep {
  private let processRunner: WorkflowProcessRunning

  init(processRunner: WorkflowProcessRunning) {
    self.processRunner = processRunner
  }

  func run(_ invocation: ShellValidationInvocation) async -> ProcessResult {
    let result = await processRunner.run(
      executable: URL(fileURLWithPath: "/bin/zsh"),
      arguments: ["-lc", invocation.command],
      currentDirectoryURL: URL(fileURLWithPath: invocation.project.path, isDirectory: true),
      timeoutSeconds: invocation.timeoutSeconds
    )
    let timeoutNote =
      result.timedOut
      ? "\nTimed out after \(Int(invocation.timeoutSeconds ?? 0)) seconds.\n"
      : ""
    return ProcessResult(
      exitCode: result.exitCode,
      output: """
        == \(invocation.name) ==
        Command: \(invocation.command)
        Exit code: \(result.exitCode)
        \(result.output)
        \(timeoutNote)
        """
    )
  }
}
