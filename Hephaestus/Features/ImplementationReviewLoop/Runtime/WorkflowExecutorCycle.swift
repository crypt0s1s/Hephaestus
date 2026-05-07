import Foundation

extension WorkflowExecutor {
  func runValidatedReviewLoop(
    project: WorkflowProject,
    plan: PlanDocument,
    request: ImplementationReviewWorkflowRequest,
    runState: WorkflowRunState,
    debugLog: WorkflowDebugLog,
    log: inout String
  ) async -> ProcessResult {
    var latestFeedback = ""
    for cycle in 0...request.maxReviewCycles {
      let cycleInfo = WorkflowReviewCycleInfo(cycle: cycle)
      switch await runImplementationCycle(
        cycleInfo: cycleInfo,
        project: project,
        plan: plan,
        request: request,
        runState: runState,
        debugLog: debugLog,
        log: &log,
        latestFeedback: &latestFeedback
      ) {
      case .continueLoop:
        continue
      case .finish(let result):
        return result
      }
    }

    await runState.emit("Step 4 - Workflow ended before reviewers passed.")
    return await runState.result(
      exitCode: 1,
      output: log + "\nWorkflow ended before reviewers passed.\n"
    )
  }

  func runImplementationCycle(
    cycleInfo: WorkflowReviewCycleInfo,
    project: WorkflowProject,
    plan: PlanDocument,
    request: ImplementationReviewWorkflowRequest,
    runState: WorkflowRunState,
    debugLog: WorkflowDebugLog,
    log: inout String,
    latestFeedback: inout String
  ) async -> WorkflowCycleContinuation {
    let implementerPrompt =
      cycleInfo.isInitialImplementation
      ? makeInitialImplementerPrompt(project: project, plan: plan)
      : makeFixPrompt(project: project, plan: plan, feedback: latestFeedback)

    if let failure = await runImplementerStep(
      cycleInfo: cycleInfo,
      project: project,
      prompt: implementerPrompt,
      runState: runState,
      debugLog: debugLog,
      log: &log
    ) {
      return .finish(failure)
    }

    switch await runBuildStep(
      cycleInfo: cycleInfo,
      project: project,
      request: request,
      runState: runState,
      debugLog: debugLog,
      log: &log,
      latestFeedback: &latestFeedback
    ) {
    case .passed:
      return await runReviewStep(
        cycleInfo: cycleInfo,
        project: project,
        plan: plan,
        request: request,
        runState: runState,
        debugLog: debugLog,
        log: &log,
        latestFeedback: &latestFeedback
      )
    case .needsFix:
      return .continueLoop
    case .failed(let result):
      return .finish(result)
    }
  }

  func runImplementerStep(
    cycleInfo: WorkflowReviewCycleInfo,
    project: WorkflowProject,
    prompt: String,
    runState: WorkflowRunState,
    debugLog: WorkflowDebugLog,
    log: inout String
  ) async -> ProcessResult? {
    await prepareImplementerStep(
      cycleInfo: cycleInfo, prompt: prompt, runState: runState, debugLog: debugLog)

    let result = await codexStep.run(
      cycleInfo.implementerInvocation(project: project, prompt: prompt))
    log += result.output + "\n"
    await debugLog.append(result.output + "\n")
    await debugLog.append(result.output, to: "\(cycleInfo.implementerStepID)-output.log")
    guard result.exitCode == 0 else {
      await runState.emit("Step 1 - Implementer failed with exit code \(result.exitCode).")
      await upsertImplementerStep(
        cycleInfo: cycleInfo,
        status: .failed,
        summary: "Implementer failed with exit code \(result.exitCode).",
        prompt: prompt,
        output: result.output,
        outcome: .terminalFailed,
        runState: runState
      )
      return await runState.result(exitCode: result.exitCode, output: log)
    }

    await runState.emit("Step 1 - Implementer finished \(cycleInfo.label).")
    await upsertImplementerStep(
      cycleInfo: cycleInfo,
      status: .succeeded,
      summary: "Implementer finished \(cycleInfo.label).",
      prompt: prompt,
      output: result.output,
      outcome: nil,
      runState: runState
    )
    return nil
  }

