import Foundation

nonisolated struct WorkflowDescription: Codable, Equatable {
    let id: String
    let name: String
    let version: String
    let summary: String
    let inputs: [WorkflowInputDefinition]
    let steps: [WorkflowStepDescription]
}

nonisolated struct WorkflowInputDefinition: Codable, Equatable {
    let id: String
    let type: String
    let label: String
    let defaultValue: String?
}

nonisolated struct WorkflowStepDescription: Codable, Equatable {
    let id: String
    let title: String
    let summary: String
}

nonisolated struct WorkflowRunInput: Codable, Equatable {
    let projectPath: String
    let values: [String: String]
}

nonisolated struct ExternalWorkflowEvent: Codable, Equatable {
    let type: ExternalWorkflowEventType
    let stepID: String?
    let title: String?
    let status: ExternalWorkflowEventStatus?
    let summary: String?
}

nonisolated enum ExternalWorkflowEventType: String, Codable, Equatable {
    case workflowStarted
    case workflowFinished
    case stepStarted
    case stepFinished
    case logChunk
}

nonisolated enum ExternalWorkflowEventStatus: String, Codable, Equatable {
    case pending
    case inProgress
    case succeeded
    case failed
}

nonisolated struct ExternalWorkflowManifest: Equatable {
    let id: String
    let name: String
    let version: String
    let runtime: String
    let entry: String
    let packageURL: URL
}
