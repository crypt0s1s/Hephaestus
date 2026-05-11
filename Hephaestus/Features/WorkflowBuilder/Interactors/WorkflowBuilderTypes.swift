import Foundation

struct WorkflowBuilderState: Equatable {
    var projectID: WorkflowProject.ID?
    var savedDefinitions: [WorkflowGraphDefinition] = []
    var definition: WorkflowGraphDefinition?
    var selectedNodeID: String?
    var validationResult: WorkflowValidationResult?
    var statusMessage: String?

    var selectedNode: WorkflowNode? {
        guard let selectedNodeID else { return nil }
        return definition?.nodes.first { $0.id == selectedNodeID }
    }
}

enum WorkflowBuilderPattern: String, CaseIterable, Identifiable {
    case planningLoop
    case reviewLoop
    case implementationLoop

    var id: String { rawValue }

    var title: String {
        switch self {
        case .planningLoop:
            "Planning Loop"
        case .reviewLoop:
            "Review Loop"
        case .implementationLoop:
            "Implementation Loop"
        }
    }
}

enum WorkflowLoopStopPreset: String, CaseIterable, Identifiable {
    case maxIterations
    case untilApproval
    case untilReviewPasses
    case untilNoBlockingFindings
    case manual

    var id: String { rawValue }

    var title: String {
        switch self {
        case .maxIterations:
            "Max iterations"
        case .untilApproval:
            "Until approval"
        case .untilReviewPasses:
            "Until review passes"
        case .untilNoBlockingFindings:
            "Until no blocking findings"
        case .manual:
            "Manual"
        }
    }

    init(condition: WorkflowLoopStopCondition) {
        switch condition {
        case .maxIterations:
            self = .maxIterations
        case .untilApproval:
            self = .untilApproval
        case .untilReviewPasses:
            self = .untilReviewPasses
        case .untilNoBlockingFindings:
            self = .untilNoBlockingFindings
        case .manual:
            self = .manual
        }
    }

    func stopCondition(maxIterations: Int) -> WorkflowLoopStopCondition {
        switch self {
        case .maxIterations:
            .maxIterations(maxIterations)
        case .untilApproval:
            .untilApproval(maxIterations: maxIterations)
        case .untilReviewPasses:
            .untilReviewPasses(maxIterations: maxIterations)
        case .untilNoBlockingFindings:
            .untilNoBlockingFindings(maxIterations: maxIterations)
        case .manual:
            .manual
        }
    }
}
