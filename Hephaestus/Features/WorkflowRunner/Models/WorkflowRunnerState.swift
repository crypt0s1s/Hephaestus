import Foundation

struct WorkflowRunnerState: Equatable {
    var projects: [WorkflowProject] = []
    var selectedProjectID: WorkflowProject.ID?
    var branchNames: [WorkflowProject.ID: String] = [:]
    var workflows: [WorkflowDefinition] = []
    var expandedWorkflowIDs: Set<WorkflowDefinition.ID> = [
        ImplementationReviewBuiltInWorkflow.id,
        PlanningReviewWorkflowRunner.id,
    ]
    var implementationPlanPath = ""
    var implementationBuildCommand = "swift build"
    var externalWorkflowInputValues: [WorkflowDefinition.ID: [String: String]] = [:]
    var isRunning = false
    var activeWorkflowID: WorkflowDefinition.ID?
    var statusMessage: String?
    var timelineOutput = ""
    var stepRecords: [WorkflowStepRecord] = []
    var output = ""
    var debugLogURL: URL?
    var lastRunSucceeded: Bool?
    var lastRunWorkflowID: WorkflowDefinition.ID?
    var planningInteraction: WorkflowInteractionState?

    var selectedProject: WorkflowProject? {
        guard let selectedProjectID else { return nil }
        return projects.first { $0.id == selectedProjectID }
    }

    func branchName(for project: WorkflowProject) -> String? {
        branchNames[project.id]
    }

    func isWorkflowExpanded(_ workflow: WorkflowDefinition) -> Bool {
        expandedWorkflowIDs.contains(workflow.id)
    }
}
