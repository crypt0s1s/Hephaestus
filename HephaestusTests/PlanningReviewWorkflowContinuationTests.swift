import Foundation
import Testing

@testable import Hephaestus

@MainActor
struct PlanningReviewWorkflowContinuationTests {
    @Test
    func continuePlanningReviewReopensDraftFromLatestReviewedPlan() async throws {
        let fixture = try await makeCompletedReviewFixture()
        let latestPlan = try #require(
            fixture.model.state.planningInteraction?.latestResolvedOutput?.artifact.content
        )

        fixture.model.continuePlanningReview()

        let interaction = try #require(fixture.model.state.planningInteraction)
        #expect(interaction.phase == .idle)
        #expect(interaction.submittedOutput == nil)
        #expect(interaction.draft == latestPlan)
        #expect(fixture.model.state.activeWorkflowActivity == .waitingForInteraction)
    }

    @Test
    func requestAnotherPlanningReviewCycleAppendsNextCycleArtifacts() async throws {
        let fixture = try await makeCompletedReviewFixture()

        await fixture.model.requestAnotherPlanningReviewCycle()

        let interaction = try #require(fixture.model.state.planningInteraction)
        #expect(interaction.phase == .completed)
        #expect(interaction.latestResolvedOutput?.producerStepID == "planner-response-cycle-3")
        #expect(interaction.relatedOutputs.contains { $0.producerStepID == "automated-review-cycle-3" })
        #expect(fixture.model.state.stepRecords.contains { $0.id == "planning-review-planner-response-3" })
    }

    private func makeCompletedReviewFixture() async throws -> CompletedPlanningReviewFixture {
        let projectURL = try makeTemporaryPlanningProject()
        let model = makePlanningReviewModel(projectURL: projectURL)
        var interaction = PlanningReviewWorkflowRunner.makeInitialInteractionState()
        interaction.updatePlanningDraftCandidate(content: validPlanMarkdown, source: .user)
        model.update { $0.planningInteraction = interaction }

        await model.submitPlanningDraftPlan()

        let completedInteraction = try #require(model.state.planningInteraction)
        #expect(completedInteraction.phase == .completed)
        return CompletedPlanningReviewFixture(projectURL: projectURL, model: model)
    }
}

private struct CompletedPlanningReviewFixture {
    let projectURL: URL
    let model: WorkflowRunnerModel
}
