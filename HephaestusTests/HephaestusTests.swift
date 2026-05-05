import Foundation
import Testing
@testable import Hephaestus

struct WorkflowRunnerTests {
    @Test
    func planValidationAcceptsOnlyProjectRelativeMarkdownFiles() throws {
        let projectURL = try makeTemporaryProject()
        let docsURL = projectURL.appendingPathComponent("docs", isDirectory: true)
        try FileManager.default.createDirectory(at: docsURL, withIntermediateDirectories: true)
        let planURL = docsURL.appendingPathComponent("plan.md")
        try "# Plan\n".write(to: planURL, atomically: true, encoding: .utf8)

        let project = WorkflowProject(url: projectURL, bookmarkData: nil)
        let validator = PlanFileValidator()
        let plan = try validator.loadPlan(project: project, relativePath: "docs/plan.md")

        #expect(plan.relativePath == "docs/plan.md")
        #expect(plan.contents == "# Plan\n")
        #expect(throws: PlanFileValidationError.absolutePathNotAllowed) {
            _ = try validator.loadPlan(project: project, relativePath: planURL.path)
        }
        #expect(throws: PlanFileValidationError.nonMarkdownPath("docs/plan.txt")) {
            _ = try validator.loadPlan(project: project, relativePath: "docs/plan.txt")
        }
        #expect(throws: PlanFileValidationError.escapesProject("../outside.md")) {
            _ = try validator.loadPlan(project: project, relativePath: "../outside.md")
        }
    }

    @Test
    func codexAndShellStepsConstructExpectedCommands() async {
        let project = WorkflowProject(url: URL(fileURLWithPath: "/tmp/project", isDirectory: true), bookmarkData: nil)
        let runner = RecordingProcessRunner(results: [
            ProcessResult(exitCode: 0, output: "done"),
            ProcessResult(exitCode: 0, output: "built")
        ])

        _ = await CodexAgentStep(processRunner: runner).run(CodexAgentInvocation(
            name: "Implementer",
            project: project,
            prompt: "implement"
        ))
        _ = await ShellValidationStep(processRunner: runner).run(ShellValidationInvocation(
            name: "Build",
            project: project,
            command: "swift build"
        ))

        let calls = runner.recordedCalls()
        #expect(calls.count == 2)
        #expect(calls[0].arguments == [
            "exec",
            "--cd", "/tmp/project",
            "--skip-git-repo-check",
            "--sandbox", "workspace-write",
            "implement"
        ])
        #expect(calls[0].timeoutSeconds == 300)
        #expect(calls[1].executable.path == "/bin/zsh")
        #expect(calls[1].arguments == ["-lc", "swift build"])
        #expect(calls[1].currentDirectoryURL?.path == "/tmp/project")
        #expect(calls[1].timeoutSeconds == 600)
    }

    @Test
    func reviewFindingOnlyBlocksOnSeverityLinePrefixes() {
        #expect(!ReviewFinding(reviewerName: "A", transcript: "No P1/P2 issues remain.").hasBlockingIssue)
        #expect(!ReviewFinding(reviewerName: "A", transcript: "P3: small follow-up").hasBlockingIssue)
        #expect(ReviewFinding(reviewerName: "A", transcript: "- P2: missing build validation").hasBlockingIssue)
        #expect(ReviewFinding(reviewerName: "A", transcript: "P1: build is broken").hasBlockingIssue)
    }

    @Test
    func buildFailureRoutesBackToImplementerBeforeReview() async throws {
        let projectURL = try makeTemporaryProject()
        try "# Plan\n".write(to: projectURL.appendingPathComponent("plan.md"), atomically: true, encoding: .utf8)
        let project = WorkflowProject(url: projectURL, bookmarkData: nil)
        let runner = RecordingProcessRunner(results: [
            ProcessResult(exitCode: 0, output: "implemented"),
            ProcessResult(exitCode: 1, output: "compile error"),
            ProcessResult(exitCode: 0, output: "fixed build"),
            ProcessResult(exitCode: 0, output: "build passed"),
            ProcessResult(exitCode: 0, output: "pass"),
            ProcessResult(exitCode: 0, output: "pass")
        ])
        let executor = WorkflowExecutor(
            codexStep: CodexAgentStep(processRunner: runner),
            shellStep: ShellValidationStep(processRunner: runner)
        )
        let progressRecorder = ProgressRecorder()

        let result = await executor.runImplementationReviewLoop(
            project: project,
            request: ImplementationReviewWorkflowRequest(planRelativePath: "plan.md", buildCommand: "swift build"),
            progress: { progress in
                await progressRecorder.record(progress)
            }
        )

        #expect(result.exitCode == 0)
        #expect(result.debugLogURL != nil)
        if let debugLogURL = result.debugLogURL {
            #expect(FileManager.default.fileExists(atPath: debugLogURL.path))
        }
        let progressEvents = await progressRecorder.events()
        #expect(progressEvents.contains { $0.timeline.contains("Step 1 - Implementer started initial implementation.") })
        #expect(progressEvents.contains { $0.debugLogURL != nil })
        #expect(progressEvents.contains { $0.stepRecords.contains { $0.title == "Step 4 - Feedback relay" } })
        let codexPrompts = runner.recordedCalls()
            .filter { $0.arguments.first == "exec" }
            .compactMap { $0.arguments.last }
        #expect(codexPrompts.count == 4)
        #expect(codexPrompts[1].contains("The build failed"))
        #expect(codexPrompts.contains { $0.contains("Reviewer A") })
        #expect(codexPrompts.contains { $0.contains("Reviewer B") })
        let finalTimeline = progressEvents.last?.timeline ?? ""
        let reviewerAStarted = finalTimeline.range(of: "Step 3.1 - Reviewer A started.")
        let reviewerBStarted = finalTimeline.range(of: "Step 3.2 - Reviewer B started.")
        let reviewerAFinished = reviewerAStarted.flatMap { startedRange in
            finalTimeline.range(
                of: "Step 3.1 - Reviewer A",
                options: [],
                range: startedRange.upperBound..<finalTimeline.endIndex
            )
        }
        #expect(reviewerAStarted != nil)
        #expect(reviewerBStarted != nil)
        #expect(reviewerAFinished != nil)
        if let reviewerBStarted, let reviewerAFinished {
            #expect(reviewerBStarted.lowerBound < reviewerAFinished.lowerBound)
        }
    }

    @Test
    func reviewerBlockingFindingTriggersFixBuildAndFreshReview() async throws {
        let projectURL = try makeTemporaryProject()
        try "# Plan\n".write(to: projectURL.appendingPathComponent("plan.md"), atomically: true, encoding: .utf8)
        let project = WorkflowProject(url: projectURL, bookmarkData: nil)
        let runner = RecordingProcessRunner(results: [
            ProcessResult(exitCode: 0, output: "implemented"),
            ProcessResult(exitCode: 0, output: "build passed"),
            ProcessResult(exitCode: 0, output: "P2: missing test in Sources/App.swift:12"),
            ProcessResult(exitCode: 0, output: "pass"),
            ProcessResult(exitCode: 0, output: "fixed review finding"),
            ProcessResult(exitCode: 0, output: "build passed again"),
            ProcessResult(exitCode: 0, output: "pass"),
            ProcessResult(exitCode: 0, output: "pass")
        ])
        let executor = WorkflowExecutor(
            codexStep: CodexAgentStep(processRunner: runner),
            shellStep: ShellValidationStep(processRunner: runner)
        )

        let result = await executor.runImplementationReviewLoop(
            project: project,
            request: ImplementationReviewWorkflowRequest(planRelativePath: "plan.md", buildCommand: "swift build")
        )

        #expect(result.exitCode == 0)
        let codexPrompts = runner.recordedCalls()
            .filter { $0.arguments.first == "exec" }
            .compactMap { $0.arguments.last }
        #expect(codexPrompts.count == 6)
        #expect(codexPrompts[3].contains("reported blocking findings"))
        #expect(codexPrompts[3].contains("P2: missing test"))
    }

    @Test
    func externalWorkflowDiscoveryLoadsSwiftPackageManifestAndDescription() async throws {
        let packageURL = try makeTemporaryProject()
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
        let descriptionOutput = """
        Building for debugging...
        {"id":"external-implementation-review-example","name":"External Implementation Review Example","version":"0.1.0","summary":"Fake workflow","inputs":[],"steps":[{"id":"implement","title":"Implement plan","summary":"Apply a plan."}]}
        """
        let runner = RecordingProcessRunner(results: [
            ProcessResult(exitCode: 0, output: descriptionOutput)
        ])
        let discovery = ExternalWorkflowDiscovery(
            environment: ["HEPHAESTUS_EXTERNAL_WORKFLOW_ROOT": packageURL.path],
            processRunner: runner
        )

        let workflows = await discovery.discoverWorkflows()

        #expect(workflows.count == 1)
        #expect(workflows.first?.id == "external-implementation-review-example")
        #expect(workflows.first?.kind == .externalSwiftPackage)
        #expect(workflows.first?.externalPackagePath == packageURL.path)
        #expect(workflows.first?.externalEntryName == "ImplementationReviewWorkflow")
        #expect(workflows.first?.steps.map(\.id) == ["implement"])
        let call = runner.recordedCalls().first
        #expect(call?.arguments.contains("--package-path") == true)
        #expect(call?.arguments.contains("--scratch-path") == true)
        #expect(call.map { Array($0.arguments.suffix(2)) } == ["ImplementationReviewWorkflow", "describe"])
        #expect(call?.timeoutSeconds == 120)
    }
}

