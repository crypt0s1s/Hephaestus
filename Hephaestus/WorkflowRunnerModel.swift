import Combine
import Foundation
import SwiftUI

struct WorkflowRunnerState: Equatable {
    var projects: [WorkflowProject] = []
    var selectedProjectID: WorkflowProject.ID?
    var branchNames: [WorkflowProject.ID: String] = [:]
    var workflows: [WorkflowDefinition] = [.helloWorld]
    var expandedWorkflowIDs: Set<WorkflowDefinition.ID> = [WorkflowDefinition.helloWorld.id]
    var isRunning = false
    var statusMessage: String?
    var output = ""
    var lastRunSucceeded: Bool?

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

@MainActor
final class WorkflowRunnerModel: ObservableObject {
    @Published private(set) var state: WorkflowRunnerState

    private let projectStore: ProjectStore
    private let projectPicker: ProjectPicker
    private let branchReader: GitBranchReader
    private let workflowRunner: HeadlessCodexWorkflowRunner

    convenience init() {
        self.init(
            projectStore: UserDefaultsProjectStore(),
            projectPicker: NSOpenPanelProjectPicker(),
            branchReader: GitBranchReader(),
            workflowRunner: HeadlessCodexWorkflowRunner()
        )
    }

    init(
        projectStore: ProjectStore,
        projectPicker: ProjectPicker,
        branchReader: GitBranchReader,
        workflowRunner: HeadlessCodexWorkflowRunner
    ) {
        self.projectStore = projectStore
        self.projectPicker = projectPicker
        self.branchReader = branchReader
        self.workflowRunner = workflowRunner

        let snapshot = projectStore.load()
        var initialState = WorkflowRunnerState(
            projects: snapshot.projects,
            selectedProjectID: snapshot.selectedProjectID
        )
        if initialState.selectedProjectID == nil {
            initialState.selectedProjectID = initialState.projects.first?.id
        }
        state = initialState

        Task { await refreshBranches() }
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

    func runHelloWorldWorkflow() {
        guard let project = state.selectedProject else { return }

        update {
            $0.isRunning = true
            $0.statusMessage = "Running HelloWorld workflow..."
            $0.output = ""
            $0.lastRunSucceeded = nil
        }

        Task {
            let result = await workflowRunner.runHelloWorldWorkflow(in: project)
            update {
                $0.output = result.output
                $0.isRunning = false
                $0.lastRunSucceeded = result.exitCode == 0
                $0.statusMessage = result.exitCode == 0
                    ? "Created and deleted HelloWorld.txt in \(project.name)."
                    : "Workflow failed with exit code \(result.exitCode)."
            }
        }
    }

    private func refreshBranches() async {
        for project in state.projects {
            await refreshBranch(for: project)
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
}
