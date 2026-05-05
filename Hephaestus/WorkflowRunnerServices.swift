import AppKit
import Foundation

struct ProcessResult: Equatable {
    let exitCode: Int32
    let output: String
}

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
    func currentBranchName(for project: WorkflowProject) async -> String? {
        let result = await ProjectSecurityScope.withAccess(to: project) {
            await ProcessRunner.run(
                executable: URL(fileURLWithPath: "/usr/bin/env"),
                arguments: ["git", "-C", project.path, "branch", "--show-current"]
            )
        }
        let branch = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
        return branch.isEmpty ? nil : branch
    }
}

struct HeadlessCodexWorkflowRunner {
    func runHelloWorldWorkflow(in project: WorkflowProject) async -> ProcessResult {
        await ProjectSecurityScope.withAccess(to: project) {
            let createResult = await runCodexStep(
                name: "Create HelloWorld.txt",
                project: project,
                prompt: """
                Create a file named HelloWorld.txt in the current working directory.
                The file must contain exactly:
                Hello from Hephaestus workflow
                Do not modify any other files.
                """
            )
            guard createResult.exitCode == 0 else {
                return createResult
            }

            let deleteResult = await runCodexStep(
                name: "Delete HelloWorld.txt",
                project: project,
                prompt: """
                Delete the file named HelloWorld.txt from the current working directory.
                Do not modify any other files.
                """
            )

            return ProcessResult(
                exitCode: deleteResult.exitCode,
                output: createResult.output + "\n" + deleteResult.output
            )
        }
    }

    private func runCodexStep(name: String, project: WorkflowProject, prompt: String) async -> ProcessResult {
        let result = await ProcessRunner.run(
            executable: Self.codexExecutableURL,
            arguments: [
                "exec",
                "--cd", project.path,
                "--skip-git-repo-check",
                "--sandbox", "workspace-write",
                prompt
            ]
        )
        return ProcessResult(
            exitCode: result.exitCode,
            output: """
            == \(name) ==
            \(result.output)
            """
        )
    }

    private static var codexExecutableURL: URL {
        let appBundledCodex = URL(fileURLWithPath: "/Applications/Codex.app/Contents/Resources/codex")
        if FileManager.default.isExecutableFile(atPath: appBundledCodex.path) {
            return appBundledCodex
        }
        return URL(fileURLWithPath: "/usr/bin/env")
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

enum ProcessRunner {
    static func run(executable: URL, arguments: [String]) async -> ProcessResult {
        await withCheckedContinuation { continuation in
            let process = Process()
            process.executableURL = executable
            process.arguments = executable.lastPathComponent == "env" && arguments.first != "git"
                ? ["codex"] + arguments
                : arguments

            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe

            process.terminationHandler = { process in
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: data, encoding: .utf8) ?? ""
                continuation.resume(returning: ProcessResult(exitCode: process.terminationStatus, output: output))
            }

            do {
                try process.run()
            } catch {
                continuation.resume(returning: ProcessResult(exitCode: -1, output: String(describing: error)))
            }
        }
    }
}
