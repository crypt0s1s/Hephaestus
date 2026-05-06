import Foundation

struct HeadlessCodexWorkflowRunner {
    private let executor: WorkflowExecutor

    init(processRunner: WorkflowProcessRunning = DefaultProcessRunner()) {
        self.executor = WorkflowExecutor(
            codexStep: CodexAgentStep(processRunner: processRunner),
            shellStep: ShellValidationStep(processRunner: processRunner)
        )
    }

    func runHelloWorldWorkflow(in project: WorkflowProject) async -> ProcessResult {
        await ProjectSecurityScope.withAccess(to: project) {
            let createResult = await executor.runCodexStep(
                CodexAgentInvocation(
                    name: "Create HelloWorld.txt",
                    project: project,
                    prompt: """
                Create a file named HelloWorld.txt in the current working directory.
                The file must contain exactly:
                Hello from Hephaestus workflow
                Do not modify any other files.
                """
                )
            )
            guard createResult.exitCode == 0 else {
                return createResult
            }

            let deleteResult = await executor.runCodexStep(
                CodexAgentInvocation(
                    name: "Delete HelloWorld.txt",
                    project: project,
                    prompt: """
                Delete the file named HelloWorld.txt from the current working directory.
                Do not modify any other files.
                """
                )
            )

            return ProcessResult(
                exitCode: deleteResult.exitCode,
                output: createResult.output + "\n" + deleteResult.output
            )
        }
    }

    func runImplementationReviewLoop(
        in project: WorkflowProject,
        request: ImplementationReviewWorkflowRequest,
        progress: WorkflowProgressHandler? = nil
    ) async -> ProcessResult {
        await ProjectSecurityScope.withAccess(to: project) {
            await executor.runImplementationReviewLoop(project: project, request: request, progress: progress)
        }
    }
}
