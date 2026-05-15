import Foundation
import Testing

@testable import Hephaestus

@MainActor
struct PlanningReviewWorkflowFailureTests {
    @Test
    func failedAutomationCycleDoesNotEnterUserReviewPause() {
        let run = PlanningReviewAutomationRun(
            sessionID: "session",
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

        let result = makePlanningReviewWorkflowRunner().finishPlanningReviewAutomationRun(run)

        #expect(result.exitCode == 1)
        #expect(!result.stepRecords.contains { $0.id == "planning-review-interactive-user-review" })
        #expect(result.output.contains("Automated review cycles failed"))
    }

    @Test
    func allReviewerFailureReturnsInteractionToEditableDraft() async throws {
        let projectURL = try makeTemporaryPlanningProject()
        let model = makePlanningReviewModel(
            projectURL: projectURL,
            backendAdapter: AllFailingReviewersHarnessBackendAdapter()
        )
        var interaction = PlanningReviewWorkflowRunner.makeInitialInteractionState()
        interaction.updatePlanningDraftCandidate(content: validPlanMarkdown, source: .user)
        interaction.submittedOutput = submittedOutput(for: interaction)
        interaction.phase = .completed
        model.seedPlanningInteractionState(interaction)

        await model.requestAnotherPlanningReviewCycle()

        #expect(model.currentPlanningInteractionState?.phase == .idle)
        #expect(model.currentPlanningInteractionState?.submittedOutput == nil)
        #expect(model.currentPlanningInteractionState?.canSubmit == true)
        #expect(model.currentPlanningInteractionState?.errorMessage?.contains("Automated review failed") == true)
        #expect(!model.state.stepRecords.contains { $0.id.hasPrefix("planning-review-planner-response-") })
        #expect(model.state.stepRecords.contains { $0.id == "planning-review-consolidated-feedback-1" })
        #expect(!model.state.isRunning)
        #expect(model.state.lastRunSucceeded == false)
    }

    @Test
    func plannerResponseFailureStopsBeforeLaterCycles() async throws {
        let projectURL = try makeTemporaryPlanningProject()
        let model = makePlanningReviewModel(
            projectURL: projectURL,
            backendAdapter: FailingPlannerResponseHarnessBackendAdapter()
        )
        var interaction = PlanningReviewWorkflowRunner.makeInitialInteractionState()
        interaction.updatePlanningDraftCandidate(content: validPlanMarkdown, source: .user)
        model.seedPlanningInteractionState(interaction)

        await model.submitPlanningDraftPlan()

        #expect(model.currentPlanningInteractionState?.phase == .idle)
        #expect(model.state.lastRunSucceeded == false)
        #expect(model.state.stepRecords.contains { $0.id == "planning-review-planner-response-1" })
        #expect(!model.state.stepRecords.contains { $0.id == "planning-review-reviewer-2-1" })
    }

    @Test
    func laterCycleFailureReopensLatestSuccessfulPlannerResponseDraft() async throws {
        let projectURL = try makeTemporaryPlanningProject()
        let model = makePlanningReviewModel(
            projectURL: projectURL,
            backendAdapter: FailingSecondPlannerResponseHarnessBackendAdapter()
        )
        var interaction = PlanningReviewWorkflowRunner.makeInitialInteractionState()
        interaction.updatePlanningDraftCandidate(content: validPlanMarkdown, source: .user)
        model.seedPlanningInteractionState(interaction)

        await model.submitPlanningDraftPlan()

        expectFailedPlanningReviewRecovery(model)
        #expect(model.state.stepRecords.contains { $0.id == "planning-review-planner-response-1" })
        #expect(
            model.state.stepRecords.contains {
                $0.id == "planning-review-planner-response-2" && $0.status == .failed
            })
        let recoveredInteraction = try #require(model.currentPlanningInteractionState)
        #expect(recoveredInteraction.latestResolvedOutput?.producerStepID == "planner-response-cycle-1")
        #expect(recoveredInteraction.draft == alternateValidPlanMarkdown)
        #expect(recoveredInteraction.outputCandidate.content == alternateValidPlanMarkdown)
        #expect(recoveredInteraction.canSubmit)
    }

