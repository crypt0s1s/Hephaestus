import Foundation

struct WorkflowDefinition: Identifiable, Equatable {
    let id: String
    let title: String
    let subtitle: String
    let kind: WorkflowKind
    let steps: [WorkflowStepDefinition]
    let inputs: [WorkflowInputDefinition]
    let externalPackagePath: String?
    let externalEntryName: String?

    static let helloWorld = WorkflowDefinition(
        id: "hello-world",
        title: "Create and delete HelloWorld.txt",
        subtitle: "Runs two headless Codex CLI steps in the selected folder.",
        kind: .helloWorld,
        inputs: [],
        externalPackagePath: nil,
        externalEntryName: nil,
        steps: [
            WorkflowStepDefinition(
                id: "create-hello-world",
                title: "Create HelloWorld.txt",
                subtitle: "Creates the file with the expected sample text."
            ),
            WorkflowStepDefinition(
                id: "delete-hello-world",
                title: "Delete HelloWorld.txt",
                subtitle: "Removes the file after the create step succeeds."
            )
        ]
    )

    static let implementationReviewLoop = WorkflowDefinition(
        id: "implementation-review-loop",
        title: "Implementation Review Loop",
        subtitle: "Implements a markdown plan, builds, and loops through two reviewers.",
        kind: .implementationReviewLoop,
        inputs: [],
        externalPackagePath: nil,
        externalEntryName: nil,
        steps: [
            WorkflowStepDefinition(
                id: "implement-plan",
                title: "Implement plan",
                subtitle: "One implementer agent applies the selected markdown plan."
            ),
            WorkflowStepDefinition(
                id: "build-after-implementation",
                title: "Build after implementation",
                subtitle: "Runs the configured build command and returns failures to the implementer."
            ),
            WorkflowStepDefinition(
                id: "two-reviewers",
                title: "Review with two agents",
                subtitle: "Two fresh review-only agents check the patch for blocking issues."
            ),
            WorkflowStepDefinition(
                id: "fix-loop",
                title: "Fix and re-review",
                subtitle: "Blocking findings go back through implement, build, and review."
            )
        ]
    )

    init(
        id: String,
        title: String,
        subtitle: String,
        kind: WorkflowKind,
        inputs: [WorkflowInputDefinition] = [],
        externalPackagePath: String? = nil,
        externalEntryName: String? = nil,
        steps: [WorkflowStepDefinition]
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.kind = kind
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
            kind: .externalSwiftPackage,
            inputs: description.inputs,
            externalPackagePath: packageURL.path,
            externalEntryName: entryName,
            steps: description.steps.map {
                WorkflowStepDefinition(id: $0.id, title: $0.title, subtitle: $0.summary)
            }
        )
    }
}

enum WorkflowKind: Equatable {
    case helloWorld
    case implementationReviewLoop
    case externalSwiftPackage
}

struct WorkflowStepDefinition: Identifiable, Equatable {
    let id: String
    let title: String
    let subtitle: String
}
