import Foundation

struct WorkflowDefinition: Identifiable, Equatable {
    let id: String
    let title: String
    let subtitle: String
    let kind: WorkflowKind
    let steps: [WorkflowStepDefinition]

    static let helloWorld = WorkflowDefinition(
        id: "hello-world",
        title: "Create and delete HelloWorld.txt",
        subtitle: "Runs two headless Codex CLI steps in the selected folder.",
        kind: .helloWorld,
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
}

enum WorkflowKind: Equatable {
    case helloWorld
    case implementationReviewLoop
}

struct WorkflowStepDefinition: Identifiable, Equatable {
    let id: String
    let title: String
    let subtitle: String
}
