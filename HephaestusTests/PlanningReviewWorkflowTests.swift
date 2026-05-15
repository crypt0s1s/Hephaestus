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
        interaction.updatePlanningDraftCandidate(content: validPlanMarkdown, source: .user)
        model.update { $0.planningInteraction = interaction }

        await model.submitPlanningDraftPlan()

        let submittedOutput = try #require(model.state.planningInteraction?.submittedOutput)
        try expectAcceptedPlanningFiles(
            projectURL: projectURL,
            sessionID: sessionID,
            submittedOutput: submittedOutput
        )
        expectPlanningReviewWaitingForUser(model)
        let reviewedInteraction = try #require(model.state.planningInteraction)
        try expectPlannerResponseArtifacts(
            projectURL: projectURL,
            sessionID: sessionID,
            interaction: reviewedInteraction
        )

        model.acceptPlanningReview()

        expectPlanningReviewAccepted(model)
        let latestOutput = try #require(model.state.planningInteraction?.latestResolvedOutput)
        try expectFinalPlanningAcceptance(
            projectURL: projectURL,
            sessionID: sessionID,
            output: latestOutput
        )
    }

    private func expectAcceptedPlanningFiles(
        projectURL: URL,
        sessionID: String,
        submittedOutput: InteractiveStepOutput
    ) throws {
        let planURL =
            projectURL
            .appendingPathComponent(".hephaestus/planning-review/\(sessionID)", isDirectory: true)
            .appendingPathComponent("plan.md")
        #expect(try String(contentsOf: planURL, encoding: .utf8) == validPlanMarkdown)
        let acceptedPlanURL =
            projectURL
            .appendingPathComponent(".hephaestus/planning-review/\(sessionID)/accepted", isDirectory: true)
            .appendingPathComponent("plan.md")
        #expect(try String(contentsOf: acceptedPlanURL, encoding: .utf8) == validPlanMarkdown)
        let acceptance = try loadPersistedPlanningAcceptanceRecord(
            projectURL: projectURL,
            sessionID: sessionID,
            kind: .draft
        )
        #expect(acceptance.kind == "draftAcceptedForReview")
        #expect(acceptance.outputID == submittedOutput.id)
        #expect(acceptance.acceptedRevision == 1)
        #expect(acceptance.contentHash == PlanningPlanArtifactPolicy.contentHash(validPlanMarkdown))
        #expect(acceptance.acceptedAt == submittedOutput.createdAt)
        #expect(acceptance.idempotencyKey == "\(sessionID)-draft-plan-1")
        #expect(acceptance.content == validPlanMarkdown)
        #expect(acceptance.contentType == PlanningPlanArtifactPolicy.contentType)
        #expect(acceptance.projectRelativePath == submittedOutput.artifact.projectRelativePath)
    }

    private func expectPlannerResponseArtifacts(
        projectURL: URL,
        sessionID: String,
        interaction: PlanningInteractionState
    ) throws {
        let cycleOneOutput = try #require(
            interaction.relatedOutputs.first { $0.producerStepID == "planner-response-cycle-1" }
        )
        try expectPlannerResponseArtifact(
            projectURL: projectURL,
            sessionID: sessionID,
            output: cycleOneOutput,
            cycle: 1
        )
        let cycleTwoOutput = try #require(interaction.latestResolvedOutput)
        try expectPlannerResponseArtifact(
            projectURL: projectURL,
            sessionID: sessionID,
            output: cycleTwoOutput,
            cycle: 2
        )
    }

    private func expectPlannerResponseArtifact(
        projectURL: URL,
        sessionID: String,
        output: InteractiveStepOutput,
        cycle: Int
    ) throws {
        let planPath = PlanningPlanArtifactPolicy.plannerResponsePlanPath(sessionID: sessionID, cycle: cycle)
        let planURL = projectURL.appendingPathComponent(planPath)
        #expect(output.producerStepID == "planner-response-cycle-\(cycle)")
        #expect(output.artifact.projectRelativePath == planPath)
        #expect(output.artifact.contentType == PlanningPlanArtifactPolicy.contentType)
        #expect(try String(contentsOf: planURL, encoding: .utf8) == output.artifact.content)
    }

    private func expectPlanningReviewWaitingForUser(_ model: WorkflowRunnerModel) {
        #expect(model.state.planningInteraction?.phase == .completed)
        #expect(model.state.planningInteraction?.submittedOutput?.artifact.projectRelativePath != nil)
        #expect(!model.state.isRunning)
        #expect(model.state.activeWorkflowActivity == .waitingForUserReview)
        #expect(model.state.lastRunSucceeded == nil)
        #expect(
            model.state.stepRecords.contains {
                $0.id == "planning-review-interactive-user-review" && $0.status == .inProgress
            })
        #expect(model.state.stepRecords.contains { $0.id == "planning-review-reviewer-1-1" })
        #expect(model.state.stepRecords.contains { $0.id == "planning-review-consolidated-feedback-1" })
        #expect(model.state.stepRecords.contains { $0.id == "planning-review-planner-response-2" })
        #expect(model.state.planningInteraction?.latestResolvedOutput?.producerStepID == "planner-response-cycle-2")
        #expect(
            model.state.planningInteraction?.relatedOutputs.contains {
                $0.producerStepID == "automated-review-cycle-1"
            } == true)
    }

    private func expectFinalPlanningAcceptance(
        projectURL: URL,
        sessionID: String,
        output: InteractiveStepOutput
    ) throws {
        let acceptedPlanURL =
            projectURL
            .appendingPathComponent(".hephaestus/planning-review/\(sessionID)/accepted", isDirectory: true)
            .appendingPathComponent("plan.md")
        #expect(try String(contentsOf: acceptedPlanURL, encoding: .utf8) == output.artifact.content)
        let acceptance = try loadPersistedPlanningAcceptanceRecord(
            projectURL: projectURL,
            sessionID: sessionID,
            kind: .final
        )
        #expect(acceptance.kind == "finalReviewedPlanAccepted")
        #expect(acceptance.outputID == output.id)
        #expect(acceptance.acceptedRevision == 0)
        #expect(acceptance.contentHash == PlanningPlanArtifactPolicy.contentHash(output.artifact.content))
        #expect(
            acceptance.acceptedAt.timeIntervalSince1970.rounded(.down)
                == acceptance.acceptedAt.timeIntervalSince1970)
        #expect(acceptance.content == output.artifact.content)
        #expect(acceptance.contentType == PlanningPlanArtifactPolicy.contentType)
        #expect(acceptance.idempotencyKey == "final-review-\(output.id)")
        #expect(acceptance.projectRelativePath == output.artifact.projectRelativePath)
        #expect(acceptance.projectRelativePath == PlanningPlanArtifactPolicy.relativePlanPath(sessionID: sessionID))
        let draftAcceptance = try loadPersistedPlanningAcceptanceRecord(
            projectURL: projectURL,
            sessionID: sessionID,
            kind: .draft
        )
        #expect(draftAcceptance.kind == "draftAcceptedForReview")
    }

    private func expectPlanningReviewAccepted(_ model: WorkflowRunnerModel) {
        #expect(model.state.planningInteraction?.phase == .accepted)
        #expect(model.state.planningInteraction?.canResolveCompletedOutput == false)
        #expect(!model.state.isRunning)
        #expect(model.state.lastRunSucceeded == true)
        #expect(
            model.state.stepRecords.contains {
                $0.id == "planning-review-interactive-user-review" && $0.status == .succeeded
            })
    }

    @Test
    func planningInteractionSubmissionRejectsIncompletePlan() async throws {
        let projectURL = try makeTemporaryPlanningProject()
        let model = makePlanningReviewModel(projectURL: projectURL)
        var interaction = PlanningReviewWorkflowRunner.makeInitialInteractionState()
        let sessionID = interaction.sessionID
        interaction.updatePlanningDraftCandidate(content: "# Plan\n\nThis is not enough yet.", source: .user)
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
    func generatedPlanningDraftCanBeAcceptedAfterUserReviewWithoutForcedEdit() async throws {
        let projectURL = try makeTemporaryPlanningProject()
        let model = makePlanningReviewModel(projectURL: projectURL)
        var interaction = PlanningReviewWorkflowRunner.makeInitialInteractionState()
        interaction.note = "Build an interactive planning workflow."
        model.update { $0.planningInteraction = interaction }

        await model.sendPlanningMessage()

        #expect(model.state.planningInteraction?.canSubmit == true)
        #expect(model.state.planningInteraction?.gateState.canAcceptOutputForReview == true)
        let draftPath = PlanningPlanArtifactPolicy.draftPlanPath(sessionID: interaction.sessionID)
        let draftURL = projectURL.appendingPathComponent(draftPath)
        #expect(try String(contentsOf: draftURL, encoding: .utf8).contains("## Summary"))
    }

    @Test
    func validAgentDraftCandidateCanBeAcceptedAsReviewedOutput() async throws {
        let projectURL = try makeTemporaryPlanningProject()
        let model = makePlanningReviewModel(projectURL: projectURL)
        var interaction = PlanningReviewWorkflowRunner.makeInitialInteractionState()
        interaction.updatePlanningDraftCandidate(content: validPlanMarkdown, source: .agent)
        model.update { $0.planningInteraction = interaction }

        #expect(model.state.planningInteraction?.canSubmit == true)

        await model.submitPlanningDraftPlan()

        #expect(model.state.planningInteraction?.submittedOutput != nil)
        #expect(model.state.planningInteraction?.gateState.canAcceptOutputForReview == false)
    }

    @Test
    func invalidDraftCandidateBlocksSubmissionRegardlessOfProvenance() async throws {
        let projectURL = try makeTemporaryPlanningProject()
        let model = makePlanningReviewModel(projectURL: projectURL)
        var interaction = PlanningReviewWorkflowRunner.makeInitialInteractionState()
        interaction.updatePlanningDraftCandidate(content: "# Plan\n\nStill rough.", source: .user)
        model.update { $0.planningInteraction = interaction }

        #expect(model.state.planningInteraction?.canSubmit == false)

        await model.submitPlanningDraftPlan()

        #expect(model.state.planningInteraction?.submittedOutput == nil)
        #expect(
            model.state.planningInteraction?.errorMessage?
                .contains("Plan is missing required sections") == true)
    }

}
