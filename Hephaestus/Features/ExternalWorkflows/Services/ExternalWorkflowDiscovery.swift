import Foundation

struct ExternalWorkflowDiscovery {
    private let fileManager: FileManager
    private let environment: [String: String]
    private let processRunner: WorkflowProcessRunning

    init(
        fileManager: FileManager = .default,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        processRunner: WorkflowProcessRunning = DefaultProcessRunner()
    ) {
        self.fileManager = fileManager
        self.environment = environment
        self.processRunner = processRunner
    }

    func discoverWorkflows() async -> [WorkflowDefinition] {
        var workflows: [WorkflowDefinition] = []
        for root in workflowRoots {
            guard let manifest = loadManifest(packageURL: root),
                await validate(manifest: manifest),
                let description = await describe(manifest: manifest),
                isCompatible(description: description, manifest: manifest)
            else {
                continue
            }
            workflows.append(
                WorkflowDefinition(
                    externalDescription: description,
                    packageURL: root,
                    entryName: manifest.entry
                ))
        }
        return workflows
    }

    private var workflowRoots: [URL] {
        guard
            let rawValue = environment["HEPHAESTUS_EXTERNAL_WORKFLOW_ROOTS"]
                ?? environment["HEPHAESTUS_EXTERNAL_WORKFLOW_ROOT"]
        else {
            return []
        }

        return
            rawValue
            .split(separator: ":")
            .map { URL(fileURLWithPath: String($0), isDirectory: true) }
            .filter { fileManager.fileExists(atPath: $0.path) }
    }

    private func loadManifest(packageURL: URL) -> ExternalWorkflowManifest? {
        let manifestURL = packageURL.appendingPathComponent("HephaestusWorkflow.toml")
        guard let contents = try? String(contentsOf: manifestURL, encoding: .utf8) else {
            return nil
        }
        let values = parseManifest(contents)
        guard let id = values["id"],
            let name = values["name"],
            let version = values["version"],
            let runtime = values["runtime"],
            let entry = values["entry"]
        else {
            return nil
        }
        return ExternalWorkflowManifest(
            id: id,
            name: name,
            version: version,
            runtime: runtime,
            entry: entry,
            packageURL: packageURL
        )
    }

    private func describe(manifest: ExternalWorkflowManifest) async -> WorkflowDescription? {
        guard manifest.runtime == "swift-package" else { return nil }
        let result = await runPackageCommand(manifest: manifest, command: "describe")
        guard result.exitCode == 0 else {
            return nil
        }
        return decodeDescription(from: result.output)
    }

    private func validate(manifest: ExternalWorkflowManifest) async -> Bool {
        guard manifest.runtime == "swift-package" else { return false }
        let result = await runPackageCommand(manifest: manifest, command: "validate")
        guard result.exitCode == 0,
            let validation = decodeValidation(from: result.output)
        else {
            return false
        }
        return validation.status == "ok"
    }

    private func isCompatible(
        description: WorkflowDescription,
        manifest: ExternalWorkflowManifest
    ) -> Bool {
        description.id == manifest.id
            && description.version == manifest.version
    }

    private func runPackageCommand(
        manifest: ExternalWorkflowManifest,
        command: String
    ) async -> ProcessResult {
        await processRunner.run(
            executable: URL(fileURLWithPath: "/usr/bin/swift"),
            arguments: [
                "run",
                "--package-path", manifest.packageURL.path,
                "--scratch-path", SwiftPackageScratchPath.url(for: manifest.packageURL).path,
                manifest.entry,
                command,
            ],
            currentDirectoryURL: manifest.packageURL,
            timeoutSeconds: 120
        )
    }

    private func decodeDescription(from output: String) -> WorkflowDescription? {
        if let start = output.firstIndex(of: "{") {
            let jsonCandidate = String(output[start...])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if let data = jsonCandidate.data(using: .utf8),
                let description = try? JSONDecoder().decode(WorkflowDescription.self, from: data) {
                return description
            }
        }

        for line in output.split(separator: "\n").reversed() {
            let trimmed = String(line).trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.hasPrefix("{"), let data = trimmed.data(using: .utf8) else { continue }
            if let description = try? JSONDecoder().decode(WorkflowDescription.self, from: data) {
                return description
            }
        }
        return nil
    }

    private func decodeValidation(from output: String) -> ExternalWorkflowValidation? {
        if let start = output.firstIndex(of: "{") {
            let jsonCandidate = String(output[start...])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if let data = jsonCandidate.data(using: .utf8),
                let validation = try? JSONDecoder().decode(ExternalWorkflowValidation.self, from: data) {
                return validation
            }
        }

        for line in output.split(separator: "\n").reversed() {
            let trimmed = String(line).trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.hasPrefix("{"), let data = trimmed.data(using: .utf8) else { continue }
            if let validation = try? JSONDecoder().decode(ExternalWorkflowValidation.self, from: data) {
                return validation
            }
        }
        return nil
    }

    private func parseManifest(_ contents: String) -> [String: String] {
        var values: [String: String] = [:]
        for line in contents.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, !trimmed.hasPrefix("#"),
                let separator = trimmed.firstIndex(of: "=")
            else {
                continue
            }
            let key = trimmed[..<separator].trimmingCharacters(in: .whitespacesAndNewlines)
            let rawValue = trimmed[trimmed.index(after: separator)...]
                .trimmingCharacters(in: .whitespacesAndNewlines)
            values[key] = rawValue.trimmingCharacters(in: CharacterSet(charactersIn: "\""))
        }
        return values
    }
}

private struct ExternalWorkflowValidation: Decodable {
    let status: String
}
