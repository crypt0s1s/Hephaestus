import Foundation
import Testing

@testable import Hephaestus

@MainActor
struct PlanningReviewWorkflowTests {
    @Test
    func planningReviewWorkflowStartsInInteractiveWaitingState() throws {
        let catalog = BuiltInWorkflowCatalog.production()
        let planningDefinition = try #require(catalog.workflow(id: PlanningReviewWorkflowRunner.id)?.definition)
        #expect(catalog.definitions.map(\.id).contains(PlanningReviewWorkflowRunner.id))
        #expect(planningDefinition.steps.first?.id == "interactive-planning")

        let projectURL = try makeTemporaryPlanningProject()
        let project = WorkflowProject(url: projectURL, bookmarkData: nil)
        let progress = makePlanningReviewWorkflowRunner().startInteractivePlanning(project: project)

        #expect(progress.timeline.contains("Interactive planning phase is waiting for user input."))
        #expect(progress.timeline.contains("Automated reviewer cycles have not started."))
        #expect(progress.stepRecords.first?.id == "planning-review-interactive-planning")
        #expect(progress.stepRecords.first?.status == .inProgress)
        #expect(progress.stepRecords.dropFirst().allSatisfy { $0.status == .pending })
    }

    @Test
    func submittingPlanAdvancesToReviewReadyState() throws {
        let projectURL = try makeTemporaryPlanningProject()
        let project = WorkflowProject(url: projectURL, bookmarkData: nil)
        let message = InteractiveStepOutput(
            producerStepID: "interactive-planning",
            artifact: InteractiveStepArtifact(
                title: "Submitted Plan",
                contentType: "text/markdown; artifact=plan",
                content: "# Plan\n\nBuild the interactive phase."
            ),
            summary: "Submitted plan for review"
        )

        let progress = makePlanningReviewWorkflowRunner().submitPlan(project: project, output: message)

        #expect(progress.timeline.contains("Interactive planning phase submitted a plan artifact."))
        #expect(progress.timeline.contains("Automated reviewer cycles are ready to start."))
        #expect(progress.stepRecords.count == 4)
        #expect(progress.stepRecords[0].status == .succeeded)
        #expect(progress.stepRecords[1].status == .succeeded)
        #expect(progress.stepRecords[1].outputPreview?.contains("Build the interactive phase.") == true)
        #expect(progress.stepRecords[2].status == .pending)
        #expect(
            progress.stepRecords[2].summary
                == "Automated reviewer cycles are ready to consume the submitted plan.")
    }

    @Test
    func planningInteractionSubmissionMaterializesPlanAndReturnsForUserReview() async throws {
        let projectURL = try makeTemporaryPlanningProject()
        let model = makePlanningReviewModel(projectURL: projectURL)
        var interaction = PlanningReviewWorkflowRunner.makeInitialInteractionState()
        let sessionID = interaction.sessionID
        interaction.draft = validPlanMarkdown
        interaction.draftProvenance = .userEdited
        model.update { $0.planningInteraction = interaction }

        await model.submitPlanningDraftPlan()

        let planURL =
            projectURL
            .appendingPathComponent(".hephaestus/planning-review/\(sessionID)", isDirectory: true)
            .appendingPathComponent("plan.md")
        let writtenPlan = try String(contentsOf: planURL, encoding: .utf8)
        #expect(writtenPlan == validPlanMarkdown)
        #expect(model.state.planningInteraction?.phase == .completed)
        #expect(model.state.planningInteraction?.submittedOutput?.artifact.projectRelativePath != nil)
        #expect(model.state.isRunning)
        #expect(model.state.lastRunSucceeded == nil)
        #expect(
            model.state.stepRecords.contains {
                $0.id == "planning-review-interactive-user-review" && $0.status == .inProgress
            })
        #expect(model.state.stepRecords.contains { $0.id == "planning-review-reviewer-1-1" })
        #expect(model.state.stepRecords.contains { $0.id == "planning-review-planner-response-2" })

        model.acceptPlanningReview()

        #expect(model.state.planningInteraction?.phase == .accepted)
        #expect(model.state.planningInteraction?.canResolveCompletedOutput == false)
        #expect(!model.state.isRunning)
        #expect(model.state.lastRunSucceeded == true)
    }

    @Test
    func planningInteractionSubmissionRejectsIncompletePlan() async throws {
        let projectURL = try makeTemporaryPlanningProject()
        let model = makePlanningReviewModel(projectURL: projectURL)
        var interaction = PlanningReviewWorkflowRunner.makeInitialInteractionState()
        let sessionID = interaction.sessionID
        interaction.draft = "# Plan\n\nThis is not enough yet."
        interaction.draftProvenance = .userEdited
        model.update { $0.planningInteraction = interaction }

        await model.submitPlanningDraftPlan()

        let planURL =
            projectURL
            .appendingPathComponent(".hephaestus/planning-review/\(sessionID)", isDirectory: true)
            .appendingPathComponent("plan.md")
        #expect(!FileManager.default.fileExists(atPath: planURL.path))
        #expect(model.state.planningInteraction?.phase == .idle)
        #expect(model.state.planningInteraction?.submittedOutput == nil)
        #expect(
            model.state.planningInteraction?.errorMessage?
                .contains("Plan is missing required sections") == true)
    }

    @Test
    func failedAutomationCycleDoesNotEnterUserReviewPause() {
        let run = PlanningReviewPrototypeAutomationRun(
            timeline: "started",
            records: [
                WorkflowStepRecord(
                    id: "planning-review-reviewer-1-1",
                    title: "Reviewer A cycle 1",
                    status: .failed,
                    summary: "Reviewer failed.",
                    sortOrder: 200
                )
            ],
            planPath: ".hephaestus/planning-review/session/plan.md"
        )

        let result = makePlanningReviewWorkflowRunner().finishPlanningReviewPrototypeAutomationRun(run)

        #expect(result.exitCode == 1)
        #expect(!result.stepRecords.contains { $0.id == "planning-review-interactive-user-review" })
        #expect(result.output.contains("Automated review cycles failed"))
    }

    @Test
    func failedPlanningReviewReturnsInteractionToEditableDraft() async throws {
        let projectURL = try makeTemporaryPlanningProject()
        let model = makePlanningReviewModel(projectURL: projectURL)
        var interaction = PlanningReviewWorkflowRunner.makeInitialInteractionState()
        interaction.draft = validPlanMarkdown
        interaction.draftProvenance = .userEdited
        interaction.submittedOutput = InteractiveStepOutput(
            producerStepID: interaction.stepID,
            artifact: InteractiveStepArtifact(
                title: "Submitted Plan",
                contentType: "text/markdown; artifact=plan",
                content: validPlanMarkdown,
                projectRelativePath: ".hephaestus/planning-review/session/plan.md"
            ),
            summary: "Submitted plan"
        )
        interaction.phase = .completed
        model.update {
            $0.planningInteraction = interaction
            $0.stepRecords = [
                WorkflowStepRecord(
                    id: "planning-review-reviewer-1-1",
                    title: "Reviewer A cycle 1",
                    status: .failed,
                    summary: "Reviewer failed.",
                    sortOrder: 200
                )
            ]
        }

        await model.requestAnotherPlanningReviewCycle()

        #expect(model.state.planningInteraction?.phase == .idle)
        #expect(model.state.planningInteraction?.submittedOutput == nil)
        #expect(model.state.planningInteraction?.canSubmit == true)
        #expect(model.state.planningInteraction?.errorMessage?.contains("Automated review failed") == true)
        #expect(!model.state.isRunning)
        #expect(model.state.lastRunSucceeded == false)
    }

    @Test
    func generatedPlanningDraftRequiresUserEditBeforeSubmission() async throws {
        let projectURL = try makeTemporaryPlanningProject()
        let model = makePlanningReviewModel(projectURL: projectURL)
        var interaction = PlanningReviewWorkflowRunner.makeInitialInteractionState()
        interaction.note = "Build an interactive planning workflow."
        model.update { $0.planningInteraction = interaction }

        await model.sendPlanningMessage()

        #expect(model.state.planningInteraction?.draftProvenance == .agentGenerated)
        #expect(model.state.planningInteraction?.canSubmit == false)
        #expect(model.state.planningInteraction?.draftRequiresUserEdit == true)

        await model.submitPlanningDraftPlan()

        #expect(model.state.planningInteraction?.submittedOutput == nil)
        #expect(
            model.state.planningInteraction?.errorMessage?
                .contains("Edit the generated draft") == true)

        model.updatePlanningDraftPlan(validPlanMarkdown + "\n")

        #expect(model.state.planningInteraction?.draftProvenance == .userEdited)
        #expect(model.state.planningInteraction?.canSubmit == true)
    }
}

