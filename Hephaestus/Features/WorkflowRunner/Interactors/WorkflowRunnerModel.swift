import Combine
import Foundation
import SwiftUI

@MainActor
final class WorkflowRunnerModel: ObservableObject {
  @Published private(set) var state: WorkflowRunnerState

  private let projectStore: ProjectStore
  private let projectPicker: ProjectPicker
  private let branchReader: GitBranchReader
  private let builtInWorkflowCatalog: BuiltInWorkflowCatalog
  private let externalWorkflowDiscovery: ExternalWorkflowDiscovery
  private let externalWorkflowRunner: ExternalWorkflowRunner
  private let environment: [String: String]

  convenience init() {
    self.init(
      projectStore: UserDefaultsProjectStore(),
      projectPicker: NSOpenPanelProjectPicker(),
      branchReader: GitBranchReader(),
      builtInWorkflowCatalog: .production(),
      externalWorkflowDiscovery: ExternalWorkflowDiscovery(),
      externalWorkflowRunner: ExternalWorkflowRunner(),
      environment: ProcessInfo.processInfo.environment
    )
  }

  init(
    projectStore: ProjectStore,
    projectPicker: ProjectPicker,
    branchReader: GitBranchReader,
    builtInWorkflowCatalog: BuiltInWorkflowCatalog,
    externalWorkflowDiscovery: ExternalWorkflowDiscovery,
    externalWorkflowRunner: ExternalWorkflowRunner,
    environment: [String: String]
  ) {
    self.projectStore = projectStore
    self.projectPicker = projectPicker
    self.branchReader = branchReader
    self.builtInWorkflowCatalog = builtInWorkflowCatalog
    self.externalWorkflowDiscovery = externalWorkflowDiscovery
    self.externalWorkflowRunner = externalWorkflowRunner
    self.environment = environment

    let snapshot = projectStore.load()
    var initialState = WorkflowRunnerState(
      projects: snapshot.projects,
      selectedProjectID: snapshot.selectedProjectID
    )
    initialState.workflows = builtInWorkflowCatalog.definitions
    if let environmentProject = Self.environmentProject(environment: environment) {
      initialState.projects.removeAll { $0.id == environmentProject.id }
      initialState.projects.insert(environmentProject, at: 0)
      initialState.selectedProjectID = environmentProject.id
    }
    if initialState.selectedProjectID == nil {
      initialState.selectedProjectID = initialState.projects.first?.id
    }
    state = initialState

    Task { await refreshBranches() }
    Task { await discoverExternalWorkflows() }
  }

  func selectProject(_ project: WorkflowProject) {
    update { $0.selectedProjectID = project.id }
    projectStore.saveSelectedProjectID(project.id)
    Task { await refreshBranch(for: project) }
  }

  func selectProjectFolder() {
    do {
      guard let project = try projectPicker.pickProject() else { return }
      update {
        $0.projects.removeAll { $0.id == project.id }
        $0.projects.insert(project, at: 0)
      }
      projectStore.saveProjects(state.projects)
      selectProject(project)
    } catch {
      update {
        $0.statusMessage = "Could not save project access: \(error)"
        $0.lastRunSucceeded = false
      }
    }
  }

  func refreshSelectedProject() {
    guard let project = state.selectedProject else { return }
    Task { await refreshBranch(for: project) }
  }

  func toggleWorkflowExpansion(_ workflow: WorkflowDefinition) {
    withAnimation(.easeInOut(duration: 0.18)) {
      update {
        if $0.expandedWorkflowIDs.contains(workflow.id) {
          $0.expandedWorkflowIDs.remove(workflow.id)
        } else {
          $0.expandedWorkflowIDs.insert(workflow.id)
        }
      }
    }
  }

  func updateImplementationPlanPath(_ path: String) {
    update { $0.implementationPlanPath = path }
  }

  func updateImplementationBuildCommand(_ command: String) {
    update { $0.implementationBuildCommand = command }
  }

  func updateExternalWorkflowInput(
    workflowID: WorkflowDefinition.ID, inputID: String, value: String
  ) {
    update {
      var values = $0.externalWorkflowInputValues[workflowID, default: [:]]
      values[inputID] = value
      $0.externalWorkflowInputValues[workflowID] = values
    }
  }

  func runWorkflow(_ workflow: WorkflowDefinition) {
    switch workflow.source {
    case .builtIn:
      runBuiltInWorkflow(workflow)
    case .externalSwiftPackage:
      runExternalWorkflow(workflow)
    }
  }

  private func runBuiltInWorkflow(_ workflow: WorkflowDefinition) {
    guard let project = state.selectedProject,
          let builtInWorkflow = builtInWorkflowCatalog.workflow(id: workflow.id)
    else { return }

    update {
      $0.isRunning = true
      $0.activeWorkflowID = workflow.id
      $0.statusMessage = nil
      $0.timelineOutput = "\(workflow.title) started."
      $0.stepRecords = []
      $0.output = ""
      $0.debugLogURL = nil
      $0.lastRunSucceeded = nil
      $0.planningInteraction = nil
    }

    Task {
      let result = await builtInWorkflow.run(
        context: BuiltInWorkflowRunContext(
          project: project,
          inputValues: builtInInputValues(),
          progress: { [weak model = self] progress in
            await model?.applyWorkflowProgress(progress)
          }
        ))
      applyBuiltInWorkflowResult(result, workflow: workflow, project: project)
    }
  }

