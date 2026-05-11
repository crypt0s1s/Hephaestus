import Foundation

private enum PlanningInteractionError: LocalizedError {
  case plannerFailed(String)

  var errorDescription: String? {
    switch self {
    case .plannerFailed(let output):
      return output.isEmpty ? "Planner backend failed." : output
    }
  }
}

@MainActor
extension WorkflowRunnerModel {
  func updatePlanningDraftMessage(_ message: String) {
    updateInteraction {
      $0.note = message
      $0.errorMessage = nil
    }
  }

  func updatePlanningDraftPlan(_ plan: String) {
    updateInteraction {
      if $0.draft != plan {
        $0.draftProvenance = plan.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
          ? .empty
          : .userEdited
      }
      $0.draft = plan
      $0.errorMessage = nil
    }
  }

  func sendPlanningMessage() async {
    guard let project = state.selectedProject,
          let interaction = state.planningInteraction,
          !interaction.trimmedNote.isEmpty,
          interaction.phase == .idle
    else { return }
    let note = interaction.trimmedNote
    updateInteraction {
      $0.entries.append(WorkflowInteractionEntry(source: .user, text: note))
      $0.note = ""
      $0.phase = .sending
      $0.errorMessage = nil
    }

    do {
      let session = try await planningSession(for: interaction, project: project)
      updateInteraction { $0.backendSession = session }
      let assistantEntryID = appendStreamingPlannerEntry()
      let response = try await sendPlannerTurn(
        note: note,
        session: session,
        assistantEntryID: assistantEntryID
      )
      applyCompletedPlannerTurn(response)
    } catch {
      updateInteraction {
        $0.phase = .idle
        $0.errorMessage = "Planner turn failed: \(error.localizedDescription)"
      }
    }
  }

  func submitPlanningDraftPlan() async {
    guard let project = state.selectedProject,
          let interaction = state.planningInteraction,
          interaction.phase == .idle
    else { return }
    let submittedPlan = interaction.trimmedDraft
    guard !submittedPlan.isEmpty else {
      updateInteraction { $0.errorMessage = "Add a draft plan before submitting." }
      return
    }
    guard interaction.draftProvenance == .userEdited else {
      updateInteraction {
        $0.errorMessage = "Edit the generated draft before submitting it for review."
      }
      return
    }
    guard interaction.submittedOutput == nil else { return }

    updateInteraction {
      $0.phase = .materializing
      $0.errorMessage = nil
      $0.entries.append(
        WorkflowInteractionEntry(
          source: .system,
          text: "Submitting the draft plan and preparing automated review cycles."
        )
      )
    }

    do {
      try await submitValidatedPlan(
        project: project,
        interaction: interaction,
        submittedPlan: submittedPlan
      )
    } catch {
      handlePlanningSubmissionFailure(error)
    }
  }

  func acceptPlanningReview() {
    guard let interaction = state.planningInteraction,
          interaction.canResolveCompletedOutput
    else { return }
    update {
      $0.isRunning = false
      $0.activeWorkflowID = nil
      $0.lastRunWorkflowID = PlanningReviewWorkflowRunner.id
      $0.lastRunSucceeded = true
      $0.statusMessage = "Planning review workflow accepted."
      $0.planningInteraction?.phase = .accepted
      $0.planningInteraction?.entries.append(
        WorkflowInteractionEntry(
          source: .system,
          text: "Accepted the submitted plan and completed the workflow."
        )
      )
    }
  }

  func continuePlanningReview() {
    guard let project = state.selectedProject,
          let interaction = state.planningInteraction,
          interaction.canResolveCompletedOutput
    else { return }
    updateInteraction {
      $0.submittedOutput = nil
      $0.draftProvenance = $0.trimmedDraft.isEmpty ? .empty : .userEdited
      $0.phase = .idle
      $0.errorMessage = nil
      $0.entries.append(
        WorkflowInteractionEntry(
          source: .system,
          text: "Reopened planning. Update the draft and submit it again when it is ready."
        )
      )
    }
    update {
      $0.isRunning = true
      $0.activeWorkflowID = PlanningReviewWorkflowRunner.id
      $0.lastRunSucceeded = nil
      $0.stepRecords = planningReviewServices.makeWorkflowRunner()
        .startInteractivePlanning(project: project).stepRecords
      $0.timelineOutput = """
        Planning Review Workflow reopened.
        Interactive planning phase is waiting for updated input.
        """
      $0.statusMessage = "Planning reopened. Submit another draft to restart review cycles."
    }
  }

