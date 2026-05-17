import Foundation

struct PlanningReviewWorkflowRunner: BuiltInWorkflow {
    static let id = "planning-review"
    let automation: any PlanningReviewAutomating

    init(automation: any PlanningReviewAutomating) {
        self.automation = automation
    }

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
            pendingSummary: "Reviewer cycles will start after the submitted plan artifact exists.",
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

    static func makeInitialInteractionState() -> PlanningInteractionState {
        PlanningInteractionState(
            workflowID: id,
            stepID: "interactive-planning",
            title: "Interactive planning",
            subtitle: "Write or paste a draft plan, then submit it as a workflow message.",
            inputPlaceholder: "Add a note to keep with this interaction",
            draftTitle: "Draft plan",
            outputCandidate: PlanningInteractionState.makePlanningDraftCandidate(),
            initialEntries: [
                PlanningInteractionEntry(
                    source: .system,
                    text: "This workflow is paused until you submit a reviewable draft plan."
                )
            ]
        )
    }

    func run(context: BuiltInWorkflowRunContext) async -> BuiltInWorkflowRunResult {
        let interaction = Self.makeInitialInteractionState()
        context.interactiveSessionStore.setPlanningInteractionState(interaction)
        let progress = startInteractivePlanning(project: context.project)
        return .waiting(
            progress,
            output: """
                == Planning Review Workflow ==
                Interactive planning phase is waiting for user input.
                Use the upcoming submit-plan action to materialize a draft plan and start automated review.
                """,
            activity: interaction.interactiveActivityProjection
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

    func submitPlan(project: WorkflowProject, output: InteractiveStepOutput) -> WorkflowRunProgress {
        WorkflowRunProgress(
            timeline: """
                Planning Review Workflow started.
                Interactive planning phase submitted a plan artifact.
                Automated reviewer cycles are ready to start.
                """,
            debugLogURL: nil,
            stepRecords: submittedPlanRecords(project: project, output: output)
        )
    }

    func runAutomatedReviewCycles(
        project: WorkflowProject,
        submittedOutput: InteractiveStepOutput,
        sessionID: String,
        progress: WorkflowProgressHandler? = nil
    ) async -> PlanningReviewAutomationResult {
        let planPath = submittedOutput.artifact.projectRelativePath ?? "the submitted plan artifact"
        var run = PlanningReviewAutomationRun(
            sessionID: sessionID,
            timeline: automation.startedTimeline,
            records: submittedPlanRecords(project: project, output: submittedOutput),
            planPath: planPath,
            currentPlanOutput: submittedOutput,
            relatedOutputs: [submittedOutput]
        )
        for cycle in 1...automation.reviewCycleCount {
            let shouldContinue = await automation.runCycle(
                cycle: cycle,
                project: project,
                run: &run,
                progress: progress
            )
            guard shouldContinue else { break }
        }
        return PlanningReviewAutomationResult(
            processResult: finishPlanningReviewAutomationRun(run),
            run: run
        )
    }

    func runPlanningReviewAutomationCycle(
        cycle: Int,
        project: WorkflowProject,
        run: inout PlanningReviewAutomationRun,
        progress: WorkflowProgressHandler?
    ) async {
        _ = await automation.runCycle(
            cycle: cycle,
            project: project,
            run: &run,
            progress: progress
        )
    }

    func makeAdditionalAutomationRun(
        interaction: PlanningInteractionState,
        submittedOutput: InteractiveStepOutput,
        currentPlanOutput: InteractiveStepOutput,
        timeline: String,
        records: [WorkflowStepRecord]
    ) -> PlanningReviewAutomationRun {
        PlanningReviewAutomationRun(
            sessionID: interaction.sessionID,
            timeline: timeline.isEmpty ? automation.startedTimeline : timeline,
            records: records.filter { $0.id != Self.interactiveUserReviewRecordID },
            planPath: currentPlanOutput.artifact.projectRelativePath ?? "the latest reviewed plan",
            currentPlanOutput: currentPlanOutput,
            relatedOutputs: interaction.relatedOutputs.isEmpty ? [submittedOutput] : interaction.relatedOutputs
        )
    }

    func nextAutomationCycleNumber(from records: [WorkflowStepRecord]) -> Int {
        let existingCycles = records.compactMap(Self.reviewerCycleNumber)
        return (existingCycles.max() ?? 0) + 1
    }

    func finishPlanningReviewAutomationRun(
        _ run: PlanningReviewAutomationRun
    ) -> ProcessResult {
        automation.finish(run)
    }

    nonisolated private static let interactiveUserReviewRecordID = "planning-review-interactive-user-review"

    nonisolated private static func reviewerCycleNumber(from record: WorkflowStepRecord) -> Int? {
        guard record.id.hasPrefix("planning-review-reviewer-") else { return nil }
        let parts = record.id.split(separator: "-")
        return parts.dropFirst(3).first.flatMap { Int($0) }
    }

    private func initialPlanningRecords(project: WorkflowProject) -> [WorkflowStepRecord] {
        Self.steps.map { step in
            step.id == "interactive-planning"
                ? interactivePlanningRecord(step: step, project: project)
                : pendingRecord(step: step)
        }
    }

    private func submittedPlanRecords(project: WorkflowProject, output: InteractiveStepOutput)
        -> [WorkflowStepRecord] {
        Self.steps.map { step in
            switch step.id {
            case "interactive-planning":
                return submittedInteractivePlanningRecord(step: step, project: project, output: output)
            case "submit-plan":
                return submittedPlanRecord(step: step, output: output)
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
        output: InteractiveStepOutput
    ) -> WorkflowStepRecord {
        WorkflowStepRecord(
            id: step.recordID,
            title: step.title,
            status: .succeeded,
            summary: "Planner interaction produced a submitted plan artifact.",
            inputPreview: """
                Project: \(project.name)
                Goal: Draft a reviewable implementation plan.
                """,
            outputPreview: output.summary ?? "Submitted plan artifact \(output.id)",
            artifactReferences: [.init(output: output, title: "Submitted plan")],
            sortOrder: step.sortOrder
        )
    }

    private func submittedPlanRecord(step: PlanningReviewStep, output: InteractiveStepOutput)
        -> WorkflowStepRecord {
        WorkflowStepRecord(
            id: step.recordID,
            title: step.title,
            status: .succeeded,
            summary: output.summary ?? "Submitted plan artifact \(output.id)",
            inputPreview: "Producer: interactive planning step",
            outputPreview: submittedPlanPreview(from: output),
            artifactReferences: [.init(output: output, title: "Submitted plan")],
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

    private func submittedPlanPreview(from output: InteractiveStepOutput) -> String {
        output.artifact.content
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

extension WorkflowDefinition {
    fileprivate init(
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