  private func runExternalWorkflow(_ workflow: WorkflowDefinition) {
    guard let project = state.selectedProject else { return }

    update {
      $0.isRunning = true
      $0.activeWorkflowID = workflow.id
      $0.statusMessage = "Running \(workflow.title)..."
      $0.timelineOutput = "External workflow started: \(workflow.title)"
      $0.stepRecords = []
      $0.output = ""
      $0.debugLogURL = nil
      $0.lastRunSucceeded = nil
      $0.planningInteraction = nil
    }

    Task {
      let result = await externalWorkflowRunner.run(
        workflow: workflow,
        project: project,
        inputValues: state.externalWorkflowInputValues[workflow.id] ?? [:],
        progress: { [weak model = self] progress in
          await model?.applyWorkflowProgress(progress)
        }
      )
      update {
        $0.output = result.output
        $0.debugLogURL = result.debugLogURL
        $0.stepRecords = result.stepRecords
        $0.timelineOutput = result.timeline.isEmpty ? result.output : result.timeline
        $0.isRunning = false
        $0.activeWorkflowID = nil
        $0.lastRunWorkflowID = workflow.id
        $0.lastRunSucceeded = result.exitCode == 0
        $0.statusMessage =
          result.exitCode == 0
          ? "\(workflow.title) completed for \(project.name)."
          : "\(workflow.title) failed with exit code \(result.exitCode)."
      }
    }
  }

  private func discoverExternalWorkflows() async {
    let externalWorkflows = await externalWorkflowDiscovery.discoverWorkflows()
    guard !externalWorkflows.isEmpty else { return }
    update {
      $0.workflows.removeAll { $0.source == .externalSwiftPackage }
      $0.workflows.append(contentsOf: externalWorkflows)
      $0.expandedWorkflowIDs.formUnion(externalWorkflows.map(\.id))
      for workflow in externalWorkflows {
        let defaults = Self.defaultInputValues(for: workflow)
        $0.externalWorkflowInputValues[workflow.id] = defaults.merging(
          $0.externalWorkflowInputValues[workflow.id] ?? [:],
          uniquingKeysWith: { _, current in current }
        )
      }
    }
  }

  private func applyBuiltInWorkflowResult(
    _ result: BuiltInWorkflowRunResult,
    workflow: WorkflowDefinition,
    project: WorkflowProject
  ) {
    switch result {
    case .completed(let processResult):
      applyCompletedBuiltInWorkflowResult(processResult, workflow: workflow, project: project)
    case .waiting(let progress, let output):
      update {
        $0.output = output
        $0.debugLogURL = progress.debugLogURL
        $0.stepRecords = progress.stepRecords
        $0.timelineOutput = progress.timeline
        $0.isRunning = true
        $0.activeWorkflowID = workflow.id
        $0.lastRunWorkflowID = nil
        $0.lastRunSucceeded = nil
        $0.statusMessage = nil
        if workflow.id == PlanningReviewWorkflowRunner.id {
          $0.planningInteraction = PlanningReviewWorkflowRunner.makeInitialInteractionState()
        } else {
          $0.planningInteraction = nil
        }
      }
    }
  }

  private func applyCompletedBuiltInWorkflowResult(
    _ result: ProcessResult,
    workflow: WorkflowDefinition,
    project: WorkflowProject
  ) {
    update {
      $0.output = result.output
      $0.debugLogURL = result.debugLogURL
      $0.stepRecords = result.stepRecords
      $0.timelineOutput = result.timeline.isEmpty ? result.output : result.timeline
      $0.isRunning = false
      $0.activeWorkflowID = nil
      $0.lastRunWorkflowID = workflow.id
      $0.lastRunSucceeded = result.exitCode == 0
      $0.statusMessage =
        result.exitCode == 0
        ? "\(workflow.title) completed for \(project.name)."
        : "\(workflow.title) failed with exit code \(result.exitCode)."
    }
  }

  private func refreshBranches() async {
    for project in state.projects {
      await refreshBranch(for: project)
    }
  }

  private func applyWorkflowProgress(_ progress: WorkflowRunProgress) {
    update {
      $0.timelineOutput = progress.timeline
      $0.debugLogURL = progress.debugLogURL
      $0.stepRecords = progress.stepRecords
    }
  }

  private func refreshBranch(for project: WorkflowProject) async {
    let branchName = await branchReader.currentBranchName(for: project)
    update {
      $0.branchNames[project.id] = branchName
    }
  }

  func update(_ mutate: (inout WorkflowRunnerState) -> Void) {
    mutate(&state)
  }

  private static func environmentProject(environment: [String: String]) -> WorkflowProject? {
    guard let path = environment["HEPHAESTUS_WORKFLOW_PROJECT_PATH"], !path.isEmpty else {
      return nil
    }
    return WorkflowProject(url: URL(fileURLWithPath: path, isDirectory: true), bookmarkData: nil)
  }

  private static func defaultInputValues(for workflow: WorkflowDefinition) -> [String: String] {
    Dictionary(
      uniqueKeysWithValues: workflow.inputs.map {
        ($0.id, $0.defaultValue ?? "")
      })
  }

  private func builtInInputValues() -> [String: String] {
    [
      ImplementationReviewBuiltInWorkflow.planPathInputID: state.implementationPlanPath,
      ImplementationReviewBuiltInWorkflow.buildCommandInputID: state.implementationBuildCommand,
    ]
  }

}
