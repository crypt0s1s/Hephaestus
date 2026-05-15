import Foundation

struct PlanningReviewAutomationRun {
    let sessionID: String
    var timeline: String
    var records: [WorkflowStepRecord]
    var planPath: String
    var currentPlanOutput: InteractiveStepOutput?
    var relatedOutputs: [InteractiveStepOutput] = []
    var terminalFailureRecordID: WorkflowStepRecord.ID?
}

struct PlanningReviewAutomationResult {
    let processResult: ProcessResult
    let run: PlanningReviewAutomationRun
}

struct PlanningReviewerRun {
    let name: String
    let prompt: String
    let result: ProcessResult
}

struct PlanningReviewCycleFeedback {
    let consolidatedRecord: WorkflowStepRecord
    let consolidatedOutput: InteractiveStepOutput
    let successfulReviewerResults: [PlanningReviewerRun]
}

struct PlanningPlannerResponseRun {
    let record: WorkflowStepRecord
    let revisedPlanOutput: InteractiveStepOutput?
}

extension WorkflowStepRecord {
    func plannerResponseRun(revisedPlanOutput: InteractiveStepOutput?) -> PlanningPlannerResponseRun {
        PlanningPlannerResponseRun(record: self, revisedPlanOutput: revisedPlanOutput)
    }
}