    @Test
    func feedbackPersistenceFailureDoesNotEnterUserReviewPause() async throws {
        let projectURL = try makeTemporaryPlanningProject()
        let model = makePlanningReviewModel(
            projectURL: projectURL,
            backendAdapter: UniqueReviewerOutputHarnessBackendAdapter(),
            planArtifactMaterializer: FailingPlanningArtifactMaterializer(failure: .consolidatedFeedback)
        )
        var interaction = PlanningReviewWorkflowRunner.makeInitialInteractionState()
        interaction.updatePlanningDraftCandidate(content: validPlanMarkdown, source: .user)
        model.seedPlanningInteractionState(interaction)

        await model.submitPlanningDraftPlan()

        expectFailedPlanningReviewRecovery(model)
        #expect(
            reviewerOutput(model, id: "planning-review-reviewer-1-1")?
                .contains("Reviewer A unique feedback") == true)
        #expect(
            reviewerOutput(model, id: "planning-review-reviewer-1-2")?
                .contains("Reviewer B unique feedback") == true)
        #expect(
            model.state.stepRecords.contains {
                $0.id == "planning-review-consolidated-feedback-1" && $0.status == .failed
            })
        #expect(!model.state.stepRecords.contains { $0.id == "planning-review-planner-response-1" })
    }

    @Test
    func repeatedAcceptedDraftDoesNotStartAutomationAgain() async throws {
        let projectURL = try makeTemporaryPlanningProject()
        let project = WorkflowProject(url: projectURL, bookmarkData: nil)
        let store = PlanningPlanArtifactStore()
        var interaction = PlanningReviewWorkflowRunner.makeInitialInteractionState()
        interaction.updatePlanningDraftCandidate(content: validPlanMarkdown, source: .user)
        _ = try store.acceptDraftForReview(
            project: project,
            sessionID: interaction.sessionID,
            producerStepID: interaction.stepID,
            request: PlanningDraftAcceptanceRequest(
                candidate: interaction.outputCandidate,
                expectedRevision: interaction.outputCandidate.revision,
                idempotencyKey: WorkflowRunnerModel.acceptanceIdempotencyKey(for: interaction)
            )
        )
        let model = makePlanningReviewModel(projectURL: projectURL, planArtifactMaterializer: store)
        model.seedPlanningInteractionState(interaction)

        await model.submitPlanningDraftPlan()

        #expect(model.currentPlanningInteractionState?.submittedOutput == nil)
        #expect(model.state.activeWorkflowActivity == .waitingForInteraction)
        #expect(!model.state.stepRecords.contains { $0.id.hasPrefix("planning-review-reviewer-") })
        #expect(model.currentPlanningInteractionState?.errorMessage?.contains("already accepted") == true)
    }

    @Test
    func plannerResponsePlanPersistenceFailureStopsBeforeLaterCycles() async throws {
        let projectURL = try makeTemporaryPlanningProject()
        let model = makePlanningReviewModel(
            projectURL: projectURL,
            planArtifactMaterializer: FailingPlanningArtifactMaterializer(failure: .plannerResponsePlan)
        )
        var interaction = PlanningReviewWorkflowRunner.makeInitialInteractionState()
        interaction.updatePlanningDraftCandidate(content: validPlanMarkdown, source: .user)
        model.seedPlanningInteractionState(interaction)

        await model.submitPlanningDraftPlan()

        expectFailedPlanningReviewRecovery(model)
        #expect(model.state.stepRecords.contains { $0.id == "planning-review-consolidated-feedback-1" })
        #expect(
            model.state.stepRecords.contains {
                $0.id == "planning-review-planner-response-1" && $0.status == .failed
            })
        #expect(!model.state.stepRecords.contains { $0.id == "planning-review-reviewer-2-1" })
    }

    @Test
    func plannerResponseWithoutRevisedPlanFailsBeforeUserReview() async throws {
        let projectURL = try makeTemporaryPlanningProject()
        let model = makePlanningReviewModel(
            projectURL: projectURL,
            backendAdapter: NoPlanPlannerResponseHarnessBackendAdapter()
        )
        var interaction = PlanningReviewWorkflowRunner.makeInitialInteractionState()
        interaction.updatePlanningDraftCandidate(content: validPlanMarkdown, source: .user)
        model.seedPlanningInteractionState(interaction)

        await model.submitPlanningDraftPlan()

        expectFailedPlanningReviewRecovery(model)
        #expect(
            model.state.stepRecords.contains {
                $0.id == "planning-review-planner-response-1" && $0.status == .failed
            })
        #expect(!model.state.stepRecords.contains { $0.id == "planning-review-reviewer-2-1" })
    }

    private func submittedOutput(for interaction: PlanningInteractionState) -> InteractiveStepOutput {
        InteractiveStepOutput(
            producerStepID: interaction.stepID,
            artifact: InteractiveStepArtifact(
                title: "Submitted Plan",
                contentType: "text/markdown; artifact=plan",
                content: validPlanMarkdown,
                projectRelativePath: ".hephaestus/planning-review/session/plan.md"
            ),
            summary: "Submitted plan"
        )
    }

    private func reviewerOutput(_ model: WorkflowRunnerModel, id: WorkflowStepRecord.ID) -> String? {
        model.state.stepRecords.first { $0.id == id }?.outputPreview
    }

    private func expectFailedPlanningReviewRecovery(_ model: WorkflowRunnerModel) {
        #expect(model.currentPlanningInteractionState?.phase == .idle)
        #expect(model.currentPlanningInteractionState?.submittedOutput == nil)
        #expect(model.currentPlanningInteractionState?.canSubmit == true)
        #expect(!model.state.isRunning)
        #expect(model.state.activeWorkflowID == nil)
        #expect(model.state.activeWorkflowActivity == nil)
        #expect(model.state.lastRunSucceeded == false)
        #expect(model.currentPlanningInteractionState?.errorMessage?.contains("Automated review failed") == true)
        #expect(
            !model.state.stepRecords.contains {
                $0.id == "planning-review-interactive-user-review" && $0.status == .inProgress
            })
    }
}
