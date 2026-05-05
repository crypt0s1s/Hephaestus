import Foundation

struct WorkflowDescription: Codable {
    let id: String
    let name: String
    let version: String
    let summary: String
    let inputs: [WorkflowInputDefinition]
    let steps: [WorkflowStepDescription]
}

struct WorkflowInputDefinition: Codable {
    let id: String
    let type: String
    let label: String
    let defaultValue: String?
}

struct WorkflowStepDescription: Codable {
    let id: String
    let title: String
    let summary: String
}

struct WorkflowEvent: Codable {
    let type: String
    let stepID: String?
    let title: String?
    let status: String?
    let summary: String?
}

struct WorkflowRunInput: Codable {
    let projectPath: String
    let values: [String: String]
}

let description = WorkflowDescription(
    id: "external-implementation-review-example",
    name: "External Implementation Review Example",
    version: "0.1.0",
    summary: "Fake external Swift package workflow that emits implementation, build, review, and gate events.",
    inputs: [
        WorkflowInputDefinition(id: "planPath", type: "string", label: "Plan path", defaultValue: "docs/plans/mock-implementation-review-loop-plan.md"),
        WorkflowInputDefinition(id: "buildCommand", type: "string", label: "Build command", defaultValue: "swift build")
    ],
    steps: [
        WorkflowStepDescription(id: "describe", title: "Describe workflow", summary: "External package provides metadata to Hephaestus."),
        WorkflowStepDescription(id: "implement", title: "Implement plan", summary: "Fake implementer phase emits a successful result."),
        WorkflowStepDescription(id: "build", title: "Build", summary: "Fake build phase emits a successful result."),
        WorkflowStepDescription(id: "review-a", title: "Reviewer A", summary: "Fake reviewer A emits pass."),
        WorkflowStepDescription(id: "review-b", title: "Reviewer B", summary: "Fake reviewer B emits pass."),
        WorkflowStepDescription(id: "gate", title: "Review gate", summary: "Fake gate completes the workflow.")
    ]
)

func writeJSON<T: Encodable>(_ value: T) throws {
    let data = try JSONEncoder().encode(value)
    FileHandle.standardOutput.write(data)
    FileHandle.standardOutput.write(Data("\n".utf8))
}

func emit(_ event: WorkflowEvent) {
    try? writeJSON(event)
    fflush(stdout)
}

let command = CommandLine.arguments.dropFirst().first ?? "describe"

do {
    switch command {
    case "describe":
        try writeJSON(description)
    case "validate":
        try writeJSON(["status": "ok"])
    case "run":
        let input = try loadRunInput()
        let planPath = input.values["planPath"] ?? "unspecified plan"
        let buildCommand = input.values["buildCommand"] ?? "unspecified build"
        emit(WorkflowEvent(type: "workflowStarted", stepID: nil, title: description.name, status: "inProgress", summary: "External workflow process started."))
        emit(WorkflowEvent(type: "stepStarted", stepID: "implement", title: "Implement plan", status: "inProgress", summary: "Fake implementer started for \(planPath)."))
        emit(WorkflowEvent(type: "stepFinished", stepID: "implement", title: "Implement plan", status: "succeeded", summary: "Fake implementer finished."))
        emit(WorkflowEvent(type: "stepStarted", stepID: "build", title: "Build", status: "inProgress", summary: "Fake build started: \(buildCommand)."))
        emit(WorkflowEvent(type: "stepFinished", stepID: "build", title: "Build", status: "succeeded", summary: "Fake build passed."))
        emit(WorkflowEvent(type: "stepStarted", stepID: "review-a", title: "Reviewer A", status: "inProgress", summary: "Reviewer A started."))
        emit(WorkflowEvent(type: "stepStarted", stepID: "review-b", title: "Reviewer B", status: "inProgress", summary: "Reviewer B started."))
        emit(WorkflowEvent(type: "stepFinished", stepID: "review-a", title: "Reviewer A", status: "succeeded", summary: "Reviewer A passed."))
        emit(WorkflowEvent(type: "stepFinished", stepID: "review-b", title: "Reviewer B", status: "succeeded", summary: "Reviewer B passed."))
        emit(WorkflowEvent(type: "stepFinished", stepID: "gate", title: "Review gate", status: "succeeded", summary: "No blocking findings."))
        emit(WorkflowEvent(type: "workflowFinished", stepID: nil, title: description.name, status: "succeeded", summary: "External fake workflow completed."))
    default:
        fputs("Unknown command: \(command)\n", stderr)
        exit(64)
    }
} catch {
    fputs(String(describing: error), stderr)
    exit(1)
}

func loadRunInput() throws -> WorkflowRunInput {
    guard let inputFlagIndex = CommandLine.arguments.firstIndex(of: "--input"),
          CommandLine.arguments.indices.contains(inputFlagIndex + 1) else {
        return WorkflowRunInput(projectPath: FileManager.default.currentDirectoryPath, values: [:])
    }
    let inputURL = URL(fileURLWithPath: CommandLine.arguments[inputFlagIndex + 1])
    let data = try Data(contentsOf: inputURL)
    return try JSONDecoder().decode(WorkflowRunInput.self, from: data)
}
