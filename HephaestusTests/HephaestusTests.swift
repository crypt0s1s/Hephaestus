import Foundation
import Testing

@testable import Hephaestus

@MainActor
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
    let project = WorkflowProject(
      url: URL(fileURLWithPath: "/tmp/project", isDirectory: true), bookmarkData: nil)
    let runner = RecordingProcessRunner(results: [
      ProcessResult(exitCode: 0, output: "done"),
      ProcessResult(exitCode: 0, output: "built"),
    ])

    _ = await CodexAgentStep(processRunner: runner).run(
      CodexAgentInvocation(
        name: "Implementer",
        project: project,
        prompt: "implement"
      ))
    _ = await ShellValidationStep(processRunner: runner).run(
      ShellValidationInvocation(
        name: "Build",
        project: project,
        command: "swift build"
      ))

    let calls = runner.recordedCalls()
    #expect(calls.count == 2)
    let expectedCodexArguments = [
      "exec",
      "--cd", "/tmp/project",
      "--skip-git-repo-check",
      "--sandbox", "workspace-write",
      "implement",
    ]
    #expect(
      calls[0].arguments == expectedCodexArguments
        || calls[0].arguments == ["codex"] + expectedCodexArguments)
    #expect(calls[0].timeoutSeconds == 300)
    #expect(calls[1].executable.path == "/bin/zsh")
    #expect(calls[1].arguments == ["-lc", "swift build"])
    #expect(calls[1].currentDirectoryURL?.path == "/tmp/project")
    #expect(calls[1].timeoutSeconds == 600)
  }

  @Test
  func reviewFindingOnlyBlocksOnSeverityLinePrefixes() {
    #expect(
      !ReviewFinding(reviewerName: "A", transcript: "No P1/P2 issues remain.").hasBlockingIssue)
    #expect(!ReviewFinding(reviewerName: "A", transcript: "P3: small follow-up").hasBlockingIssue)
    #expect(
      ReviewFinding(reviewerName: "A", transcript: "- P2: missing build validation")
        .hasBlockingIssue)
    #expect(ReviewFinding(reviewerName: "A", transcript: "P1: build is broken").hasBlockingIssue)
    #expect(
      ReviewFinding(reviewerName: "A", transcript: "P2: uppercase severity blocks").hasBlockingIssue
    )
    #expect(ReviewFinding(reviewerName: "A", transcript: "pass\nP1: later issue").hasBlockingIssue)
    #expect(
      !ReviewFinding(reviewerName: "A", transcript: "p2p behavior is unchanged").hasBlockingIssue)
  }

  @Test
  func reviewFindingSummaryPrefersReviewerIssuesOverTrailingJSON() {
    let transcript = """
      I found these issues:
      P2: Missing validation in Sources/App.swift:12
      - P3: Add a focused regression test.
      [
        "/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/swiftc",
        "-target",
        "arm64-apple-macosx14.0"
      ]
      """

    #expect(
      ReviewFindingSummary.extract(from: transcript) == """
        P2: Missing validation in Sources/App.swift:12
        - P3: Add a focused regression test.
        """)
    #expect(
      ReviewFinding(reviewerName: "A", transcript: transcript).displaySummary.contains(
        "Missing validation"))
    #expect(ReviewFindingSummary.extract(from: "pass") == "pass")
    #expect(
      ReviewFindingSummary.extract(from: "pass\nP2: not actually clean") == "P2: not actually clean"
    )
    #expect(ReviewFindingSummary.extract(from: "p2p behavior is unchanged") == nil)
    let noisyReviewerTail = """
      ?? Package.swift
      ?? Sources/HelloWorldImplementationPOC/main.swift
      ?? docs/plans/hello-world.md
      codex
      P2 [.build/.lock:1] Generated SwiftPM build output is present as untracked worktree content.
      tokens used
      8,935
      P2 [.build/.lock:1] Generated SwiftPM build output is present as untracked worktree content.
      """
    #expect(
      ReviewFindingSummary.extract(from: noisyReviewerTail)
        == "P2 [.build/.lock:1] Generated SwiftPM build output is present as untracked worktree content."
    )
  }

  @Test
  func buildFailureRoutesBackToImplementerBeforeReview() async throws {
    let fixture = try makeBuildFailureRouteFixture()
    let progressRecorder = ProgressRecorder()

    let result = await fixture.executor.runImplementationReviewLoop(
      project: fixture.project,
      request: ImplementationReviewWorkflowRequest(
        planRelativePath: "plan.md", buildCommand: "swift build"),
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
    assertBuildFailureProgressEvents(progressEvents)
    try assertBuildFailureStepHierarchy(result.stepRecords, progressEvents: progressEvents)
    assertBuildFailurePrompts(fixture.runner)
    assertReviewersOverlap(progressEvents.last?.timeline ?? "")
  }

  @Test
  func reviewerBlockingFindingTriggersFixBuildAndFreshReview() async throws {
    let projectURL = try makeTemporaryProject()
    try "# Plan\n".write(
      to: projectURL.appendingPathComponent("plan.md"), atomically: true, encoding: .utf8)
    let project = WorkflowProject(url: projectURL, bookmarkData: nil)
    let runner = RecordingProcessRunner(results: [
      ProcessResult(exitCode: 0, output: "implemented"),
      ProcessResult(exitCode: 0, output: "build passed"),
      ProcessResult(exitCode: 0, output: "P2: missing test in Sources/App.swift:12"),
      ProcessResult(exitCode: 0, output: "pass"),
      ProcessResult(exitCode: 0, output: "fixed review finding"),
      ProcessResult(exitCode: 0, output: "build passed again"),
      ProcessResult(exitCode: 0, output: "pass"),
      ProcessResult(exitCode: 0, output: "pass"),
    ])
    let executor = WorkflowExecutor(
      codexStep: CodexAgentStep(processRunner: runner),
      shellStep: ShellValidationStep(processRunner: runner)
    )

    let result = await executor.runImplementationReviewLoop(
      project: project,
      request: ImplementationReviewWorkflowRequest(
        planRelativePath: "plan.md", buildCommand: "swift build")
    )

    #expect(result.exitCode == 0)
    try assertInitialReviewerStatuses(result.stepRecords)
    let codexPrompts = runner.recordedCalls()
      .filter { $0.arguments.first == "exec" }
      .compactMap { $0.arguments.last }
    let reviewerPrompt = codexPrompts.first {
      $0.contains("Review only the current uncommitted implementation diff")
    } ?? ""
    let fixPrompt = codexPrompts.first { $0.contains("reported blocking findings") } ?? ""
    #expect(codexPrompts.count == 6)
    #expect(codexPrompts.allSatisfy { !$0.contains("# Plan") })
    #expect(codexPrompts.allSatisfy { $0.contains("plan.md") })
    assertReviewerPromptGuards(reviewerPrompt)
    assertFixPromptContainsBlockingFinding(fixPrompt)
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
      \(externalWorkflowDescriptionJSON)
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
    #expect(workflows.first?.source == .externalSwiftPackage)
    #expect(workflows.first?.externalPackagePath == packageURL.path)
    #expect(workflows.first?.externalEntryName == "ImplementationReviewWorkflow")
    #expect(workflows.first?.inputs.map(\.id) == ["planPath"])
    #expect(workflows.first?.inputs.first?.defaultValue == "docs/plans/demo.md")
    #expect(workflows.first?.steps.map(\.id) == ["implement"])
    let call = runner.recordedCalls().first
    #expect(call?.arguments.contains("--package-path") == true)
    #expect(call?.arguments.contains("--scratch-path") == true)
    #expect(
      call.map { Array($0.arguments.suffix(2)) } == ["ImplementationReviewWorkflow", "describe"])
    #expect(call?.timeoutSeconds == 120)
  }
}

