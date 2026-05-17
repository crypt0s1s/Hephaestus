import Foundation

struct WorkflowInteractiveActivity: Identifiable, Equatable {
    var workflowID: WorkflowDefinition.ID
    var activityID: String
    var stepID: String
    var sessionID: String
    var rendererID: String
    var title: String
    var subtitle: String
    var status: WorkflowInteractiveStatus
    var primaryUserAction: WorkflowInteractiveUserAction?

    var id: String {
        "\(workflowID):\(activityID):\(sessionID)"
    }
}

enum WorkflowInteractiveStatus: Equatable {
    case waitingForInput
    case waitingForOutputReview
    case runningAutomation
    case waitingForFinalReview
    case recoverableFailure
    case accepted
    case blocked(String)
}

struct WorkflowInteractiveUserAction: Equatable {
    var title: String
    var systemImage: String?
    var accessibilityIdentifier: String
}
