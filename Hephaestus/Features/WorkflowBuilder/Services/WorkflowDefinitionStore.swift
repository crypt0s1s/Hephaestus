import Foundation

nonisolated struct WorkflowDefinitionStore {
    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
        encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
    }

    func loadDefinitions(project: WorkflowProject) throws -> [WorkflowGraphDefinition] {
        let directory = workflowDirectory(project: project)
        guard fileManager.fileExists(atPath: directory.path) else { return [] }
        let files = try fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        )
        .filter { $0.pathExtension == "json" || $0.pathExtension == "workflow" }
        .filter { $0.lastPathComponent.hasSuffix(".workflow.json") }
        return try files.sorted { $0.lastPathComponent < $1.lastPathComponent }.map { file in
            try decoder.decode(WorkflowGraphDefinition.self, from: Data(contentsOf: file))
        }
    }

    func save(_ definition: WorkflowGraphDefinition, project: WorkflowProject) throws {
        let directory = workflowDirectory(project: project)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try encoder.encode(definition)
        try data.write(to: fileURL(for: definition, project: project), options: .atomic)
    }

    func fileURL(for definition: WorkflowGraphDefinition, project: WorkflowProject) -> URL {
        workflowDirectory(project: project)
            .appendingPathComponent("\(definition.id).workflow.json", isDirectory: false)
    }

    private func workflowDirectory(project: WorkflowProject) -> URL {
        URL(fileURLWithPath: project.path, isDirectory: true)
            .appendingPathComponent(".hephaestus", isDirectory: true)
            .appendingPathComponent("workflows", isDirectory: true)
    }
}
