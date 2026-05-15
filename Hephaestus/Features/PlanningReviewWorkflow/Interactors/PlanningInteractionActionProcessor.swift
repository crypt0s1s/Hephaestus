import Foundation

@MainActor
struct PlanningInteractionActionProcessor {
    enum Action {
        case changeNote(String)
        case tapAddNote
        case changeDraft(String)
        case tapAcceptDraftForReview
        case tapAcceptReviewedWorkflow
        case tapRequestAnotherCycle
        case tapContinuePlanning
        case chooseRecovery(InteractiveStepRecoveryAction)
        case tapCopyArtifactPath(String)
    }

    let model: WorkflowRunnerModel
    let artifactPathCopier: any PlanningReviewArtifactPathCopying

    init(model: WorkflowRunnerModel) {
        self.init(
            model: model,
            artifactPathCopier: PasteboardPlanningReviewArtifactPathCopier()
        )
    }

    init(
        model: WorkflowRunnerModel,
        artifactPathCopier: any PlanningReviewArtifactPathCopying
    ) {
        self.model = model
        self.artifactPathCopier = artifactPathCopier
    }

    func handle(_ action: Action) {
        switch action {
        case .changeNote(let note):
            model.updatePlanningDraftMessage(note)
        case .tapAddNote:
            Task { await model.sendPlanningMessage() }
        case .changeDraft(let draft):
            model.updatePlanningDraftPlan(draft)
        case .tapAcceptDraftForReview:
            Task { await model.submitPlanningDraftPlan() }
        case .tapAcceptReviewedWorkflow:
            model.acceptPlanningReview()
        case .tapRequestAnotherCycle:
            Task { await model.requestAnotherPlanningReviewCycle() }
        case .tapContinuePlanning:
            model.continuePlanningReview()
        case .chooseRecovery(let recoveryAction):
            model.choosePlanningRecoveryAction(recoveryAction)
        case .tapCopyArtifactPath(let path):
            copyArtifactPath(path)
        }
    }

    private func copyArtifactPath(_ path: String) {
        artifactPathCopier.copyArtifactPath(path)
        model.notePlanningReviewArtifactPathCopied(path)
    }
}
