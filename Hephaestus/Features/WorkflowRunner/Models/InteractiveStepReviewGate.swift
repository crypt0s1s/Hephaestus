import Foundation

struct InteractiveStepOutputCandidate: Equatable {
    enum Source: Equatable {
        case empty
        case agent
        case user
    }

    let outputID: String
    var contentType: String
    var content: String
    var source: Source
    var revision: Int

    init(
        outputID: String,
        contentType: String,
        content: String = "",
        source: Source = .empty,
        revision: Int = 0
    ) {
        self.outputID = outputID
        self.contentType = contentType
        self.content = content
        self.source = source
        self.revision = revision
    }
}

enum InteractiveStepGateState: Equatable {
    case interacting
    case needsOutput(InteractiveRequiredOutputIssue)
    case awaitingUserReview(InteractiveReadyOutput)
    case accepted(InteractiveOutputAcceptanceRecord)

    var canAcceptOutputForReview: Bool {
        if case .awaitingUserReview = self {
            return true
        }
        return false
    }

    var isAccepted: Bool {
        if case .accepted = self {
            return true
        }
        return false
    }
}

struct InteractiveRequiredOutputIssue: Equatable {
    enum Reason: Equatable {
        case missing
        case invalid
    }

    let outputID: String
    let title: String
    let reason: Reason
    let message: String
    let recoveryActions: [InteractiveStepRecoveryAction]
}

enum InteractiveStepRecoveryAction: Hashable {
    case requestAgentRevision(outputID: String)
    case editOutput(outputID: String)
    case pasteOutput(outputID: String)
}

struct InteractiveReadyOutput: Equatable {
    let outputID: String
    let candidateRevision: Int
}

struct InteractiveOutputAcceptanceRecord: Equatable {
    let outputID: String
    let acceptedRevision: Int
    let contentHash: String
    let acceptedAt: Date
    let idempotencyKey: String
}
