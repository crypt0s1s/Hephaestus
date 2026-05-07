import Combine
import Foundation
import SwiftUI

@MainActor
final class WorkflowRunnerModel: ObservableObject {
  @Published private(set) var state: WorkflowRunnerState

  private let projectStore: ProjectStore
  private let projectPicker: ProjectPicker
  private let branchReader: GitBranchReader
  private let workflowRunner: HeadlessCodexWorkflowRunner
  private let externalWorkflowDiscovery: ExternalWorkflowDiscovery
  private let externalWorkflowRunner: ExternalWorkflowRunner
  private let environment: [String: String]

  convenience init() {
    self.init(
      projectStore: UserDefaultsProjectStore(),
      projectPicker: NSOpenPanelProjectPicker(),
      branchReader: GitBranchReader(),
      workflowRunner: HeadlessCodexWorkflowRunner(),
      externalWorkflowDiscovery: ExternalWorkflowDiscovery(),
      externalWorkflowRunner: ExternalWorkflowRunner(),
      environment: ProcessInfo.processInfo.environment
    )
  }

  init(
    projectStore: ProjectStore,
    projectPicker: ProjectPicker,
    branchReader: GitBranchReader,
    workflowRunner: HeadlessCodexWorkflowRunner,
    externalWorkflowDiscovery: ExternalWorkflowDiscovery,
    externalWorkflowRunner: ExternalWorkflowRunner,
    environment: [String: String]
  ) {
    self.projectStore = projectStore
    self.projectPicker = projectPicker
    self.branchReader = branchReader
    self.workflowRunner = workflowRunner
    self.externalWorkflowDiscovery = externalWorkflowDiscovery
    self.externalWorkflowRunner = externalWorkflowRunner
    self.environment = environment

    let snapshot = projectStore.load()
    var initialState = WorkflowRunnerState(
      projects: snapshot.projects,
      selectedProjectID: snapshot.selectedProjectID
    )
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
    switch workflow.kind {
    case .helloWorld:
      runHelloWorldWorkflow()
    case .implementationReviewLoop:
      runImplementationReviewLoop()
    case .externalSwiftPackage:
      runExternalWorkflow(workflow)
    }
  }

  private func runHelloWorldWorkflow() {
    guard let project = state.selectedProject else { return }

    update {
      $0.isRunning = true
      $0.activeWorkflowID = WorkflowDefinition.helloWorld.id
      $0.statusMessage = "Running HelloWorld workflow..."
      $0.timelineOutput =
        "Step 1 - Create HelloWorld.txt started.\nStep 2 - Delete HelloWorld.txt will run after creation."
      $0.stepRecords = []
      $0.output = ""
      $0.debugLogURL = nil
      $0.lastRunSucceeded = nil
    }

    Task {
      let result = await workflowRunner.runHelloWorldWorkflow(in: project)
      update {
        $0.output = result.output
        $0.debugLogURL = result.debugLogURL
        $0.stepRecords = result.stepRecords
        $0.timelineOutput =
          result.exitCode == 0
          ? "Step 1 - Create HelloWorld.txt finished.\nStep 2 - Delete HelloWorld.txt finished.\nWorkflow completed."
          : "HelloWorld workflow failed. Open full logs for details."
        $0.isRunning = false
        $0.activeWorkflowID = nil
        $0.lastRunWorkflowID = WorkflowDefinition.helloWorld.id
        $0.lastRunSucceeded = result.exitCode == 0
        $0.statusMessage =
          result.exitCode == 0
          ? "Created and deleted HelloWorld.txt in \(project.name)."
          : "Workflow failed with exit code \(result.exitCode)."
      }
    }
  }

  private func runImplementationReviewLoop() {
    guard let project = state.selectedProject else { return }

    let request = ImplementationReviewWorkflowRequest(
      planRelativePath: state.implementationPlanPath,
      buildCommand: state.implementationBuildCommand
    )

    update {
      $0.isRunning = true
      $0.activeWorkflowID = WorkflowDefinition.implementationReviewLoop.id
      $0.statusMessage = nil
      $0.timelineOutput = "Step 0 - Preparing implementation review loop..."
      $0.stepRecords = []
      $0.output = ""
      $0.debugLogURL = nil
      $0.lastRunSucceeded = nil
    }

    Task {
      let result = await workflowRunner.runImplementationReviewLoop(
        in: project,
        request: request,
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
        $0.lastRunWorkflowID = WorkflowDefinition.implementationReviewLoop.id
        $0.lastRunSucceeded = result.exitCode == 0
        $0.statusMessage =
          result.exitCode == 0
          ? "Implementation Review Loop completed for \(project.name)."
          : "Implementation Review Loop failed with exit code \(result.exitCode)."
      }
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
      $0.workflows.removeAll { $0.kind == .externalSwiftPackage }
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

  private func update(_ mutate: (inout WorkflowRunnerState) -> Void) {
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
}
