import Foundation

struct PlanningReviewPrototypeTurnSettlement {
    private let artifactStore: PlanningPlanArtifactMaterializing

    init(artifactStore: PlanningPlanArtifactMaterializing) {
        self.artifactStore = artifactStore
    }

    func settle(
        draftArtifact: PlanningDraftArtifact,
        interaction: PlanningInteractionState
    ) -> PlanningReviewTurnSettlement {
        do {
            let loadedDraft = try artifactStore.loadDraftArtifact(draftArtifact)
            return PlanningReviewTurnSettlement(
                proposedPlan: loadedDraft.content,
                errorMessage: nil,
                notice: Self.generatedDraftNotice(draftPath: draftArtifact.relativePath)
            )
        } catch {
            let shouldRequireOutput = interaction.outputCandidate.content
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .isEmpty
            return PlanningReviewTurnSettlement(
                proposedPlan: nil,
                errorMessage: "Planner draft artifact was not reviewable: \(error.localizedDescription)",
                notice: nil,
                shouldRequireOutput: shouldRequireOutput
            )
        }
    }
}

extension PlanningReviewPrototypeTurnSettlement {
    static func generatedDraftNotice(draftPath: String) -> String {
        "Hephaestus wrote the validated planner draft to \(draftPath). Review it, then accept it for automated review."
    }
}

struct PlanningReviewTurnSettlement: Equatable {
    let proposedPlan: String?
    let errorMessage: String?
    let notice: String?
    var shouldRequireOutput = false
}
