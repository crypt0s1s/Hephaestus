import Foundation
import Testing

@testable import Hephaestus

@MainActor
struct ExternalWorkflowDiscoveryTests {
    @Test
    func loadsSwiftPackageManifestAfterValidation() async throws {
        let packageURL = try makeTemporaryProject()
        try writeManifest(to: packageURL)
        let descriptionOutput = """
            Building for debugging...
            \(externalWorkflowDescriptionJSON)
            """
        let runner = RecordingProcessRunner(results: [
            ProcessResult(exitCode: 0, output: #"{"status":"ok"}"#),
            ProcessResult(exitCode: 0, output: descriptionOutput),
        ])
        let discovery = ExternalWorkflowDiscovery(
            environment: ["HEPHAESTUS_EXTERNAL_WORKFLOW_ROOT": packageURL.path],
            processRunner: runner
        )

        let workflows = await discovery.discoverWorkflows()

        #expect(workflows.count == 1)
        #expect(workflows.first?.id == "external-implementation-review-example")
        #expect(workflows.first?.source == .externalSwiftPackage)
        #expect(workflows.first?.externalPackagePath == packageURL.path)
        #expect(workflows.first?.externalEntryName == "ImplementationReviewWorkflow")
        #expect(workflows.first?.inputs.map(\.id) == ["planPath"])
        #expect(workflows.first?.inputs.first?.defaultValue == "docs/plans/demo.md")
        #expect(workflows.first?.steps.map(\.id) == ["implement"])
        assertDiscoveryCalls(runner.recordedCalls(), expectedCommands: ["validate", "describe"])
    }

    @Test
    func skipsInvalidWorkflowPackageBeforeDescribe() async throws {
        let packageURL = try makeTemporaryProject()
        try writeManifest(to: packageURL)
        let runner = RecordingProcessRunner(results: [
            ProcessResult(exitCode: 1, output: #"{"status":"invalid"}"#),
            ProcessResult(exitCode: 0, output: externalWorkflowDescriptionJSON),
        ])
        let discovery = ExternalWorkflowDiscovery(
            environment: ["HEPHAESTUS_EXTERNAL_WORKFLOW_ROOT": packageURL.path],
            processRunner: runner
        )

        let workflows = await discovery.discoverWorkflows()

        #expect(workflows.isEmpty)
        assertDiscoveryCalls(runner.recordedCalls(), expectedCommands: ["validate"])
    }

    @Test
    func skipsWorkflowWhenDescriptionDoesNotMatchManifest() async throws {
        let packageURL = try makeTemporaryProject()
        try writeManifest(to: packageURL)
        let mismatchedDescription = externalWorkflowDescriptionJSON
            .replacingOccurrences(of: "\"version\": \"0.1.0\"", with: "\"version\": \"9.9.9\"")
        let runner = RecordingProcessRunner(results: [
            ProcessResult(exitCode: 0, output: #"{"status":"ok"}"#),
            ProcessResult(exitCode: 0, output: mismatchedDescription),
        ])
        let discovery = ExternalWorkflowDiscovery(
            environment: ["HEPHAESTUS_EXTERNAL_WORKFLOW_ROOT": packageURL.path],
            processRunner: runner
        )

        let workflows = await discovery.discoverWorkflows()

        #expect(workflows.isEmpty)
        assertDiscoveryCalls(runner.recordedCalls(), expectedCommands: ["validate", "describe"])
    }

    private func writeManifest(to packageURL: URL) throws {
        try """
        id = "external-implementation-review-example"
        name = "External Implementation Review Example"
        version = "0.1.0"
        runtime = "swift-package"
        entry = "ImplementationReviewWorkflow"
        """.write(
            to: packageURL.appendingPathComponent("HephaestusWorkflow.toml"),
            atomically: true,
            encoding: .utf8
        )
    }

    private func assertDiscoveryCalls(
        _ calls: [RecordedProcessCall],
        expectedCommands: [String]
    ) {
        #expect(calls.count == expectedCommands.count)
        #expect(calls.allSatisfy { $0.arguments.contains("--package-path") })
        #expect(calls.allSatisfy { $0.arguments.contains("--scratch-path") })
        #expect(
            calls.map { Array($0.arguments.suffix(2)) }
                == expectedCommands.map { ["ImplementationReviewWorkflow", $0] }
        )
        #expect(calls.allSatisfy { $0.timeoutSeconds == 120 })
    }
}

private func makeTemporaryProject() throws -> URL {
    let url = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("hephaestus-external-workflow-tests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

private let externalWorkflowDescriptionJSON = """
    {
    "id": "external-implementation-review-example",
    "name": "External Implementation Review Example",
    "version": "0.1.0",
    "summary": "Fake workflow",
    "inputs": [
      {
        "id": "planPath",
        "type": "string",
        "label": "Plan path",
        "defaultValue": "docs/plans/demo.md"
      }
    ],
    "steps": [
      {
        "id": "implement",
        "title": "Implement plan",
        "summary": "Apply a plan."
      }
    ]
    }
    """
