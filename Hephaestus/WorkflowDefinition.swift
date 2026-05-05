import Foundation

struct WorkflowDefinition: Identifiable, Equatable {
    let id: String
    let title: String
    let subtitle: String
    let steps: [WorkflowStepDefinition]

    static let helloWorld = WorkflowDefinition(
        id: "hello-world",
        title: "Create and delete HelloWorld.txt",
        subtitle: "Runs two headless Codex CLI steps in the selected folder.",
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
}

struct WorkflowStepDefinition: Identifiable, Equatable {
    let id: String
    let title: String
    let subtitle: String
}