private func makeBuildFailureRouteFixture() throws -> (
  project: WorkflowProject,
  runner: RecordingProcessRunner,
  executor: WorkflowExecutor
) {
  let projectURL = try makeTemporaryProject()
  try "# Plan\n".write(
    to: projectURL.appendingPathComponent("plan.md"), atomically: true, encoding: .utf8)
  let runner = RecordingProcessRunner(results: [
    ProcessResult(exitCode: 0, output: "implemented"),
    ProcessResult(exitCode: 1, output: "compile error"),
    ProcessResult(exitCode: 0, output: "fixed build"),
    ProcessResult(exitCode: 0, output: "build passed"),
    ProcessResult(exitCode: 0, output: "pass"),
    ProcessResult(exitCode: 0, output: "pass"),
  ])
  let executor = WorkflowExecutor(
    codexStep: CodexAgentStep(processRunner: runner),
    shellStep: ShellValidationStep(processRunner: runner)
  )
  return (WorkflowProject(url: projectURL, bookmarkData: nil), runner, executor)
}

private func assertBuildFailureProgressEvents(_ progressEvents: [WorkflowRunProgress]) {
  let didStartInitialImplementation = progressEvents.contains { event in
    event.timeline.contains("Step 1 - Implementer started initial implementation.")
  }
  let didPublishDebugLog = progressEvents.contains { event in
    event.debugLogURL != nil
  }
  let didPublishFeedbackRelay = progressEvents.contains { event in
    event.stepRecords.contains { record in
      record.title == "Step 4 - Feedback relay"
    }
  }

  #expect(didStartInitialImplementation)
  #expect(didPublishDebugLog)
  #expect(didPublishFeedbackRelay)
}

