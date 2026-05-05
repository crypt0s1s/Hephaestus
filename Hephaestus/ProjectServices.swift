import AppKit
import Foundation

protocol ProjectStore {
    func load() -> ProjectStoreSnapshot
    func saveProjects(_ projects: [WorkflowProject])
    func saveSelectedProjectID(_ id: WorkflowProject.ID?)
}

struct ProjectStoreSnapshot: Equatable {
    var projects: [WorkflowProject]
    var selectedProjectID: WorkflowProject.ID?
}

struct UserDefaultsProjectStore: ProjectStore {
    private let defaults: UserDefaults
    private let projectsKey = "hephaestus.workflow.projects"
    private let selectedProjectKey = "hephaestus.workflow.selectedProject"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> ProjectStoreSnapshot {
        ProjectStoreSnapshot(
            projects: loadProjects(),
            selectedProjectID: defaults.string(forKey: selectedProjectKey)
        )
    }

    func saveProjects(_ projects: [WorkflowProject]) {
        guard let data = try? JSONEncoder().encode(projects) else { return }
        defaults.set(data, forKey: projectsKey)
    }

    func saveSelectedProjectID(_ id: WorkflowProject.ID?) {
        defaults.set(id, forKey: selectedProjectKey)
    }

    private func loadProjects() -> [WorkflowProject] {
        guard let data = defaults.data(forKey: projectsKey) else { return [] }
        return (try? JSONDecoder().decode([WorkflowProject].self, from: data)) ?? []
    }
}

protocol ProjectPicker {
    @MainActor
    func pickProject() throws -> WorkflowProject?
}

struct NSOpenPanelProjectPicker: ProjectPicker {
    @MainActor
    func pickProject() throws -> WorkflowProject? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.prompt = "Select Project"

        guard panel.runModal() == .OK, let url = panel.url else { return nil }

        let bookmark = try url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
        return WorkflowProject(url: url, bookmarkData: bookmark)
    }
}

struct GitBranchReader {
    private let processRunner: WorkflowProcessRunning

    init(processRunner: WorkflowProcessRunning = DefaultProcessRunner()) {
        self.processRunner = processRunner
    }

    func currentBranchName(for project: WorkflowProject) async -> String? {
        let result = await ProjectSecurityScope.withAccess(to: project) {
            await processRunner.run(
                executable: URL(fileURLWithPath: "/usr/bin/env"),
                arguments: ["git", "-C", project.path, "branch", "--show-current"]
            )
        }
        guard result.exitCode == 0 else {
            return nil
        }
        let branch = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
        return branch.isEmpty ? nil : branch
    }
}

enum ProjectSecurityScope {
    static func withAccess<T>(to project: WorkflowProject, operation: () async -> T) async -> T {
        var isStale = false
        let accessURL: URL?
        if let bookmarkData = project.bookmarkData {
            accessURL = try? URL(
                resolvingBookmarkData: bookmarkData,
                options: .withSecurityScope,
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )
        } else {
            accessURL = URL(fileURLWithPath: project.path, isDirectory: true)
        }

        let didStartAccess = accessURL?.startAccessingSecurityScopedResource() ?? false
        defer {
            if didStartAccess {
                accessURL?.stopAccessingSecurityScopedResource()
            }
        }
        return await operation()
    }
}
