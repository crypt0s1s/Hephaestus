import CryptoKit
import Foundation

protocol PlanningPlanArtifactMaterializing {
    func prepareDraftArtifact(project: WorkflowProject, sessionID: String) throws -> PlanningDraftArtifact

    func loadDraftArtifact(_ artifact: PlanningDraftArtifact) throws -> PlanningLoadedDraftArtifact

    func materializeDraftArtifact(
        project: WorkflowProject,
        sessionID: String,
        content: String
    ) throws -> PlanningLoadedDraftArtifact

    func acceptDraftForReview(
        project: WorkflowProject,
        sessionID: String,
        producerStepID: String,
        request: PlanningDraftAcceptanceRequest
    ) throws -> PlanningDraftAcceptance

    func materializeConsolidatedFeedback(
        project: WorkflowProject,
        sessionID: String,
        cycle: Int,
        content: String
    ) throws -> InteractiveStepOutput

    func materializePlannerResponsePlan(
        project: WorkflowProject,
        sessionID: String,
        cycle: Int,
        content: String
    ) throws -> InteractiveStepOutput

    func finalizeReviewedPlan(
        project: WorkflowProject,
        sessionID: String,
        output: InteractiveStepOutput
    ) throws -> InteractiveStepOutput
}

struct PlanningDraftAcceptanceRequest: Equatable {
    let candidate: InteractiveStepOutputCandidate
    let expectedRevision: Int
    let idempotencyKey: String
}

struct PlanningDraftAcceptance: Equatable {
    let record: InteractiveOutputAcceptanceRecord
    let output: InteractiveStepOutput
    let isNewAcceptance: Bool
}

struct PlanningDraftArtifact: Equatable {
    let project: WorkflowProject
    let relativePath: String
    let fileURL: URL
}

struct PlanningLoadedDraftArtifact: Equatable {
    let artifact: PlanningDraftArtifact
    let content: String
}

enum PlanningPlanArtifactPolicy {
    static let artifactTitle = "Submitted Plan"
    static let contentType = "text/markdown; artifact=plan"

    private static let directoryPath = ".hephaestus/planning-review"
    private static let fileName = "plan.md"
    private static let requiredSections = [
        "## Summary",
        "## Scope",
        "## Non-Goals",
        "## Implementation Approach",
        "## Validation",
        "## Open Questions",
    ]

    static func relativePlanPath(sessionID: String) -> String {
        "\(directoryPath)/\(sessionID)/\(fileName)"
    }

    static func draftPlanPath(sessionID: String) -> String {
        "\(directoryPath)/\(sessionID)/draft/\(fileName)"
    }

    static func acceptedPlanPath(sessionID: String) -> String {
        "\(directoryPath)/\(sessionID)/accepted/\(fileName)"
    }

    static func acceptanceRecordPath(sessionID: String) -> String {
        draftAcceptanceRecordPath(sessionID: sessionID)
    }

    static func draftAcceptanceRecordPath(sessionID: String) -> String {
        "\(directoryPath)/\(sessionID)/accepted/draft-acceptance.json"
    }

    static func finalAcceptanceRecordPath(sessionID: String) -> String {
        "\(directoryPath)/\(sessionID)/accepted/final-acceptance.json"
    }

    static func consolidatedFeedbackPath(sessionID: String, cycle: Int) -> String {
        "\(directoryPath)/\(sessionID)/cycles/\(cycle)/consolidated-review.md"
    }

    static func plannerResponsePlanPath(sessionID: String, cycle: Int) -> String {
        "\(directoryPath)/\(sessionID)/cycles/\(cycle)/plan.md"
    }

    static func validate(_ content: String) throws {
        let missingSections = missingRequiredSections(in: content)
        guard missingSections.isEmpty else {
            throw PlanningPlanArtifactMaterializationError.missingRequiredSections(missingSections)
        }
    }

    static func missingRequiredSections(in content: String) -> [String] {
        requiredSections.filter { !content.localizedCaseInsensitiveContains($0) }
    }

    static func contentHash(_ content: String) -> String {
        let data = Data(content.utf8)
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}

enum PlanningPlanArtifactMaterializationError: LocalizedError, Equatable {
    case missingDraftArtifact(String)
    case missingRequiredSections([String])
    case staleRevision(expected: Int, actual: Int)
    case alreadyAccepted
    case idempotencyKeyConflict

    var errorDescription: String? {
        switch self {
        case .missingDraftArtifact(let path):
            return "Planner did not write the required draft artifact at \(path)."
        case .missingRequiredSections(let sections):
            return "Plan is missing required sections: \(sections.joined(separator: ", "))"
        case .staleRevision(let expected, let actual):
            return "Draft changed before acceptance. Expected revision \(expected), found \(actual)."
        case .alreadyAccepted:
            return "A draft has already been accepted for this planning session."
        case .idempotencyKeyConflict:
            return "Acceptance idempotency key was reused with different draft content."
        }
    }
}