  func prepareImplementerStep(
    cycleInfo: WorkflowReviewCycleInfo,
    prompt: String,
    runState: WorkflowRunState,
    debugLog: WorkflowDebugLog
  ) async {
    await runState.emit("Step 1 - Implementer started \(cycleInfo.label).")
    await debugLog.append(prompt, to: "\(cycleInfo.implementerStepID)-prompt.md")
    await debugLog.append(
      messageBlock(title: "Message to Implementer: \(cycleInfo.label)", body: prompt))
    await upsertImplementerStep(
      cycleInfo: cycleInfo,
      status: .inProgress,
      summary: "Implementer is running \(cycleInfo.label).",
      prompt: prompt,
      output: nil,
      outcome: .running,
      runState: runState
    )
  }

  func runBuildStep(
    cycleInfo: WorkflowReviewCycleInfo,
    project: WorkflowProject,
    request: ImplementationReviewWorkflowRequest,
    runState: WorkflowRunState,
    debugLog: WorkflowDebugLog,
    log: inout String,
    latestFeedback: inout String
  ) async -> WorkflowBuildStepResult {
    await runState.emit("Step 2 - Build started after \(cycleInfo.label).")
    await upsertBuildStep(
      cycleInfo: cycleInfo,
      request: request,
      status: .inProgress,
      summary: "Running build after \(cycleInfo.label).",
      output: nil,
      outcome: .running,
      runState: runState
    )

    let result = await shellStep.run(cycleInfo.buildInvocation(project: project, request: request))
    log += result.output + "\n"
    await debugLog.append(result.output + "\n")
    await debugLog.append(result.output, to: "\(cycleInfo.buildStepID)-output.log")
    guard result.exitCode == 0 else {
      return await handleBuildFailure(
        result: result,
        cycleInfo: cycleInfo,
        request: request,
        runState: runState,
        log: log,
        latestFeedback: &latestFeedback
      )
    }

    await runState.emit("Step 2 - Build passed after \(cycleInfo.label).")
    await upsertBuildStep(
      cycleInfo: cycleInfo,
      request: request,
      status: .succeeded,
      summary: "Build passed after \(cycleInfo.label).",
      output: result.output,
      outcome: nil,
      runState: runState
    )
    return .passed
  }

  func runReviewStep(
    cycleInfo: WorkflowReviewCycleInfo,
    project: WorkflowProject,
    plan: PlanDocument,
    request: ImplementationReviewWorkflowRequest,
    runState: WorkflowRunState,
    debugLog: WorkflowDebugLog,
    log: inout String,
    latestFeedback: inout String
  ) async -> WorkflowCycleContinuation {
    let prompts = ReviewerPromptPair(
      a: makeReviewerPrompt(name: "Reviewer A", project: project, plan: plan),
      b: makeReviewerPrompt(name: "Reviewer B", project: project, plan: plan)
    )
    await prepareReviewerStep(
      .a, prompt: prompts.a, cycleInfo: cycleInfo, runState: runState, debugLog: debugLog)
    async let reviewerARun = runReviewer(name: "Reviewer A", project: project, prompt: prompts.a)
    await prepareReviewerStep(
      .b, prompt: prompts.b, cycleInfo: cycleInfo, runState: runState, debugLog: debugLog)
    async let reviewerBRun = runReviewer(name: "Reviewer B", project: project, prompt: prompts.b)
    let reviewerPair = await ReviewerRunPair(a: reviewerARun, b: reviewerBRun)

    await recordReviewerResults(
      reviewerPair,
      prompts: prompts,
      cycleInfo: cycleInfo,
      runState: runState,
      debugLog: debugLog,
      log: &log
    )

    let blockingFindings = reviewerPair.findings.filter(\.hasBlockingIssue)
    if blockingFindings.isEmpty {
      return await finishSuccessfulReview(
        reviewerPair,
        prompts: prompts,
        cycleInfo: cycleInfo,
        runState: runState,
        log: log
      )
    }

    return await relayReviewFeedback(
      blockingFindings,
      cycleInfo: cycleInfo,
      request: request,
      runState: runState,
      debugLog: debugLog,
      log: log,
      latestFeedback: &latestFeedback
    )
  }