private func makeTemporaryPlanningProject() throws -> URL {
    let url = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("hephaestus-planning-review-tests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

@MainActor
private func makePlanningReviewWorkflowRunner() -> PlanningReviewWorkflowRunner {
    PlanningReviewWorkflowRunner(
        automation: PlanningReviewPrototypeAutomation(
            agentStep: CodexAgentStep(backendAdapter: MockHarnessBackendAdapter())
        ))
}

@MainActor
private func makePlanningReviewModel(projectURL: URL) -> WorkflowRunnerModel {
    let project = WorkflowProject(url: projectURL, bookmarkData: nil)
    return WorkflowRunnerModel(
        projectStore: StaticProjectStore(project: project),
        projectPicker: EmptyProjectPicker(),
        branchReader: GitBranchReader(
            processRunner: RecordingProcessRunner(results: [ProcessResult(exitCode: 0, output: "main")])
        ),
        builtInWorkflowCatalog: .production(processRunner: RecordingProcessRunner(results: [])),
        externalWorkflowDiscovery: ExternalWorkflowDiscovery(
            environment: [:],
            processRunner: RecordingProcessRunner(results: [])
        ),
        externalWorkflowRunner: ExternalWorkflowRunner(),
        planningReviewServices: PlanningReviewServices(backendAdapter: MockHarnessBackendAdapter()),
        environment: [:]
    )
}

private struct StaticProjectStore: ProjectStore {
    let project: WorkflowProject

    func load() -> ProjectStoreSnapshot {
        ProjectStoreSnapshot(projects: [project], selectedProjectID: project.id)
    }

    func saveProjects(_ projects: [WorkflowProject]) {}

    func saveSelectedProjectID(_ id: WorkflowProject.ID?) {}
}

private struct EmptyProjectPicker: ProjectPicker {
    func pickProject() throws -> WorkflowProject? { nil }
}

private let validPlanMarkdown = """
    # Plan

    ## Summary
    Build the interactive planning workflow.

    ## Scope
    - Generate and submit a plan.

    ## Non-Goals
    - Do not build the full workflow builder.

    ## Implementation Approach
    - Materialize the selected draft.

    ## Validation
    - Run focused unit tests.

    ## Open Questions
    - What is the long-term pause envelope?
    """
