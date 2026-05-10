import Foundation

struct PlanningReviewWorkflowRunner: BuiltInWorkflow {
  static let id = "planning-review"

  let definition = WorkflowDefinition(
    id: id,
    title: "Planning Review Workflow",
    subtitle: "Starts with an interactive planning pause before automated review cycles.",
    source: .builtIn,
    systemImage: "bubble.left.and.text.bubble.right",
    configuration: .none,
    steps: steps
  )

  private static let steps = [
    PlanningReviewStep(
      id: "interactive-planning",
      title: "Interactive planning",
      subtitle: "Waits for the user and planner session to produce a draft plan.",
      pendingSummary: "Waiting for the user to produce and submit a draft plan.",
      sortOrder: 10
    ),
    PlanningReviewStep(
      id: "submit-plan",
      title: "Submit plan message",
      subtitle: "Materializes the draft plan as a runtime-owned workflow message.",
      pendingSummary: "Submit-plan is unavailable until a reviewable draft exists.",
      sortOrder: 20
    ),
    PlanningReviewStep(
      id: "automated-review-cycles",
      title: "Automated review cycles",
      subtitle: "Runs multiple reviewer and planner-response cycles.",
      pendingSummary: "Reviewer cycles will start after the submitted plan message exists.",
      sortOrder: 30
    ),
    PlanningReviewStep(
      id: "interactive-user-review",
      title: "Interactive user review",
      subtitle: "Returns to the user to accept, continue planning, or request another cycle.",
      pendingSummary: "User review starts after the configured automated cycles complete.",
      sortOrder: 40
    ),
  ]

  static func makeInitialInteractionState() -> WorkflowInteractionState {
    WorkflowInteractionState(
      workflowID: id,
      stepID: "interactive-planning",
      title: "Interactive planning",
      subtitle: "Write or paste a draft plan, then submit it as a workflow message.",
      inputPlaceholder: "Add a note to keep with this interaction",
      draftTitle: "Draft plan",
      initialEntries: [
        WorkflowInteractionEntry(
          source: .system,
          text: "This workflow is paused until you submit a reviewable draft plan."
        )
      ]
    )
  }

  func run(context: BuiltInWorkflowRunContext) async -> BuiltInWorkflowRunResult {
    let progress = startInteractivePlanning(project: context.project)
    return .waiting(
      progress,
      output: """
        == Planning Review Workflow ==
        Interactive planning phase is waiting for user input.
        Use the upcoming submit-plan action to materialize a draft plan and start automated review.
        """
    )
  }

  func startInteractivePlanning(project: WorkflowProject) -> WorkflowRunProgress {
    WorkflowRunProgress(
      timeline: """
        Planning Review Workflow started.
        Interactive planning phase is waiting for user input.
        Automated reviewer cycles have not started.
        """,
      debugLogURL: nil,
      stepRecords: initialPlanningRecords(project: project)
    )
  }

  func submitPlan(project: WorkflowProject, message: InteractiveStepMessage) -> WorkflowRunProgress {
    WorkflowRunProgress(
      timeline: """
        Planning Review Workflow started.
        Interactive planning phase submitted a plan message.
        Automated reviewer cycles are ready to start.
        """,
      debugLogURL: nil,
      stepRecords: submittedPlanRecords(project: project, message: message)
    )
  }

  private func initialPlanningRecords(project: WorkflowProject) -> [WorkflowStepRecord] {
    Self.steps.map { step in
      step.id == "interactive-planning"
        ? interactivePlanningRecord(step: step, project: project)
        : pendingRecord(step: step)
    }
  }

  private func submittedPlanRecords(project: WorkflowProject, message: InteractiveStepMessage)
    -> [WorkflowStepRecord] {
    Self.steps.map { step in
      switch step.id {
      case "interactive-planning":
        return submittedInteractivePlanningRecord(step: step, project: project, message: message)
      case "submit-plan":
        return submittedPlanRecord(step: step, message: message)
      case "automated-review-cycles":
        return reviewCyclesReadyRecord(step: step)
      default:
        return pendingRecord(step: step)
      }
    }
  }

  private func submittedInteractivePlanningRecord(
    step: PlanningReviewStep,
    project: WorkflowProject,
    message: InteractiveStepMessage
  ) -> WorkflowStepRecord {
    WorkflowStepRecord(
      id: step.recordID,
      title: step.title,
      status: .succeeded,
      summary: "Planner interaction produced a submitted plan message.",
      inputPreview: """
        Project: \(project.name)
        Goal: Draft a reviewable implementation plan.
        """,
      outputPreview: message.summary ?? "Submitted plan message \(message.id)",
      sortOrder: step.sortOrder
    )
  }

  private func submittedPlanRecord(step: PlanningReviewStep, message: InteractiveStepMessage)
    -> WorkflowStepRecord {
    WorkflowStepRecord(
      id: step.recordID,
      title: step.title,
      status: .succeeded,
      summary: message.summary ?? "Submitted plan message \(message.id)",
      inputPreview: "Producer: interactive planning step",
      outputPreview: submittedPlanPreview(from: message),
      sortOrder: step.sortOrder
    )
  }

  private func reviewCyclesReadyRecord(step: PlanningReviewStep) -> WorkflowStepRecord {
    WorkflowStepRecord(
      id: step.recordID,
      title: step.title,
      status: .pending,
      summary: "Automated reviewer cycles are ready to consume the submitted plan.",
      sortOrder: step.sortOrder
    )
  }

  private func submittedPlanPreview(from message: InteractiveStepMessage) -> String {
    switch message.payload {
    case .artifact(let artifact):
      return artifact.content
    }
  }

  private func interactivePlanningRecord(
    step: PlanningReviewStep,
    project: WorkflowProject
  ) -> WorkflowStepRecord {
    WorkflowStepRecord(
      id: step.recordID,
      title: step.title,
      status: .inProgress,
      summary: step.pendingSummary,
      inputPreview: """
        Project: \(project.name)
        Goal: Draft a reviewable implementation plan.
        """,
      outputPreview: "No plan has been submitted yet.",
      sortOrder: step.sortOrder
    )
  }

  private func pendingRecord(step: PlanningReviewStep) -> WorkflowStepRecord {
    WorkflowStepRecord(
      id: step.recordID,
      title: step.title,
      status: .pending,
      summary: step.pendingSummary,
      sortOrder: step.sortOrder
    )
  }
}

private struct PlanningReviewStep {
  let id: String
  let title: String
  let subtitle: String
  let pendingSummary: String
  let sortOrder: Int

  var definition: WorkflowStepDefinition {
    WorkflowStepDefinition(id: id, title: title, subtitle: subtitle)
  }

  var recordID: String {
    "\(PlanningReviewWorkflowRunner.id)-\(id)"
  }
}

private extension WorkflowDefinition {
  init(
    id: String,
    title: String,
    subtitle: String,
    source: WorkflowSource,
    systemImage: String,
    configuration: WorkflowConfiguration,
    steps: [PlanningReviewStep]
  ) {
    self.init(
      id: id,
      title: title,
      subtitle: subtitle,
      source: source,
      systemImage: systemImage,
      configuration: configuration,
      steps: steps.map(\.definition)
    )
  }
}
