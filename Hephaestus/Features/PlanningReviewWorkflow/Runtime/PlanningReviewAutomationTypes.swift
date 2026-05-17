import Foundation

struct PlanningReviewPrototypeAutomationRun {
    var timeline: String
    var records: [WorkflowStepRecord]
    var planPath: String
    var workflowMessages: [WorkflowMessage] = []
    var currentPlanMessage: WorkflowMessage?
    var terminalFailure: String?
}

struct PlanningReviewerRun {
    let name: String
    let stepID: String
    let prompt: String
    let result: ProcessResult
}

struct PlanningReviewCycleResult {
    let records: [WorkflowStepRecord]
    let workflowMessages: [WorkflowMessage]
    let consolidatedMessage: WorkflowMessage?
}
