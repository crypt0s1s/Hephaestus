import Foundation

struct WorkflowExecutor {
  static let reviewerTimeoutSeconds: TimeInterval = 90
  let codexStep: CodexAgentStep
  let shellStep: ShellValidationStep
  let planValidator: PlanFileValidator

  init(
    codexStep: CodexAgentStep,
    shellStep: ShellValidationStep,
    planValidator: PlanFileValidator = PlanFileValidator()
  ) {
    self.codexStep = codexStep
    self.shellStep = shellStep
    self.planValidator = planValidator
  }

  func runCodexStep(_ invocation: CodexAgentInvocation) async -> ProcessResult {
    await codexStep.run(invocation)
  }

  func runImplementationReviewLoop(
    project: WorkflowProject,
    request: ImplementationReviewWorkflowRequest,
    progress: WorkflowProgressHandler? = nil
  ) async -> ProcessResult {
    let debugLog = WorkflowDebugLog(projectName: project.name)
    let runState = WorkflowRunState(debugLog: debugLog, progress: progress)
    await debugLog.append(
      """
      == Implementation Review Loop Debug Log ==
      Project: \(project.path)
      Requested plan: \(request.planRelativePath)
      Build command: \(request.normalizedBuildCommand)

      """)

    let setup = await validatePlanAndPrepareRun(
      project: project,
      request: request,
      runState: runState,
      debugLog: debugLog
    )
    guard case .validated(let plan, var log) = setup else {
      if case .failed(let result) = setup {
        return result
      }
      return await runState.result(exitCode: 1, output: "Workflow setup failed.")
    }
    return await runValidatedReviewLoop(
      project: project,
      plan: plan,
      request: request,
      runState: runState,
      debugLog: debugLog,
      log: &log
    )
  }

}
