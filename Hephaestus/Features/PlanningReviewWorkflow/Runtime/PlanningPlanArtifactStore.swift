import Foundation

protocol PlanningPlanArtifactMaterializing {
    func materializePlanArtifact(
        project: WorkflowProject,
        sessionID: String,
        content: String
    ) throws -> InteractiveStepArtifact
}

struct PlanningPlanArtifactStore: PlanningPlanArtifactMaterializing {
    private let fileManager: FileManager
    private let planValidator: PlanFileValidator

    init(
        fileManager: FileManager = .default,
        planValidator: PlanFileValidator = PlanFileValidator()
    ) {
        self.fileManager = fileManager
        self.planValidator = planValidator
    }

    func materializePlanArtifact(
        project: WorkflowProject,
        sessionID: String,
        content: String
    ) throws -> InteractiveStepArtifact {
        try PlanningPlanArtifactPolicy.validate(content)
        let relativePath = PlanningPlanArtifactPolicy.relativePlanPath(sessionID: sessionID)
        let projectURL = URL(fileURLWithPath: project.path, isDirectory: true)
        let planURL = projectURL.appendingPathComponent(relativePath)
        try fileManager.createDirectory(
            at: planURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try content.write(to: planURL, atomically: true, encoding: .utf8)
        _ = try planValidator.loadPlan(project: project, relativePath: relativePath)
        return InteractiveStepArtifact(
            title: PlanningPlanArtifactPolicy.artifactTitle,
            contentType: PlanningPlanArtifactPolicy.contentType,
            content: content,
            projectRelativePath: relativePath
        )
    }
}

private enum PlanningPlanArtifactPolicy {
    static let artifactTitle = "Submitted Plan"
    static let contentType = "text/markdown; artifact=plan"

    private static let directoryPath = ".hephaestus/planning-review"
    private static let fileName = "plan.md"
    private static let requiredSections = ["## Summary", "## Scope", "## Validation"]

    static func relativePlanPath(sessionID: String) -> String {
        "\(directoryPath)/\(sessionID)/\(fileName)"
    }

    static func validate(_ content: String) throws {
        let missingSections = requiredSections.filter { !content.localizedCaseInsensitiveContains($0) }
        guard missingSections.isEmpty else {
            throw PlanningPlanArtifactMaterializationError.missingRequiredSections(missingSections)
        }
    }
}

enum PlanningPlanArtifactMaterializationError: LocalizedError, Equatable {
    case missingRequiredSections([String])

    var errorDescription: String? {
        switch self {
        case .missingRequiredSections(let sections):
            return "Plan is missing required sections: \(sections.joined(separator: ", "))"
        }
    }
}
