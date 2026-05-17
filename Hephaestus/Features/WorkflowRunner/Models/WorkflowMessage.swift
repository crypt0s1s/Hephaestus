import Foundation

nonisolated struct WorkflowMessage: Codable, Equatable, Identifiable {
    let id: String
    let runID: WorkflowRun.ID
    let kind: WorkflowMessageKind
    let producerStepID: String
    let createdAt: Date
    let payload: WorkflowMessagePayload
    let summary: String?

    init(
        id: String = UUID().uuidString,
        runID: WorkflowRun.ID,
        kind: WorkflowMessageKind,
        producerStepID: String,
        createdAt: Date = Date(),
        payload: WorkflowMessagePayload,
        summary: String?
    ) {
        self.id = id
        self.runID = runID
        self.kind = kind
        self.producerStepID = producerStepID
        self.createdAt = createdAt
        self.payload = payload
        self.summary = summary
    }
}

nonisolated enum WorkflowMessageKind: String, Codable, Equatable {
    case submittedPlan
    case currentPlan
    case reviewerFeedback
    case consolidatedReview
    case plannerResponse
}

nonisolated enum WorkflowMessagePayload: Codable, Equatable {
    case submittedPlan(SubmittedPlanMessagePayload)
    case currentPlan(CurrentPlanMessagePayload)
    case reviewerFeedback(ReviewerFeedbackMessagePayload)
    case consolidatedReview(ConsolidatedReviewMessagePayload)
    case plannerResponse(PlannerResponseMessagePayload)

    private enum CodingKeys: String, CodingKey {
        case type
        case payload
    }

    private enum PayloadType: String, Codable {
        case submittedPlan
        case currentPlan
        case reviewerFeedback
        case consolidatedReview
        case plannerResponse
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(PayloadType.self, forKey: .type) {
        case .submittedPlan:
            self = .submittedPlan(
                try container.decode(SubmittedPlanMessagePayload.self, forKey: .payload))
        case .currentPlan:
            self = .currentPlan(
                try container.decode(CurrentPlanMessagePayload.self, forKey: .payload))
        case .reviewerFeedback:
            self = .reviewerFeedback(
                try container.decode(ReviewerFeedbackMessagePayload.self, forKey: .payload))
        case .consolidatedReview:
            self = .consolidatedReview(
                try container.decode(ConsolidatedReviewMessagePayload.self, forKey: .payload))
        case .plannerResponse:
            self = .plannerResponse(
                try container.decode(PlannerResponseMessagePayload.self, forKey: .payload))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .submittedPlan(let payload):
            try container.encode(PayloadType.submittedPlan, forKey: .type)
            try container.encode(payload, forKey: .payload)
        case .currentPlan(let payload):
            try container.encode(PayloadType.currentPlan, forKey: .type)
            try container.encode(payload, forKey: .payload)
        case .reviewerFeedback(let payload):
            try container.encode(PayloadType.reviewerFeedback, forKey: .type)
            try container.encode(payload, forKey: .payload)
        case .consolidatedReview(let payload):
            try container.encode(PayloadType.consolidatedReview, forKey: .type)
            try container.encode(payload, forKey: .payload)
        case .plannerResponse(let payload):
            try container.encode(PayloadType.plannerResponse, forKey: .type)
            try container.encode(payload, forKey: .payload)
        }
    }
}

nonisolated struct SubmittedPlanMessagePayload: Codable, Equatable {
    var title: String
    var contentType: String
    var content: String
    var projectRelativePath: String?
}

nonisolated struct CurrentPlanMessagePayload: Codable, Equatable {
    var sourceMessageID: WorkflowMessage.ID
    var cycle: Int
    var contentType: String
    var content: String
    var projectRelativePath: String?
}

nonisolated struct ReviewerFeedbackMessagePayload: Codable, Equatable {
    var reviewedMessageID: WorkflowMessage.ID
    var cycle: Int
    var reviewerName: String
    var feedback: String
    var exitCode: Int32
}

nonisolated struct ConsolidatedReviewMessagePayload: Codable, Equatable {
    var reviewedMessageID: WorkflowMessage.ID
    var cycle: Int
    var reviewerMessageIDs: [WorkflowMessage.ID]
    var failedReviewers: [FailedReviewerMessagePayload]
    var feedback: String
}

nonisolated struct FailedReviewerMessagePayload: Codable, Equatable {
    var reviewerName: String
    var stepID: String
    var exitCode: Int32
    var details: String
}

nonisolated struct PlannerResponseMessagePayload: Codable, Equatable {
    var reviewMessageID: WorkflowMessage.ID
    var cycle: Int
    var response: String
    var exitCode: Int32
}

nonisolated extension WorkflowMessage {
    var submittedPlan: SubmittedPlanMessagePayload? {
        guard case .submittedPlan(let payload) = payload else { return nil }
        return payload
    }

    var currentPlan: CurrentPlanMessagePayload? {
        guard case .currentPlan(let payload) = payload else { return nil }
        return payload
    }

    var planContent: String? {
        switch payload {
        case .submittedPlan(let payload):
            payload.content
        case .currentPlan(let payload):
            payload.content
        case .plannerResponse(let payload):
            payload.response
        case .reviewerFeedback,
            .consolidatedReview:
            nil
        }
    }

    var planProjectRelativePath: String? {
        switch payload {
        case .submittedPlan(let payload):
            payload.projectRelativePath
        case .currentPlan(let payload):
            payload.projectRelativePath
        case .reviewerFeedback,
            .consolidatedReview,
            .plannerResponse:
            nil
        }
    }

    var consolidatedReview: ConsolidatedReviewMessagePayload? {
        guard case .consolidatedReview(let payload) = payload else { return nil }
        return payload
    }

    var reviewerFeedback: ReviewerFeedbackMessagePayload? {
        guard case .reviewerFeedback(let payload) = payload else { return nil }
        return payload
    }

    var plannerResponse: PlannerResponseMessagePayload? {
        guard case .plannerResponse(let payload) = payload else { return nil }
        return payload
    }
}