private func assertReviewerPromptGuards(_ reviewerPrompt: String) {
  #expect(!reviewerPrompt.isEmpty)
  #expect(reviewerPrompt.contains("Shell is allowed only for read-only inspection and comparison"))
  #expect(reviewerPrompt.contains("Do not run or retry builds, tests, package resolution"))
  #expect(reviewerPrompt.contains("The workflow build step has already run."))
  #expect(reviewerPrompt.contains("xcodebuild"))
  #expect(reviewerPrompt.contains("Return at most 5 findings"))
}

private func assertFixPromptContainsBlockingFinding(_ fixPrompt: String) {
  #expect(fixPrompt.contains("reported blocking findings"))
  #expect(fixPrompt.contains("P2: missing test"))
}

private func assertInitialReviewerStatuses(_ records: [WorkflowStepRecord]) throws {
  let initialReviewerA = try #require(records.first { $0.id == "step-3-reviewer-a-0" })
  let initialReviewerB = try #require(records.first { $0.id == "step-3-reviewer-b-0" })
  #expect(initialReviewerA.status == .needsFix)
  #expect(initialReviewerA.summary == "Reviewer A returned blocking findings.")
  #expect(initialReviewerB.status == .succeeded)
  #expect(initialReviewerB.summary == "Reviewer B passed review.")
}

private func assertBuildFailureStepHierarchy(
  _ finalRecords: [WorkflowStepRecord],
  progressEvents: [WorkflowRunProgress]
) throws {
  let initialBuild = try #require(finalRecords.first { $0.id == "step-2-build-initial" })
  #expect(initialBuild.hierarchy?.groupID == "cycle-0")
  #expect(initialBuild.hierarchy?.cycleIndex == 0)
  #expect(initialBuild.hierarchy?.phaseOrder == 20)
  let feedback = try #require(finalRecords.first { $0.id == "step-4-feedback-0" })
  #expect(feedback.hierarchy?.cycleOutcome == .needsFix)
  let fixBuild = try #require(finalRecords.first { $0.id == "step-2-build-fix-1" })
  #expect(fixBuild.hierarchy?.groupID == "cycle-1")
  #expect(fixBuild.sortOrder > feedback.sortOrder)
  let initialImplementerSequences = progressEvents.compactMap { event in
    event.stepRecords.first { $0.id == "step-1-implementer-initial" }?.hierarchy?.sequenceOrder
  }
  #expect(Set(initialImplementerSequences).count == 1)
}

private func assertBuildFailurePrompts(_ runner: RecordingProcessRunner) {
  let codexPrompts = runner.recordedCalls()
    .filter { $0.arguments.first == "exec" }
    .compactMap { $0.arguments.last }
  #expect(codexPrompts.count == 4)
  #expect(codexPrompts.allSatisfy { !$0.contains("# Plan") })
  #expect(codexPrompts.allSatisfy { $0.contains("plan.md") })
  #expect(codexPrompts[1].contains("The build failed"))
  #expect(codexPrompts.contains { $0.contains("Reviewer A") })
  #expect(codexPrompts.contains { $0.contains("Reviewer B") })
  let reviewerCalls = runner.recordedCalls()
    .filter { call in
      call.arguments.first == "exec" && (call.arguments.last?.contains("Reviewer") == true)
    }
  #expect(reviewerCalls.count == 2)
  #expect(reviewerCalls.allSatisfy { $0.timeoutSeconds == 90 })
}

private func assertReviewersOverlap(_ finalTimeline: String) {
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

private func makeTemporaryProject() throws -> URL {
  let url = URL(fileURLWithPath: NSTemporaryDirectory())
    .appendingPathComponent("hephaestus-workflow-tests-\(UUID().uuidString)", isDirectory: true)
  try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
  return url
}
