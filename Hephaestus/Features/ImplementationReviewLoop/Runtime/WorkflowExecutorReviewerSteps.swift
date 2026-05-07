import Foundation

extension WorkflowExecutor {
  func prepareReviewerStep(
    _ reviewer: WorkflowReviewerSlot,
    prompt: String,
    cycleInfo: WorkflowReviewCycleInfo,
    runState: WorkflowRunState,
    debugLog: WorkflowDebugLog
  ) async {
    await runState.emit("Step 3.\(reviewer.number) - \(reviewer.name) started.")
    await debugLog.append(prompt, to: reviewer.promptLogName(cycle: cycleInfo.cycle))
    await debugLog.append(messageBlock(title: "Message to \(reviewer.name)", body: prompt))
    await upsertReviewerStep(
      reviewer,
      cycleInfo: cycleInfo,
      status: .inProgress,
      summary: "\(reviewer.name) is checking the implementation.",
      prompt: prompt,
      output: nil,
      outcome: .running,
      runState: runState
    )
  }

  func recordReviewerResults(
    _ reviewerPair: ReviewerRunPair,
    prompts: ReviewerPromptPair,
    cycleInfo: WorkflowReviewCycleInfo,
    runState: WorkflowRunState,
    debugLog: WorkflowDebugLog,
    log: inout String
  ) async {
    await emitReviewerCompletion(.a, run: reviewerPair.a, runState: runState)
    await emitReviewerCompletion(.b, run: reviewerPair.b, runState: runState)
    log += reviewerPair.transcriptBlock + "\n"
    await debugLog.append(reviewerPair.transcriptBlock + "\n")
    await debugLog.append(
      reviewerPair.a.transcriptBlock,
      to: WorkflowReviewerSlot.a.outputLogName(cycle: cycleInfo.cycle)
    )
    await debugLog.append(
      reviewerPair.b.transcriptBlock,
      to: WorkflowReviewerSlot.b.outputLogName(cycle: cycleInfo.cycle)
    )
    await upsertReviewerStep(
      .a, cycleInfo: cycleInfo, run: reviewerPair.a, prompt: prompts.a, runState: runState)
    await upsertReviewerStep(
      .b, cycleInfo: cycleInfo, run: reviewerPair.b, prompt: prompts.b, runState: runState)
  }

  func finishSuccessfulReview(
    _ reviewerPair: ReviewerRunPair,
    prompts: ReviewerPromptPair,
    cycleInfo: WorkflowReviewCycleInfo,
    runState: WorkflowRunState,
    log: String
  ) async -> WorkflowCycleContinuation {
    await runState.emit("Step 4 - Workflow completed: build passed and both reviewers passed.")
    await upsertReviewerStep(
      .a, cycleInfo: cycleInfo, run: reviewerPair.a, prompt: prompts.a, outcome: .succeeded,
      runState: runState)
    await upsertReviewerStep(
      .b, cycleInfo: cycleInfo, run: reviewerPair.b, prompt: prompts.b, outcome: .succeeded,
      runState: runState)
    return .finish(
      await runState.result(
        exitCode: 0,
        output: log
          + "\nWorkflow passed: build succeeded and both reviewers passed or had no P1/P2 findings.\n"
      ))
  }

  func relayReviewFeedback(
    _ blockingFindings: [ReviewFinding],
    cycleInfo: WorkflowReviewCycleInfo,
    request: ImplementationReviewWorkflowRequest,
    runState: WorkflowRunState,
    debugLog: WorkflowDebugLog,
    log: String,
    latestFeedback: inout String
  ) async -> WorkflowCycleContinuation {
    latestFeedback = makeReviewerFeedback(findings: blockingFindings)
    await debugLog.append(latestFeedback, to: "step-4-feedback-\(cycleInfo.cycle).md")
    await debugLog.append(
      messageBlock(
        title: "Message to Implementer: reviewer feedback for next cycle", body: latestFeedback)
    )
    await runState.emit("Step 4 - Blocking review feedback returned to implementer.")
    await upsertFeedbackStep(
      cycleInfo: cycleInfo,
      input: blockingFindings.map(\.transcript).joined(separator: "\n\n"),
      feedback: latestFeedback,
      outcome: cycleInfo.cycle == request.maxReviewCycles ? .terminalFailed : .needsFix,
      summary: "Blocking reviewer feedback was prepared for the implementer.",
      runState: runState
    )
    guard cycleInfo.cycle == request.maxReviewCycles else { return .continueLoop }
    await runState.emit(
      "Step 4 - Loop stopped: max review cycles reached with unresolved findings.")
    return .finish(
      await runState.result(
        exitCode: 1, output: log + "\nMax review cycles reached with unresolved P1/P2 findings.\n")
    )
  }
}
