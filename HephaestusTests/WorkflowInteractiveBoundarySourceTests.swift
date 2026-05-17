import Foundation
import Testing

@testable import Hephaestus

@MainActor
struct WorkflowInteractiveBoundarySourceTests {
    @Test
    func workflowRunnerStateStoresGenericInteractiveActivityOnly() throws {
        let contents = try sourceFile(
            "Hephaestus/Features/WorkflowRunner/Models/WorkflowRunnerState.swift")

        for forbiddenToken in [
            "PlanningInteractionState",
            "planningInteraction",
            "PlanningReviewWorkflowRunner",
        ] {
            #expect(!contents.contains(forbiddenToken))
        }
    }

    @Test
    func genericRunnerModelAndViewDoNotReferencePlanningFeatureTypes() throws {
        let genericRunnerFiles = [
            "Hephaestus/Features/WorkflowRunner/Interactors/WorkflowRunnerModel.swift",
            "Hephaestus/Features/WorkflowRunner/Views/WorkflowRunnerView.swift",
        ]
        let forbiddenTokens = [
            "PlanningReviewServices",
            "PlanningInteractionState",
            "PlanningInteractionView",
            "PlanningInteractionActionProcessor",
            "PlanningReviewWorkflowRunner",
            "PlanningPresentationStyle",
        ]

        for file in genericRunnerFiles {
            let contents = try sourceFile(file)
            for token in forbiddenTokens {
                #expect(!contents.contains(token))
            }
        }
    }

    @Test
    func workflowRunnerStateCanHoldRendererOwnedActivityMetadata() {
        let activity = WorkflowInteractiveActivity(
            workflowID: "sample-workflow",
            activityID: "sample-pause",
            stepID: "pause-step",
            sessionID: "session-1",
            rendererID: "sample-renderer",
            title: "Sample Pause",
            subtitle: "Waiting for input.",
            status: .waitingForInput,
            primaryUserAction: WorkflowInteractiveUserAction(
                title: "Submit",
                systemImage: "paperplane",
                accessibilityIdentifier: "sample.submit"
            )
        )
        var state = WorkflowRunnerState()

        state.interactiveActivity = activity

        #expect(state.interactiveActivity == activity)
        #expect(state.interactiveActivity?.rendererID == "sample-renderer")
        #expect(state.interactiveActivity?.primaryUserAction?.accessibilityIdentifier == "sample.submit")
    }

    private func sourceFile(_ relativePath: String) throws -> String {
        try String(
            contentsOf: repositoryRoot.appendingPathComponent(relativePath),
            encoding: .utf8
        )
    }

    private var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
