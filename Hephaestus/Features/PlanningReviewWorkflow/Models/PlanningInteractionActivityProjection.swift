import Foundation

enum PlanningInteractionActivityProjection {
    static let rendererID = "planning-review"
    static let submitPlanActivityID = "submit-plan"
    static let automationActivityID = "automated-review-cycles"
    static let userReviewActivityID = "interactive-user-review"
}

extension PlanningInteractionState {
    var interactiveActivityProjection: WorkflowInteractiveActivity {
        WorkflowInteractiveActivity(
            workflowID: workflowID,
            activityID: projectedActivityID,
            stepID: stepID,
            sessionID: sessionID,
            rendererID: PlanningInteractionActivityProjection.rendererID,
            title: projectedTitle,
            subtitle: projectedSubtitle,
            status: projectedStatus,
            primaryUserAction: projectedPrimaryUserAction
        )
    }

    private var projectedActivityID: String {
        switch phase {
        case .materializing:
            return PlanningInteractionActivityProjection.submitPlanActivityID
        case .reviewing:
            return PlanningInteractionActivityProjection.automationActivityID
        case .completed, .accepted:
            return PlanningInteractionActivityProjection.userReviewActivityID
        case .idle, .sending:
            return stepID
        }
    }

    private var projectedTitle: String {
        switch projectedStatus {
        case .waitingForFinalReview:
            return "Interactive user review"
        case .runningAutomation:
            return phase == .reviewing ? "Automated review cycles" : title
        case .accepted:
            return "Planning review accepted"
        case .waitingForInput, .waitingForOutputReview, .recoverableFailure, .blocked:
            return title
        }
    }

    private var projectedSubtitle: String {
        switch projectedStatus {
        case .waitingForInput:
            return "Waiting for a reviewable draft plan."
        case .waitingForOutputReview:
            return "Review this draft before starting automated review."
        case .runningAutomation:
            return phase == .reviewing
                ? "Reviewer and planner-response cycles are running."
                : "The workflow is processing the draft plan."
        case .waitingForFinalReview:
            return "Automated cycles finished. Review the latest plan before accepting it."
        case .recoverableFailure:
            return errorMessage ?? "The workflow needs user recovery before it can continue."
        case .accepted:
            return "The submitted plan has been accepted."
        case .blocked(let message):
            return message
        }
    }

    private var projectedStatus: WorkflowInteractiveStatus {
        switch phase {
        case .idle:
            if errorMessage != nil {
                return .recoverableFailure
            }
            return gateState.canAcceptOutputForReview ? .waitingForOutputReview : .waitingForInput
        case .sending, .materializing, .reviewing:
            return .runningAutomation
        case .completed:
            return .waitingForFinalReview
        case .accepted:
            return .accepted
        }
    }

    private var projectedPrimaryUserAction: WorkflowInteractiveUserAction? {
        switch projectedStatus {
        case .waitingForOutputReview, .recoverableFailure:
            return WorkflowInteractiveUserAction(
                title: "Submit Plan",
                systemImage: "tray.and.arrow.up.fill",
                accessibilityIdentifier: "planning.submitPlan"
            )
        case .waitingForFinalReview:
            return WorkflowInteractiveUserAction(
                title: "Accept Plan",
                systemImage: "checkmark.circle.fill",
                accessibilityIdentifier: "planning.acceptReview"
            )
        case .waitingForInput, .runningAutomation, .accepted, .blocked:
            return nil
        }
    }
}
