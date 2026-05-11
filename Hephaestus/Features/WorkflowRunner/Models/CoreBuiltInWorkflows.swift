import Foundation

struct HelloWorldBuiltInWorkflow: BuiltInWorkflow {
    static let id = "hello-world"

    let definition = WorkflowDefinition(
        id: id,
        title: "Create and delete HelloWorld.txt",
        subtitle: "Runs two headless Codex CLI steps in the selected folder.",
        source: .builtIn,
        systemImage: "doc.text",
        configuration: .none,
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
            ),
        ]
    )
    private let runner: HeadlessCodexWorkflowRunner

    init(runner: HeadlessCodexWorkflowRunner) {
        self.runner = runner
    }

    func run(context: BuiltInWorkflowRunContext) async -> BuiltInWorkflowRunResult {
        .completed(await runner.runHelloWorldWorkflow(in: context.project))
    }
}

struct ImplementationReviewBuiltInWorkflow: BuiltInWorkflow {
    static let id = "implementation-review-loop"
    static let planPathInputID = "implementation-plan-path"
    static let buildCommandInputID = "implementation-build-command"

    let definition = WorkflowDefinition(
        id: id,
        title: "Implementation Review Loop",
        subtitle: "Implements a markdown plan, builds, and loops through two reviewers.",
        source: .builtIn,
        systemImage: "point.3.connected.trianglepath.dotted",
        configuration: .implementationReview,
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
            ),
        ]
    )
    private let runner: HeadlessCodexWorkflowRunner

    init(runner: HeadlessCodexWorkflowRunner) {
        self.runner = runner
    }

    func run(context: BuiltInWorkflowRunContext) async -> BuiltInWorkflowRunResult {
        let request = ImplementationReviewWorkflowRequest(
            planRelativePath: context.inputValues[Self.planPathInputID] ?? "",
            buildCommand: context.inputValues[Self.buildCommandInputID] ?? "swift build"
        )
        return .completed(
            await runner.runImplementationReviewLoop(
                in: context.project,
                request: request,
                progress: context.progress
            ))
    }
}
