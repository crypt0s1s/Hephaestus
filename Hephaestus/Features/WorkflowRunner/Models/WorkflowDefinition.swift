import Foundation

struct WorkflowDefinition: Identifiable, Equatable {
    let id: String
    let title: String
    let subtitle: String
    let source: WorkflowSource
    let systemImage: String
    let configuration: WorkflowConfiguration
    let steps: [WorkflowStepDefinition]
    let inputs: [WorkflowInputDefinition]
    let externalPackagePath: String?
    let externalEntryName: String?

    init(
        id: String,
        title: String,
        subtitle: String,
        source: WorkflowSource,
        systemImage: String,
        configuration: WorkflowConfiguration,
        inputs: [WorkflowInputDefinition] = [],
        externalPackagePath: String? = nil,
        externalEntryName: String? = nil,
        steps: [WorkflowStepDefinition]
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.source = source
        self.systemImage = systemImage
        self.configuration = configuration
        self.inputs = inputs
        self.externalPackagePath = externalPackagePath
        self.externalEntryName = externalEntryName
        self.steps = steps
    }

    init(externalDescription description: WorkflowDescription, packageURL: URL, entryName: String) {
        self.init(
            id: description.id,
            title: description.name,
            subtitle: description.summary,
            source: .externalSwiftPackage,
            systemImage: "doc.text",
            configuration: description.inputs.isEmpty ? .none : .inputs,
            inputs: description.inputs,
            externalPackagePath: packageURL.path,
            externalEntryName: entryName,
            steps: description.steps.map {
                WorkflowStepDefinition(id: $0.id, title: $0.title, subtitle: $0.summary)
            }
        )
    }
}

enum WorkflowSource: Equatable {
    case builtIn
    case externalSwiftPackage
}

enum WorkflowConfiguration: Equatable {
    case none
    case implementationReview
    case inputs
}

struct WorkflowStepDefinition: Identifiable, Equatable {
    let id: String
    let title: String
    let subtitle: String
}
