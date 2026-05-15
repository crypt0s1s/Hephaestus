import Foundation

enum PlanningInteractionOutputContract {
    static let draftPlanOutputID = "draft-plan"
    static let draftPlanContentType = "text/markdown; artifact=plan"
}

enum PlanningInteractionGateEvaluator {
    static func evaluate(candidate: InteractiveStepOutputCandidate) -> InteractiveStepGateState {
        let trimmedContent = candidate.content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedContent.isEmpty else {
            return .needsOutput(
                InteractiveRequiredOutputIssue(
                    outputID: candidate.outputID,
                    title: "Draft Plan",
                    reason: .missing,
                    message: "A draft plan is required before automated review can start.",
                    recoveryActions: [
                        .requestAgentRevision(outputID: candidate.outputID),
                        .editOutput(outputID: candidate.outputID),
                        .pasteOutput(outputID: candidate.outputID),
                    ]
                ))
        }

        let missingSections = PlanningPlanArtifactPolicy.missingRequiredSections(in: trimmedContent)
        guard missingSections.isEmpty else {
            return .needsOutput(
                InteractiveRequiredOutputIssue(
                    outputID: candidate.outputID,
                    title: "Draft Plan",
                    reason: .invalid,
                    message: "Plan is missing required sections: \(missingSections.joined(separator: ", "))",
                    recoveryActions: [
                        .requestAgentRevision(outputID: candidate.outputID),
                        .editOutput(outputID: candidate.outputID),
                        .pasteOutput(outputID: candidate.outputID),
                    ]
                ))
        }

        return .awaitingUserReview(
            InteractiveReadyOutput(
                outputID: candidate.outputID,
                candidateRevision: candidate.revision
            ))
    }
}

extension PlanningInteractionState {
    static func makePlanningDraftCandidate() -> InteractiveStepOutputCandidate {
        InteractiveStepOutputCandidate(
            outputID: PlanningInteractionOutputContract.draftPlanOutputID,
            contentType: PlanningInteractionOutputContract.draftPlanContentType
        )
    }

    mutating func updatePlanningDraftCandidate(
        content: String,
        source: InteractiveStepOutputCandidate.Source
    ) {
        guard !gateState.isAccepted else { return }
        let nextRevision = content == outputCandidate.content
            ? outputCandidate.revision
            : outputCandidate.revision + 1
        draft = content
        outputCandidate = InteractiveStepOutputCandidate(
            outputID: PlanningInteractionOutputContract.draftPlanOutputID,
            contentType: PlanningInteractionOutputContract.draftPlanContentType,
            content: content,
            source: content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .empty : source,
            revision: nextRevision
        )
        gateState = PlanningInteractionGateEvaluator.evaluate(candidate: outputCandidate)
    }

    mutating func acceptPlanningDraftCandidate(_ record: InteractiveOutputAcceptanceRecord) {
        gateState = .accepted(record)
    }
}