  func runReviewer(name: String, project: WorkflowProject, prompt: String) async
    -> ReviewerRun {
    let result = await codexStep.run(
      CodexAgentInvocation(
        name: name,
        project: project,
        prompt: prompt,
        timeoutSeconds: Self.reviewerTimeoutSeconds
      ))
    let transcript =
      result.exitCode == 0
      ? result.output
      : "P1: \(name) failed to run with exit code \(result.exitCode).\n\(result.output)"
    return ReviewerRun(
      name: name,
      finding: ReviewFinding(reviewerName: name, transcript: transcript),
      result: result
    )
  }

  func upsertImplementerStep(
    cycleInfo: WorkflowReviewCycleInfo,
    status: WorkflowStepRecordStatus,
    summary: String,
    prompt: String,
    output: String?,
    outcome: WorkflowStepRecordCycleOutcome?,
    runState: WorkflowRunState
  ) async {
    await runState.upsertStep(
      id: cycleInfo.implementerStepID,
      title: "Step 1 - Implementer",
      status: status,
      summary: summary,
      inputPreview: prompt,
      outputPreview: output,
      sortOrder: cycleInfo.sortBase + 10,
      hierarchy: runState.cycleHierarchy(cycle: cycleInfo.cycle, phaseOrder: 10, outcome: outcome),
      timeoutSeconds: 300
    )
  }

  func upsertBuildStep(
    cycleInfo: WorkflowReviewCycleInfo,
    request: ImplementationReviewWorkflowRequest,
    status: WorkflowStepRecordStatus,
    summary: String,
    output: String?,
    outcome: WorkflowStepRecordCycleOutcome?,
    runState: WorkflowRunState
  ) async {
    await runState.upsertStep(
      id: cycleInfo.buildStepID,
      title: "Step 2 - Build",
      status: status,
      summary: summary,
      inputPreview: request.normalizedBuildCommand,
      outputPreview: output,
      sortOrder: cycleInfo.sortBase + 20,
      hierarchy: runState.cycleHierarchy(cycle: cycleInfo.cycle, phaseOrder: 20, outcome: outcome),
      timeoutSeconds: 600
    )
  }

  func handleBuildFailure(
    result: ProcessResult,
    cycleInfo: WorkflowReviewCycleInfo,
    request: ImplementationReviewWorkflowRequest,
    runState: WorkflowRunState,
    log: String,
    latestFeedback: inout String
  ) async -> WorkflowBuildStepResult {
    await runState.emit(
      "Step 2 - Build failed with exit code \(result.exitCode); feedback returned to implementer."
    )
    await upsertBuildStep(
      cycleInfo: cycleInfo,
      request: request,
      status: .failed,
      summary: "Build failed with exit code \(result.exitCode).",
      output: result.output,
      outcome: cycleInfo.cycle == request.maxReviewCycles ? .terminalFailed : nil,
      runState: runState
    )
    latestFeedback = cycleInfo.buildFailureFeedback(output: result.output)
    await upsertFeedbackStep(
      cycleInfo: cycleInfo,
      input: result.output,
      feedback: latestFeedback,
      outcome: cycleInfo.cycle == request.maxReviewCycles ? .terminalFailed : .needsFix,
      summary: "Build failure feedback was prepared for the implementer.",
      runState: runState
    )
    guard cycleInfo.cycle == request.maxReviewCycles else {
      return .needsFix
    }
    await runState.emit("Step 4 - Loop stopped: max review cycles reached after build failure.")
    return .failed(
      await runState.result(
        exitCode: result.exitCode,
        output: log + "\nMax review cycles reached after build failure.\n"
      ))
  }

}
