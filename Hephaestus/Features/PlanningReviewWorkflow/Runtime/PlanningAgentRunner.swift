import Foundation

struct PlanningAgentInvocation: Equatable {
    let name: String
    let project: WorkflowProject
    let prompt: String
    let timeoutSeconds: Int
    let sandboxMode: String
}

protocol PlanningAgentRunning {
    func run(_ invocation: PlanningAgentInvocation) async -> ProcessResult
}

struct CodexPlanningAgentRunner: PlanningAgentRunning {
    private let codexStep: CodexAgentStep

    init(backendAdapter: any HarnessBackendAdapter) {
        codexStep = CodexAgentStep(backendAdapter: backendAdapter)
    }

    init(codexStep: CodexAgentStep) {
        self.codexStep = codexStep
    }

    func run(_ invocation: PlanningAgentInvocation) async -> ProcessResult {
        await codexStep.run(
            CodexAgentInvocation(
                name: invocation.name,
                project: invocation.project,
                prompt: invocation.prompt,
                timeoutSeconds: TimeInterval(invocation.timeoutSeconds),
                sandboxMode: invocation.sandboxMode
            ))
    }
}
