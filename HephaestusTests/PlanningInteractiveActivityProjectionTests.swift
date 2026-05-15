import Foundation
import Testing

@testable import Hephaestus

@MainActor
struct PlanningInteractiveActivityProjectionTests {
    @Test
    func emptyInitialPlanningProjectsWaitingForInput() {
        let interaction = PlanningReviewWorkflowRunner.makeInitialInteractionState()
        let activity = interaction.interactiveActivityProjection

        #expect(activity.workflowID == PlanningReviewWorkflowRunner.id)
        #expect(activity.activityID == "interactive-planning")
        #expect(activity.stepID == "interactive-planning")
        #expect(activity.sessionID == interaction.sessionID)
        #expect(activity.rendererID == PlanningInteractionActivityProjection.rendererID)
        #expect(activity.status == .waitingForInput)
        #expect(activity.primaryUserAction == nil)
    }

    @Test
    func reviewableDraftProjectsWaitingForOutputReview() {
        var interaction = PlanningReviewWorkflowRunner.makeInitialInteractionState()
        interaction.updatePlanningDraftCandidate(content: validPlanMarkdown, source: .user)

        let activity = interaction.interactiveActivityProjection

        #expect(activity.activityID == "interactive-planning")
        #expect(activity.status == .waitingForOutputReview)
        #expect(activity.primaryUserAction?.title == "Submit Plan")
        #expect(activity.primaryUserAction?.accessibilityIdentifier == "planning.submitPlan")
    }

    @Test
    func processingPhasesProjectRunningActivities() {
        expectActivity(
            for: .sending,
            expectedActivityID: "interactive-planning",
            expectedStatus: .runningAutomation
        )
        expectActivity(
            for: .materializing,
            expectedActivityID: PlanningInteractionActivityProjection.submitPlanActivityID,
            expectedStatus: .runningAutomation
        )
        expectActivity(
            for: .reviewing,
            expectedActivityID: PlanningInteractionActivityProjection.automationActivityID,
            expectedStatus: .runningAutomation
        )
    }

    @Test
    func finalReviewProjectsDistinctUserReviewActivity() {
        var interaction = PlanningReviewWorkflowRunner.makeInitialInteractionState()
        interaction.phase = .completed

        let activity = interaction.interactiveActivityProjection

        #expect(activity.activityID == PlanningInteractionActivityProjection.userReviewActivityID)
        #expect(activity.stepID == "interactive-planning")
        #expect(activity.status == .waitingForFinalReview)
        #expect(activity.primaryUserAction?.title == "Accept Plan")
        #expect(activity.primaryUserAction?.accessibilityIdentifier == "planning.acceptReview")
    }

    @Test
    func recoverableFailureProjectsRecoveryStatus() {
        var interaction = PlanningReviewWorkflowRunner.makeInitialInteractionState()
        interaction.updatePlanningDraftCandidate(content: validPlanMarkdown, source: .user)
        interaction.errorMessage = "Automated review failed. Update the draft."

        let activity = interaction.interactiveActivityProjection

        #expect(activity.status == .recoverableFailure)
        #expect(activity.subtitle == "Automated review failed. Update the draft.")
        #expect(activity.primaryUserAction?.accessibilityIdentifier == "planning.submitPlan")
    }

    @Test
    func runnerStateCanLookupPlanningSessionByID() throws {
        let projectURL = try makeTemporaryPlanningProject()
        let model = makePlanningReviewModel(projectURL: projectURL)
        var interaction = PlanningReviewWorkflowRunner.makeInitialInteractionState()
        interaction.updatePlanningDraftCandidate(content: validPlanMarkdown, source: .user)

        model.seedPlanningInteractionState(interaction)

        #expect(model.planningInteractionState(sessionID: interaction.sessionID) == interaction)
        #expect(model.planningInteractionState(sessionID: "missing") == nil)
        #expect(model.state.interactiveActivity == interaction.interactiveActivityProjection)
    }

    private func expectActivity(
        for phase: PlanningInteractionState.Phase,
        expectedActivityID: String,
        expectedStatus: WorkflowInteractiveStatus
    ) {
        var interaction = PlanningReviewWorkflowRunner.makeInitialInteractionState()
        interaction.phase = phase

        let activity = interaction.interactiveActivityProjection

        #expect(activity.activityID == expectedActivityID)
        #expect(activity.status == expectedStatus)
        #expect(activity.primaryUserAction == nil)
    }
}
