import Foundation

extension WorkflowExecutor {
  func upsertReviewerStep(
    _ reviewer: WorkflowReviewerSlot,
    cycleInfo: WorkflowReviewCycleInfo,
    run: ReviewerRun,
    prompt: String,
    outcome: WorkflowStepRecordCycleOutcome? = nil,
    runState: WorkflowRunState
  ) async {
    let status: WorkflowStepRecordStatus
    let summary: String
    if run.result.exitCode != 0 {
      status = .failed
      summary = "\(reviewer.name) failed with exit code \(run.result.exitCode)."
    } else if run.finding.hasBlockingIssue {
      status = .needsFix
      summary = "\(reviewer.name) returned blocking findings."
    } else {
      status = .succeeded
      summary = "\(reviewer.name) passed review."
    }
    await upsertReviewerStep(
      reviewer,
      cycleInfo: cycleInfo,
      status: status,
      summary: summary,
      prompt: prompt,
      output: run.result.output,
      outcome: outcome,
      runState: runState
    )
  }

  func upsertReviewerStep(
    _ reviewer: WorkflowReviewerSlot,
    cycleInfo: WorkflowReviewCycleInfo,
    status: WorkflowStepRecordStatus,
    summary: String,
    prompt: String,
    output: String?,
    outcome: WorkflowStepRecordCycleOutcome?,
    runState: WorkflowRunState
  ) async {
    await runState.upsertStep(
      id: reviewer.stepID(cycle: cycleInfo.cycle),
      title: "Step 3.\(reviewer.number) - \(reviewer.name)",
      status: status,
      summary: summary,
      inputPreview: prompt,
      outputPreview: output,
      sortOrder: cycleInfo.sortBase + reviewer.sortOffset,
      hierarchy: reviewer.hierarchy(cycleInfo: cycleInfo, outcome: outcome, runState: runState),
      timeoutSeconds: Self.reviewerTimeoutSeconds
    )
  }

  func upsertFeedbackStep(
    cycleInfo: WorkflowReviewCycleInfo,
    input: String,
    feedback: String,
    outcome: WorkflowStepRecordCycleOutcome?,
    summary: String,
    runState: WorkflowRunState
  ) async {
    await runState.upsertStep(
      id: "step-4-feedback-\(cycleInfo.cycle)",
      title: "Step 4 - Feedback relay",
      status: .succeeded,
      summary: summary,
      inputPreview: input,
      outputPreview: feedback,
      sortOrder: cycleInfo.sortBase + 40,
      hierarchy: runState.cycleHierarchy(cycle: cycleInfo.cycle, phaseOrder: 40, outcome: outcome)
    )
  }

  func emitReviewerCompletion(
    _ reviewer: WorkflowReviewerSlot,
    run: ReviewerRun,
    runState: WorkflowRunState
  ) async {
    await runState.emit(
      "Step 3.\(reviewer.number) - \(reviewer.name) finished with exit code \(run.result.exitCode)."
    )
  }
}

func messageBlock(title: String, body: String) -> String {
  """
  ## \(title)

  \(body)
  """
}
