import Foundation

@MainActor
extension WorkflowRunnerModel {
    func applyCompletedPlannerTurn(draftArtifact: PlanningDraftArtifact) {
        guard let interaction = currentPlanningInteractionState else { return }
        let settlement = PlanningReviewPrototypeTurnSettlement(
            artifactStore: planningReviewServices.planArtifactMaterializer
        ).settle(
            draftArtifact: draftArtifact,
            interaction: interaction
        )
        updateInteraction {
            if let plan = settlement.proposedPlan {
                $0.updatePlanningDraftCandidate(content: plan, source: .agent)
                if let notice = settlement.notice {
                    $0.entries.append(PlanningInteractionEntry(source: .system, text: notice))
                }
            } else if settlement.shouldRequireOutput {
                $0.gateState = PlanningInteractionGateEvaluator.evaluate(candidate: $0.outputCandidate)
            }
            $0.phase = .idle
            $0.errorMessage = settlement.errorMessage
        }
    }
}
