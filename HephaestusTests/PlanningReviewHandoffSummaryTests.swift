import Foundation
import Testing

@testable import Hephaestus

struct PlanningReviewHandoffSummaryTests {
    @Test
    func latestReviewedPlanUsesLatestResolvedOutputWhenItAlsoAppearsInRelatedOutputs() throws {
        let sessionID = "session"
        let submittedOutput = makeOutput(
            id: "submitted",
            producerStepID: "interactive-planning",
            path: PlanningPlanArtifactPolicy.relativePlanPath(sessionID: sessionID)
        )
        let cycleOnePlan = makeOutput(id: "cycle-1", producerStepID: "planner-response-cycle-1", cycle: 1)
        let cycleTwoPlan = makeOutput(id: "cycle-2", producerStepID: "planner-response-cycle-2", cycle: 2)
        var state = PlanningReviewWorkflowRunner.makeInitialInteractionState()
        state.phase = .completed
        state.submittedOutput = submittedOutput
        state.relatedOutputs = [
            submittedOutput,
            makeFeedbackOutput(cycle: 1),
            cycleOnePlan,
            makeFeedbackOutput(cycle: 2),
            cycleTwoPlan,
        ]
        state.latestResolvedOutput = cycleTwoPlan

        let summary = try #require(state.reviewHandoffSummary)

        #expect(summary.latestArtifact?.output.id == cycleTwoPlan.id)
        #expect(summary.latestArtifact?.copyPath == cycleTwoPlan.artifact.projectRelativePath)
        #expect(summary.cycles.first { $0.number == 2 }?.plan?.output.id == cycleTwoPlan.id)
        #expect(!summary.markers.map(\.identifier).contains("planning.latestReviewedPlan"))
    }

    @Test
    func acceptedHandoffKeepsOriginalCyclePlanHistoryWhenLatestOutputIsFinalized() throws {
        let sessionID = "session"
        let cycleOnePlan = makeOutput(id: "cycle-1", producerStepID: "planner-response-cycle-1", cycle: 1)
        let cycleTwoPlan = makeOutput(id: "cycle-2", producerStepID: "planner-response-cycle-2", cycle: 2)
        let finalizedCycleTwoPlan = makeOutput(
            id: cycleTwoPlan.id,
            producerStepID: cycleTwoPlan.producerStepID,
            path: PlanningPlanArtifactPolicy.relativePlanPath(sessionID: sessionID)
        )
        var state = PlanningReviewWorkflowRunner.makeInitialInteractionState()
        state.phase = .accepted
        state.relatedOutputs = [
            makeFeedbackOutput(cycle: 1),
            cycleOnePlan,
            makeFeedbackOutput(cycle: 2),
            cycleTwoPlan,
        ]
        state.latestResolvedOutput = finalizedCycleTwoPlan

        let summary = try #require(state.reviewHandoffSummary)

        #expect(
            summary.latestArtifact?.output.artifact.projectRelativePath
                == finalizedCycleTwoPlan.artifact.projectRelativePath)
        #expect(summary.latestArtifact?.title == "Final accepted plan")
        #expect(summary.cycles.first { $0.number == 2 }?.plan?.output.artifact.projectRelativePath
            == cycleTwoPlan.artifact.projectRelativePath)
        #expect(summary.cycles.map(\.number) == [1, 2])
    }

    private func makeOutput(
        id: String,
        producerStepID: String,
        cycle: Int? = nil,
        path: String? = nil
    ) -> InteractiveStepOutput {
        InteractiveStepOutput(
            id: id,
            producerStepID: producerStepID,
            artifact: InteractiveStepArtifact(
                title: "Plan",
                contentType: PlanningPlanArtifactPolicy.contentType,
                content: validPlanMarkdown,
                projectRelativePath: path
                    ?? PlanningPlanArtifactPolicy.plannerResponsePlanPath(sessionID: "session", cycle: cycle ?? 1)
            ),
            summary: "Plan \(id)"
        )
    }

    private func makeFeedbackOutput(cycle: Int) -> InteractiveStepOutput {
        InteractiveStepOutput(
            id: "feedback-\(cycle)",
            producerStepID: "automated-review-cycle-\(cycle)",
            artifact: InteractiveStepArtifact(
                title: "Review feedback",
                contentType: "text/markdown; artifact=consolidated-review",
                content: "pass",
                projectRelativePath: PlanningPlanArtifactPolicy.consolidatedFeedbackPath(
                    sessionID: "session",
                    cycle: cycle
                )
            ),
            summary: "Feedback \(cycle)"
        )
    }
}
