import Foundation

public enum WorkflowState: Hashable, Codable, Sendable {
    case drafting
    case running
    case waitingForApproval
    case reviewing
    case completed
    case failed
}