  func requestAnotherPlanningReviewCycle() async {
    guard let project = state.selectedProject,
          let interaction = state.planningInteraction,
          let output = interaction.submittedOutput,
          interaction.phase == .completed
    else { return }
    updateInteraction {
      $0.phase = .reviewing
      $0.errorMessage = nil
      $0.entries.append(
        WorkflowInteractionEntry(
          source: .system,
          text: "Requested another automated review cycle for the submitted plan."
        )
      )
    }
    let runner = planningReviewServices.makeWorkflowRunner()
    var run = PlanningReviewPrototypeAutomationRun(
      timeline: state.timelineOutput.isEmpty
        ? planningReviewServices.automation.startedTimeline
        : state.timelineOutput,
      records: state.stepRecords.filter { $0.id != "planning-review-interactive-user-review" },
      planPath: output.artifact.projectRelativePath ?? "the submitted plan artifact"
    )
    await runner.runPlanningReviewPrototypeAutomationCycle(
      cycle: nextPlanningReviewCycleNumber(),
      project: project,
      submittedOutput: output,
      run: &run,
      progress: { [weak model = self] progress in
        await model?.applyPlanningReviewProgress(progress)
      }
    )
    applyPlanningReviewResult(runner.finishPlanningReviewPrototypeAutomationRun(run))
  }

  private func submitValidatedPlan(
    project: WorkflowProject,
    interaction: WorkflowInteractionState,
    submittedPlan: String
  ) async throws {
    let artifact = try planningReviewServices.planArtifactMaterializer.materializePlanArtifact(
      project: project,
      sessionID: interaction.sessionID,
      content: submittedPlan
    )
    let output = makeSubmittedPlanOutput(from: interaction, artifact: artifact)
    var submittedInteraction = interaction
    submittedInteraction.submittedOutput = output
    submittedInteraction.phase = .reviewing
    let artifactPath = artifact.projectRelativePath ?? "the project"
    submittedInteraction.entries.append(
      WorkflowInteractionEntry(
        source: .system,
        text: "Plan artifact was written to \(artifactPath). Automated review cycles are running."
      )
    )
    let runner = planningReviewServices.makeWorkflowRunner()
    let progress = runner.submitPlan(project: project, output: output)
    applySubmittedPlan(
      interaction: submittedInteraction,
      output: output,
      plan: submittedPlan,
      progress: progress
    )
    let result = await runner.runAutomatedReviewCycles(
      project: project,
      submittedOutput: output,
      progress: { [weak model = self] progress in
        await model?.applyPlanningReviewProgress(progress)
      }
    )
    applyPlanningReviewResult(result)
  }

  private func handlePlanningSubmissionFailure(_ error: Error) {
    updateInteraction {
      $0.phase = .idle
      $0.errorMessage = "Plan submission failed: \(error.localizedDescription)"
    }
  }

  private func planningSession(
    for interaction: WorkflowInteractionState,
    project: WorkflowProject
  ) async throws -> BackendSession {
    if let session = interaction.backendSession {
      return try await planningReviewServices.backendAdapter.resumeSession(
        ResumeSessionRequest(session: session))
    }
    return try await planningReviewServices.backendAdapter.startSession(
      StartSessionRequest(project: project, title: "Planning Review")
    )
  }

  private func sendPlannerTurn(
    note: String,
    session: BackendSession,
    assistantEntryID: WorkflowInteractionEntry.ID
  ) async throws -> String {
    let stream = try await planningReviewServices.backendAdapter.startTurn(
      StartTurnRequest(
        session: session,
        prompt: PlanningInteractionPrototypePrompts.plannerPrompt(for: note),
        timeoutSeconds: 180,
        sandboxMode: "read-only"
      )
    )
    var response = ""
    for try await event in stream {
      switch event {
      case .outputChunk(let chunk):
        response += chunk
        updateStreamingPlannerEntry(id: assistantEntryID, text: response)
      case .turnCompleted(let result):
        let completedResponse = response.isEmpty ? result.output : response
        updateStreamingPlannerEntry(id: assistantEntryID, text: completedResponse)
        return completedResponse
      case .turnFailed(let result):
        throw PlanningInteractionError.plannerFailed(result.output)
      case .sessionStarted,
           .turnStarted,
           .approvalRequested,
           .turnCancelled:
        continue
      }
    }
    return response
  }

