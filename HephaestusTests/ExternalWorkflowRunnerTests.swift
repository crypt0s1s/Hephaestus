import Foundation
import Testing

@testable import Hephaestus

@MainActor
struct ExternalWorkflowRunnerTests {
    @Test
    func fastProcessExitDrainsFinalOutputAndRawLog() async throws {
        let runner = ExternalWorkflowRunner(
            processFactory: { _, _, _ in
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/bin/sh")
                let stepEvent =
                    #"{"type":"stepFinished","stepID":"fast-step","title":"Fast step","# +
                    #""status":"succeeded","summary":"Finished before pipe drained"}"#
                process.arguments = [
                    "-c",
                    """
                    printf '%s\\n' '\(stepEvent)'
                    printf 'stderr tail preserved\\n' >&2
                    """,
                ]
                return process
            }
        )

        let result = await runner.run(workflow: timeoutWorkflow(), project: timeoutProject())

        #expect(result.exitCode == 0)
        #expect(result.output.contains("stderr tail preserved"))
        #expect(result.timeline.contains("Fast step finished - Finished before pipe drained"))
        #expect(result.stepRecords.contains { $0.id == "fast-step" && $0.status == .succeeded })
        let debugLogURL = try #require(result.debugLogURL)
        let rawProcessLog = debugLogURL.appendingPathComponent("raw-process.log")
        let rawOutput = try String(contentsOf: rawProcessLog, encoding: .utf8)
        #expect(rawOutput.contains("stderr tail preserved"))
        #expect(rawOutput.contains("Finished before pipe drained"))
    }

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
        #expect(result.output.contains("External workflow timed out after 1 second."))
        #expect(result.timeline.contains("External workflow timed out after 1 second."))
        #expect(result.timeline.contains("External workflow finished: External Swift workflow"))
        let debugLogURL = try #require(result.debugLogURL)
        let rawProcessLog = debugLogURL.appendingPathComponent("raw-process.log")
        let rawOutput = try String(contentsOf: rawProcessLog, encoding: .utf8)
        #expect(rawOutput.contains("External workflow timed out after 1 second."))
    }

    @Test
    func timeoutForceKillsProcessThatIgnoresTermination() async throws {
        var capturedProcess: Process?
        let runner = ExternalWorkflowRunner(
            environment: ["HEPHAESTUS_EXTERNAL_WORKFLOW_TIMEOUT_SECONDS": "1"],
            processFactory: { _, _, _ in
                let process = Process()
                capturedProcess = process
                process.executableURL = URL(fileURLWithPath: "/bin/sh")
                let startedEvent =
                    #"{"type":"workflowStarted","title":"Stubborn external workflow","# +
                    #""status":"inProgress","summary":"Started"}"#
                process.arguments = [
                    "-c",
                    """
                    trap '' TERM
                    printf '%s\\n' '\(startedEvent)'
                    while :; do sleep 1; done
                    """,
                ]
                return process
            }
        )

        let result = await runner.run(workflow: timeoutWorkflow(), project: timeoutProject())

        #expect(result.exitCode == 124)
        #expect(capturedProcess?.isRunning == false)
        #expect(result.timeline.contains("External workflow timed out after 1 second."))
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
