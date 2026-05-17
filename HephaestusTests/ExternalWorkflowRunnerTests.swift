import Foundation
import Testing

@testable import Hephaestus

@MainActor
struct ExternalWorkflowRunnerTests {
    @Test
    func timeoutTerminatesProcessAndRecordsFailure() async throws {
        let runner = ExternalWorkflowRunner(
            environment: ["HEPHAESTUS_EXTERNAL_WORKFLOW_TIMEOUT_SECONDS": "1"],
            processFactory: { _, _, _ in
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/bin/sh")
                let startedEvent =
                    #"{"type":"workflowStarted","title":"Slow external workflow","# +
                    #""status":"inProgress","summary":"Started"}"#
                process.arguments = [
                    "-c",
                    """
                    printf '%s\\n' '\(startedEvent)'
                    exec sleep 5
                    """,
                ]
                return process
            }
        )

        let result = await runner.run(workflow: timeoutWorkflow(), project: timeoutProject())

        #expect(result.exitCode == 124)
        #expect(result.output.contains("External workflow timed out after 1 seconds."))
        #expect(result.timeline.contains("External workflow timed out after 1 seconds."))
        #expect(result.timeline.contains("External workflow finished: External Swift workflow"))
        let debugLogURL = try #require(result.debugLogURL)
        let rawProcessLog = debugLogURL.appendingPathComponent("raw-process.log")
        let rawOutput = try String(contentsOf: rawProcessLog, encoding: .utf8)
        #expect(rawOutput.contains("External workflow timed out after 1 seconds."))
    }

    private func timeoutWorkflow() -> WorkflowDefinition {
        WorkflowDefinition(
            id: "timeout-workflow",
            title: "Timeout Workflow",
            subtitle: "Timeout test",
            source: .externalSwiftPackage,
            systemImage: "clock",
            configuration: .none,
            externalPackagePath: NSTemporaryDirectory(),
            externalEntryName: "TimeoutWorkflow",
            steps: []
        )
    }

    private func timeoutProject() -> WorkflowProject {
        WorkflowProject(url: URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true), bookmarkData: nil)
    }
}
