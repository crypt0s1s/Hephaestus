import Foundation

struct BuiltInWorkflowRunContext {
  let project: WorkflowProject
  let inputValues: [String: String]
  let progress: WorkflowProgressHandler?
}

enum BuiltInWorkflowRunResult {
  case completed(ProcessResult)
  case waiting(WorkflowRunProgress, output: String)
}

protocol BuiltInWorkflow {
  var definition: WorkflowDefinition { get }

  func run(context: BuiltInWorkflowRunContext) async -> BuiltInWorkflowRunResult
}

struct BuiltInWorkflowCatalog {
  let workflows: [any BuiltInWorkflow]

  var definitions: [WorkflowDefinition] {
    workflows.map(\.definition)
  }

  func workflow(id: WorkflowDefinition.ID) -> (any BuiltInWorkflow)? {
    workflows.first { $0.definition.id == id }
  }

  static func production(processRunner: WorkflowProcessRunning = DefaultProcessRunner())
    -> BuiltInWorkflowCatalog {
    let headlessRunner = HeadlessCodexWorkflowRunner(processRunner: processRunner)
    return BuiltInWorkflowCatalog(
      workflows: [
        HelloWorldBuiltInWorkflow(runner: headlessRunner),
        ImplementationReviewBuiltInWorkflow(runner: headlessRunner),
        PlanningReviewWorkflowRunner(),
      ]
    )
  }
}