private struct RecordedProcessCall: Equatable {
    let executable: URL
    let arguments: [String]
    let currentDirectoryURL: URL?
    let timeoutSeconds: TimeInterval?
}

private final class RecordingProcessRunner: WorkflowProcessRunning {
    private let lock = NSLock()
    private var results: [ProcessResult]
    private var calls: [RecordedProcessCall] = []

    init(results: [ProcessResult]) {
        self.results = results
    }

    func run(
        executable: URL,
        arguments: [String],
        currentDirectoryURL: URL?,
        timeoutSeconds: TimeInterval?
    ) async -> ProcessResult {
        lock.withLock {
            calls.append(RecordedProcessCall(
                executable: executable,
                arguments: arguments,
                currentDirectoryURL: currentDirectoryURL,
                timeoutSeconds: timeoutSeconds
            ))
            guard !results.isEmpty else {
                return ProcessResult(exitCode: 0, output: "")
            }
            return results.removeFirst()
        }
    }

    func recordedCalls() -> [RecordedProcessCall] {
        lock.withLock { calls }
    }
}

private actor ProgressRecorder {
    private var recordedEvents: [WorkflowRunProgress] = []

    func record(_ progress: WorkflowRunProgress) {
        recordedEvents.append(progress)
    }

    func events() -> [WorkflowRunProgress] {
        recordedEvents
    }
}

private func makeTemporaryProject() throws -> URL {
    let url = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("hephaestus-workflow-tests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

private extension NSLock {
    func withLock<T>(_ operation: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try operation()
    }
}
