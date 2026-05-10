import Foundation

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
      $0.draft = plan
      $0.errorMessage = nil
    }
  }

  func sendPlanningMessage() {
    guard let note = state.planningInteraction?.trimmedNote, !note.isEmpty else { return }
    updateInteraction {
      $0.entries.append(WorkflowInteractionEntry(source: .user, text: note))
      $0.note = ""
      $0.errorMessage = nil
    }
  }

  func submitPlanningDraftPlan() {
    guard let project = state.selectedProject,
          var interaction = state.planningInteraction
    else { return }
    let submittedPlan = interaction.trimmedDraft
    guard !submittedPlan.isEmpty else {
      updateInteraction { $0.errorMessage = "Add a draft plan before submitting." }
      return
    }
    guard interaction.submittedMessage == nil else { return }

    let message = makeSubmittedPlanMessage(from: interaction, content: submittedPlan)
    interaction.submittedMessage = message
    let progress = PlanningReviewWorkflowRunner().submitPlan(project: project, message: message)
    applySubmittedPlan(interaction: interaction, message: message, plan: submittedPlan, progress: progress)
  }

  private func updateInteraction(_ mutate: (inout WorkflowInteractionState) -> Void) {
    update {
      guard var interaction = $0.planningInteraction else { return }
      mutate(&interaction)
      $0.planningInteraction = interaction
    }
  }

  private func makeSubmittedPlanMessage(
    from interaction: WorkflowInteractionState,
    content: String
  ) -> InteractiveStepMessage {
    InteractiveStepMessage(
      kind: .submittedArtifact,
      producerStepID: interaction.stepID,
      payload: .artifact(
        InteractiveStepArtifact(contentType: "text/markdown; artifact=plan", content: content)
      ),
      summary: submittedPlanSummary(from: content)
    )
  }

  private func applySubmittedPlan(
    interaction: WorkflowInteractionState,
    message: InteractiveStepMessage,
    plan: String,
    progress: WorkflowRunProgress
  ) {
    update {
      $0.planningInteraction = interaction
      $0.stepRecords = progress.stepRecords
      $0.timelineOutput = progress.timeline
      $0.output = """
        == Planning Review Workflow ==
        Submitted plan message: \(message.id)

        \(plan)
        """
      $0.isRunning = false
      $0.activeWorkflowID = nil
      $0.lastRunWorkflowID = PlanningReviewWorkflowRunner.id
      $0.lastRunSucceeded = true
      $0.statusMessage = "Submitted plan is ready for automated review cycles."
    }
  }

  private func submittedPlanSummary(from plan: String) -> String {
    let firstLine = plan
      .split(separator: "\n")
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .first { !$0.isEmpty && !$0.hasPrefix("#") }
    return firstLine.map { "Submitted plan: \($0)" } ?? "Submitted plan message"
  }
}