  private func appendStreamingPlannerEntry() -> WorkflowInteractionEntry.ID {
    let entry = WorkflowInteractionEntry(source: .assistant, text: "Thinking...")
    updateInteraction {
      $0.entries.append(entry)
    }
    return entry.id
  }

  private func updateStreamingPlannerEntry(id: WorkflowInteractionEntry.ID, text: String) {
    updateInteraction {
      guard let index = $0.entries.firstIndex(where: { $0.id == id }) else { return }
      $0.entries[index].text = text.isEmpty ? "Thinking..." : text
    }
  }

  func updateInteraction(_ mutate: (inout WorkflowInteractionState) -> Void) {
    update {
      guard var interaction = $0.planningInteraction else { return }
      mutate(&interaction)
      $0.planningInteraction = interaction
    }
  }

  private func makeSubmittedPlanOutput(
    from interaction: WorkflowInteractionState,
    artifact: InteractiveStepArtifact
  ) -> InteractiveStepOutput {
    InteractiveStepOutput(
      producerStepID: interaction.stepID,
      artifact: artifact,
      summary: PlanningInteractionPrototypePrompts.submittedPlanSummary(from: artifact.content)
    )
  }

  private func applySubmittedPlan(
    interaction: WorkflowInteractionState,
    output: InteractiveStepOutput,
    plan: String,
    progress: WorkflowRunProgress
  ) {
    update {
      $0.planningInteraction = interaction
      $0.stepRecords = progress.stepRecords
      $0.timelineOutput = progress.timeline
      $0.output = """
        == Planning Review Workflow ==
        Submitted plan artifact: \(output.id)
        Path: \(output.artifact.projectRelativePath ?? "not exported")

        \(plan)
        """
      $0.isRunning = true
      $0.activeWorkflowID = PlanningReviewWorkflowRunner.id
      $0.lastRunWorkflowID = PlanningReviewWorkflowRunner.id
      $0.lastRunSucceeded = nil
      $0.statusMessage = "Submitted plan is validated and ready for automated review cycles."
    }
  }

  private func applyPlanningReviewProgress(_ progress: WorkflowRunProgress) {
    update {
      $0.stepRecords = progress.stepRecords
      $0.timelineOutput = progress.timeline
      $0.debugLogURL = progress.debugLogURL
      $0.statusMessage = "Automated planning review cycles are running."
    }
  }

  private func applyPlanningReviewResult(_ result: ProcessResult) {
    update {
      $0.output = result.output
      $0.timelineOutput = result.timeline.isEmpty ? result.output : result.timeline
      $0.stepRecords = result.stepRecords
      $0.debugLogURL = result.debugLogURL
      $0.isRunning = result.exitCode == 0
      $0.activeWorkflowID = result.exitCode == 0 ? PlanningReviewWorkflowRunner.id : nil
      $0.lastRunWorkflowID = PlanningReviewWorkflowRunner.id
      $0.lastRunSucceeded = result.exitCode == 0 ? nil : false
      $0.statusMessage = result.exitCode == 0
        ? "Automated review cycles finished. Review the plan before accepting it."
        : "Automated review cycles failed. Inspect the run updates before retrying."
      $0.planningInteraction?.phase = result.exitCode == 0 ? .completed : .idle
      if result.exitCode != 0 {
        $0.planningInteraction?.submittedOutput = nil
        $0.planningInteraction?.errorMessage =
          "Automated review failed. Update the draft or submit it again after inspecting the run."
      }
    }
  }

  private func nextPlanningReviewCycleNumber() -> Int {
    let existingCycles = state.stepRecords.compactMap { record -> Int? in
      guard record.id.hasPrefix("planning-review-reviewer-") else { return nil }
      let parts = record.id.split(separator: "-")
      return parts.dropFirst(3).first.flatMap { Int($0) }
    }
    return (existingCycles.max() ?? 0) + 1
  }

}
