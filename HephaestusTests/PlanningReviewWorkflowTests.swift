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

        try assertCompletedPlanningReviewSubmission(
            model: model,
            projectURL: projectURL,
            sessionID: sessionID
        )

        model.acceptPlanningReview()

        #expect(model.state.planningInteraction?.phase == .accepted)
        #expect(model.state.planningInteraction?.runtimeRun.status == .completed)
        #expect(model.state.planningInteraction?.runtimeRun.activePause == nil)
        #expect(model.state.planningInteraction?.canResolveCompletedOutput == false)
        #expect(!model.state.isRunning)
        #expect(model.state.lastRunSucceeded == true)
    }

    @Test
    func continuePlanningReviewReopensLatestPlanWithFeedbackHistory() async throws {
        let projectURL = try makeTemporaryPlanningProject()
        let model = makePlanningReviewModel(projectURL: projectURL)
        var interaction = PlanningReviewWorkflowRunner.makeInitialInteractionState()
        interaction.draft = validPlanMarkdown
        interaction.draftProvenance = .userEdited
        model.update { $0.planningInteraction = interaction }

        await model.submitPlanningDraftPlan()

        let completedInteraction = try #require(model.state.planningInteraction)
        let latestPlan = try #require(
            completedInteraction.workflowMessages.last { $0.kind == .currentPlan }?.currentPlan
        )

        model.continuePlanningReview()

        let reopenedInteraction = try #require(model.state.planningInteraction)
        #expect(reopenedInteraction.phase == .idle)
        #expect(reopenedInteraction.submittedOutput == nil)
        #expect(reopenedInteraction.draft == latestPlan.content)
        #expect(reopenedInteraction.draftProvenance == .agentGenerated)
        #expect(reopenedInteraction.draftRequiresUserEdit)
        #expect(reopenedInteraction.runtimeRun.activePause?.reason == .interactiveInput)
        #expect(reopenedInteraction.entries.contains {
            $0.text.contains("Feedback history:") && $0.text.contains("Planner response:")
        })
        #expect(model.state.stepRecords.contains { $0.id == "planning-review-planner-response-2" })
        #expect(model.state.stepRecords.contains {
            $0.id == "planning-review-interactive-user-review" && $0.status == .needsFix
        })
        #expect(model.state.stepRecords.contains {
            $0.id == "planning-review-interactive-planning-continued" && $0.status == .inProgress
        })
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
            planPath: ".hephaestus/planning-review/session/plan.md",
            terminalFailure: "All reviewers failed in cycle 1."
        )

        let result = makePlanningReviewWorkflowRunner().finishPlanningReviewPrototypeAutomationRun(run)

        #expect(result.exitCode == 1)
        #expect(!result.stepRecords.contains { $0.id == "planning-review-interactive-user-review" })
        #expect(result.output.contains("Automated review cycles failed"))
    }

    @Test
    func automatedCyclesReviewLatestPlannerResponseMessage() async throws {
        let projectURL = try makeTemporaryPlanningProject()
        let project = WorkflowProject(url: projectURL, bookmarkData: nil)
        let output = makeInteractiveOutput(content: validPlanMarkdown)
        let result = await makePlanningReviewWorkflowRunner().runAutomatedReviewCycles(
            project: project,
            submittedOutput: output
        )

        #expect(result.exitCode == 0)
        let firstCurrentPlan = try #require(
            result.workflowMessages.first {
                $0.kind == .currentPlan && $0.currentPlan?.cycle == 1
            })
        let cycleTwoReviewerMessages = result.workflowMessages.filter {
            $0.kind == .reviewerFeedback && $0.reviewerFeedback?.cycle == 2
        }
        #expect(cycleTwoReviewerMessages.count == 2)
        #expect(cycleTwoReviewerMessages.allSatisfy {
            $0.reviewerFeedback?.reviewedMessageID == firstCurrentPlan.id
        })
    }

    @Test
    func plannerResponseFailureStopsFurtherAutomatedCycles() async throws {
        let projectURL = try makeTemporaryPlanningProject()
        let project = WorkflowProject(url: projectURL, bookmarkData: nil)
        let output = makeInteractiveOutput(content: validPlanMarkdown)
        let runner = makePlanningReviewWorkflowRunner(
            backendAdapter: PlannerResponseFailingPlanningReviewBackendAdapter()
        )

        let result = await runner.runAutomatedReviewCycles(project: project, submittedOutput: output)

        #expect(result.exitCode == 1)
        #expect(result.output.contains("Planner response failed in cycle 1."))
        #expect(result.stepRecords.contains {
            $0.id == "planning-review-planner-response-1" && $0.status == .failed
        })
        #expect(!result.stepRecords.contains { $0.id == "planning-review-reviewer-2-1" })
        #expect(result.workflowMessages.contains {
            $0.consolidatedReview?.cycle == 1
        })
        #expect(result.workflowMessages.contains {
            $0.plannerResponse?.cycle == 1 && $0.plannerResponse?.exitCode == 1
        })
        #expect(!result.workflowMessages.contains { $0.kind == .currentPlan })
    }

    @Test
    func singleReviewerFailureStillContinuesReviewCycles() async throws {
        let projectURL = try makeTemporaryPlanningProject()
        let project = WorkflowProject(url: projectURL, bookmarkData: nil)
        let output = makeInteractiveOutput(content: validPlanMarkdown)
        let runner = makePlanningReviewWorkflowRunner(
            backendAdapter: SelectivePlanningReviewBackendAdapter(failingReviewerNames: ["Reviewer A"])
        )

        let result = await runner.runAutomatedReviewCycles(project: project, submittedOutput: output)

        #expect(result.exitCode == 0)
        #expect(result.stepRecords.contains {
            $0.id == "planning-review-reviewer-1-1" && $0.status == .failed
        })
        #expect(result.stepRecords.contains { $0.id == "planning-review-planner-response-2" })
        #expect(result.workflowMessages.filter { $0.kind == .reviewerFeedback }.count == 2)
        let consolidatedReviews = result.workflowMessages.compactMap(\.consolidatedReview)
        #expect(consolidatedReviews.count == 2)
        #expect(consolidatedReviews.allSatisfy {
            $0.failedReviewers.first?.reviewerName == "Reviewer A"
        })
    }

    @Test
    func singleReviewerFailurePersistsFailedReviewerStateInConsolidatedReview() async throws {
        let projectURL = try makeTemporaryPlanningProject()
        let model = makePlanningReviewModel(
            projectURL: projectURL,
            backendAdapter: SelectivePlanningReviewBackendAdapter(failingReviewerNames: ["Reviewer A"])
        )
        var interaction = PlanningReviewWorkflowRunner.makeInitialInteractionState()
        let sessionID = interaction.sessionID
        interaction.draft = validPlanMarkdown
        interaction.draftProvenance = .userEdited
        model.update { $0.planningInteraction = interaction }

        await model.submitPlanningDraftPlan()

        let consolidatedMessage = try #require(
            model.state.planningInteraction?.workflowMessages.first { $0.kind == .consolidatedReview }
        )
        let consolidatedReview = try #require(consolidatedMessage.consolidatedReview)
        #expect(consolidatedReview.failedReviewers.count == 1)
        #expect(consolidatedReview.failedReviewers.first?.reviewerName == "Reviewer A")
        #expect(consolidatedReview.failedReviewers.first?.stepID == "planning-review-reviewer-1-1")

        let persistedMessage = try decodePersistedWorkflowMessage(
            consolidatedMessage.id,
            projectURL: projectURL,
            sessionID: sessionID
        )
        #expect(persistedMessage.consolidatedReview?.failedReviewers.first?.reviewerName == "Reviewer A")
    }

    @Test
    func plannerResponsePromptIncludesFailedReviewerState() throws {
        let projectURL = try makeTemporaryPlanningProject()
        try assertPlannerResponsePromptIncludesFailedReviewerState(projectURL: projectURL)
    }

    @Test
    func allReviewerFailuresStopBeforePlannerResponse() async throws {
        let projectURL = try makeTemporaryPlanningProject()
        let project = WorkflowProject(url: projectURL, bookmarkData: nil)
        let output = makeInteractiveOutput(content: validPlanMarkdown)
        let runner = makePlanningReviewWorkflowRunner(
            backendAdapter: SelectivePlanningReviewBackendAdapter(
                failingReviewerNames: ["Reviewer A", "Reviewer B"]
            )
        )

        let result = await runner.runAutomatedReviewCycles(project: project, submittedOutput: output)

        #expect(result.exitCode == 1)
        #expect(result.output.contains("All reviewers failed in cycle 1"))
        #expect(!result.stepRecords.contains { $0.id.hasPrefix("planning-review-planner-response") })
        #expect(!result.workflowMessages.contains { $0.kind == .consolidatedReview })
    }

    @Test
    func automatedMessagePersistenceFailureStopsBeforePlannerResponse() async throws {
        let projectURL = try makeTemporaryPlanningProject()
        let model = makePlanningReviewModel(
            projectURL: projectURL,
            messageStore: FailingAfterFirstPlanningReviewMessageStore()
        )
        var interaction = PlanningReviewWorkflowRunner.makeInitialInteractionState()
        interaction.draft = validPlanMarkdown
        interaction.draftProvenance = .userEdited
        model.update { $0.planningInteraction = interaction }

        await model.submitPlanningDraftPlan()

        #expect(model.state.lastRunSucceeded == false)
        #expect(model.state.output.contains("Workflow message persistence failed before planner response"))
        #expect(!model.state.stepRecords.contains { $0.id == "planning-review-planner-response-1" })
        #expect(model.state.planningInteraction?.workflowMessages.contains {
            $0.kind == .consolidatedReview
        } == false)
    }

    @Test
    func failedPlanningReviewReturnsInteractionToEditableDraft() async throws {
        let projectURL = try makeTemporaryPlanningProject()
        let model = makePlanningReviewModel(
            projectURL: projectURL,
            backendAdapter: SelectivePlanningReviewBackendAdapter(
                failingReviewerNames: ["Reviewer A", "Reviewer B"]
            )
        )
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
