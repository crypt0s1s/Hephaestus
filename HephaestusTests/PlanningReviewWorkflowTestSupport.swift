import Foundation
import Testing

@testable import Hephaestus

func makeTemporaryPlanningProject() throws -> URL {
    let url = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("hephaestus-planning-review-tests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

func assertPlanningReviewMessagesPersisted(
    _ messages: [WorkflowMessage],
    projectURL: URL,
    sessionID: String
) throws {
    let messagesURL = projectURL.appendingPathComponent(
        PlanningReviewMessageStore.relativeDirectoryPath(sessionID: sessionID),
        isDirectory: true
    )
    let persistedFiles = try FileManager.default.contentsOfDirectory(
        at: messagesURL,
        includingPropertiesForKeys: nil
    )
    #expect(persistedFiles.count == messages.count)

    let submittedMessage = try #require(messages.first { $0.kind == .submittedPlan })
    let submittedURL = projectURL.appendingPathComponent(
        PlanningReviewMessageStore.relativeMessagePath(
            sessionID: sessionID,
            messageID: submittedMessage.id
        )
    )
    let decoded = try JSONDecoder().decode(
        WorkflowMessage.self,
        from: Data(contentsOf: submittedURL)
    )
    #expect(decoded.kind == .submittedPlan)
    #expect(decoded.submittedPlan?.content == validPlanMarkdown)
    #expect(decoded.submittedPlan?.projectRelativePath?.hasSuffix("/plan.md") == true)
}

func decodePersistedWorkflowMessage(
    _ messageID: WorkflowMessage.ID,
    projectURL: URL,
    sessionID: String
) throws -> WorkflowMessage {
    let url = projectURL.appendingPathComponent(
        PlanningReviewMessageStore.relativeMessagePath(
            sessionID: sessionID,
            messageID: messageID
        )
    )
    return try JSONDecoder().decode(WorkflowMessage.self, from: Data(contentsOf: url))
}

@MainActor
func assertCompletedPlanningReviewSubmission(
    model: WorkflowRunnerModel,
    projectURL: URL,
    sessionID: String
) throws {
    let planURL =
        projectURL
        .appendingPathComponent(".hephaestus/planning-review/\(sessionID)", isDirectory: true)
        .appendingPathComponent("plan.md")
    let writtenPlan = try String(contentsOf: planURL, encoding: .utf8)
    #expect(writtenPlan == validPlanMarkdown)
    #expect(model.state.planningInteraction?.phase == .completed)
    #expect(model.state.planningInteraction?.submittedOutput?.artifact.projectRelativePath != nil)

    let messages = try #require(model.state.planningInteraction?.workflowMessages)
    assertPlanningReviewMessageCounts(messages)
    #expect(model.state.planningInteraction?.runtimeRun.status == .paused)
    #expect(model.state.planningInteraction?.runtimeRun.activePause?.reason == .userReview)
    #expect(model.state.planningInteraction?.runtimeRun.messageIDs == messages.map(\.id))
    try assertPlanningReviewMessagesPersisted(messages, projectURL: projectURL, sessionID: sessionID)

    #expect(model.state.isRunning)
    #expect(model.state.lastRunSucceeded == nil)
    #expect(model.state.stepRecords.contains { $0.id == "planning-review-reviewer-1-1" })
    #expect(model.state.stepRecords.contains { $0.id == "planning-review-planner-response-2" })
    #expect(
        model.state.stepRecords.contains {
            $0.id == "planning-review-interactive-user-review" && $0.status == .inProgress
        })
}

func assertPlanningReviewMessageCounts(_ messages: [WorkflowMessage]) {
    #expect(messages.count == 11)
    #expect(messages.filter { $0.kind == .submittedPlan }.count == 1)
    #expect(messages.filter { $0.kind == .currentPlan }.count == 2)
    #expect(messages.filter { $0.kind == .reviewerFeedback }.count == 4)
    #expect(messages.filter { $0.kind == .consolidatedReview }.count == 2)
    #expect(messages.filter { $0.kind == .plannerResponse }.count == 2)
}

@MainActor
func makePlanningReviewWorkflowRunner() -> PlanningReviewWorkflowRunner {
    makePlanningReviewWorkflowRunner(backendAdapter: MockHarnessBackendAdapter())
}

@MainActor
func makePlanningReviewWorkflowRunner(
    backendAdapter: any HarnessBackendAdapter
) -> PlanningReviewWorkflowRunner {
    PlanningReviewWorkflowRunner(
        automation: PlanningReviewPrototypeAutomation(
            agentStep: CodexAgentStep(backendAdapter: backendAdapter)
        ))
}

@MainActor
func makePlanningReviewModel(projectURL: URL) -> WorkflowRunnerModel {
    makePlanningReviewModel(
        projectURL: projectURL,
        backendAdapter: MockHarnessBackendAdapter(),
        messageStore: PlanningReviewMessageStore()
    )
}

@MainActor
func makePlanningReviewModel(
    projectURL: URL,
    backendAdapter: any HarnessBackendAdapter,
    messageStore: any PlanningReviewMessagePersisting
) -> WorkflowRunnerModel {
    let project = WorkflowProject(url: projectURL, bookmarkData: nil)
    return WorkflowRunnerModel(
        projectStore: StaticProjectStore(project: project),
        projectPicker: EmptyProjectPicker(),
        branchReader: GitBranchReader(
            processRunner: RecordingProcessRunner(results: [ProcessResult(exitCode: 0, output: "main")])
        ),
        builtInWorkflowCatalog: .production(processRunner: RecordingProcessRunner(results: [])),
        externalWorkflowDiscovery: ExternalWorkflowDiscovery(
            environment: [:],
            processRunner: RecordingProcessRunner(results: [])
        ),
        externalWorkflowRunner: ExternalWorkflowRunner(),
        planningReviewServices: PlanningReviewServices(
            backendAdapter: backendAdapter,
            messageStore: messageStore
        ),
        environment: [:]
    )
}

@MainActor
func makePlanningReviewModel(
    projectURL: URL,
    messageStore: any PlanningReviewMessagePersisting
) -> WorkflowRunnerModel {
    makePlanningReviewModel(
        projectURL: projectURL,
        backendAdapter: MockHarnessBackendAdapter(),
        messageStore: messageStore
    )
}

@MainActor
func makePlanningReviewModel(
    projectURL: URL,
    backendAdapter: any HarnessBackendAdapter
) -> WorkflowRunnerModel {
    makePlanningReviewModel(
        projectURL: projectURL,
        backendAdapter: backendAdapter,
        messageStore: PlanningReviewMessageStore()
    )
}

func makeInteractiveOutput(content: String) -> InteractiveStepOutput {
    InteractiveStepOutput(
        producerStepID: "interactive-planning",
        artifact: InteractiveStepArtifact(
            title: "Submitted Plan",
            contentType: "text/markdown; artifact=plan",
            content: content,
            projectRelativePath: ".hephaestus/planning-review/session/plan.md"
        ),
        summary: "Submitted plan"
    )
}

func makeCurrentPlanWorkflowMessage() -> WorkflowMessage {
    WorkflowMessage(
        runID: "planning-review-test-run",
        kind: .currentPlan,
        producerStepID: "planning-review-planner-response-1",
        payload: .currentPlan(
            CurrentPlanMessagePayload(
                sourceMessageID: "submitted-plan",
                cycle: 1,
                contentType: "text/markdown; artifact=plan",
                content: validPlanMarkdown,
                projectRelativePath: ".hephaestus/planning-review/session/plan.md"
            )
        ),
        summary: "Current plan"
    )
}

func makeConsolidatedReviewWithFailedReviewer(
    reviewedMessageID: WorkflowMessage.ID,
    runID: WorkflowRun.ID
) -> WorkflowMessage {
    WorkflowMessage(
        runID: runID,
        kind: .consolidatedReview,
        producerStepID: "planning-review-consolidated-review-1",
        payload: .consolidatedReview(
            ConsolidatedReviewMessagePayload(
                reviewedMessageID: reviewedMessageID,
                cycle: 1,
                reviewerMessageIDs: ["reviewer-b-message"],
                failedReviewers: [
                    FailedReviewerMessagePayload(
                        reviewerName: "Reviewer A",
                        stepID: "planning-review-reviewer-1-1",
                        exitCode: 1,
                        details: "Reviewer A failed"
                    )
                ],
                feedback: "Reviewer B:\npass"
            )
        ),
        summary: "Consolidated review"
    )
}

@MainActor
func assertPlannerResponsePromptIncludesFailedReviewerState(projectURL: URL) throws {
    let project = WorkflowProject(url: projectURL, bookmarkData: nil)
    let currentPlanMessage = makeCurrentPlanWorkflowMessage()
    let reviewMessage = makeConsolidatedReviewWithFailedReviewer(
        reviewedMessageID: currentPlanMessage.id,
        runID: currentPlanMessage.runID
    )

    let prompt = PlanningReviewPrototypeAutomation(
        agentStep: CodexAgentStep(backendAdapter: MockHarnessBackendAdapter())
    )
    .plannerResponsePrompt(
        project: project,
        currentPlanMessage: currentPlanMessage,
        reviewMessage: reviewMessage
    )

    #expect(prompt.contains("Reviewer B:\npass"))
    #expect(prompt.contains("Failed reviewers:"))
    #expect(prompt.contains("Reviewer A (planning-review-reviewer-1-1) failed with exit code 1"))
    #expect(prompt.contains("Reviewer A failed"))
}

private struct StaticProjectStore: ProjectStore {
    let project: WorkflowProject

    func load() -> ProjectStoreSnapshot {
        ProjectStoreSnapshot(projects: [project], selectedProjectID: project.id)
    }

    func saveProjects(_ projects: [WorkflowProject]) {}

    func saveSelectedProjectID(_ id: WorkflowProject.ID?) {}
}

private struct EmptyProjectPicker: ProjectPicker {
    func pickProject() throws -> WorkflowProject? { nil }
}

struct SelectivePlanningReviewBackendAdapter: HarnessBackendAdapter {
    let failingReviewerNames: Set<String>

    func startSession(_ request: StartSessionRequest) async throws -> BackendSession {
        BackendSession(
            id: UUID().uuidString,
            backendName: "selective-test",
            project: request.project
        )
    }

    func resumeSession(_ request: ResumeSessionRequest) async throws -> BackendSession {
        request.session
    }

    func startTurn(_ request: StartTurnRequest) async throws -> AsyncThrowingStream<BackendEvent, Error> {
        AsyncThrowingStream { continuation in
            continuation.yield(.turnStarted(sessionID: request.session.id))
            if let reviewerName = failingReviewerName(in: request.prompt) {
                continuation.yield(
                    .turnFailed(ProcessResult(exitCode: 1, output: "\(reviewerName) failed"))
                )
            } else {
                continuation.yield(.outputChunk("pass"))
                continuation.yield(.turnCompleted(ProcessResult(exitCode: 0, output: "pass")))
            }
            continuation.finish()
        }
    }

    func respondToApproval(_ response: ApprovalResponse) async throws {}

    func cancelTurn(_ request: CancelTurnRequest) async throws {}

    private func failingReviewerName(in prompt: String) -> String? {
        failingReviewerNames.first { prompt.contains("You are \($0),") }
    }
}

struct PlannerResponseFailingPlanningReviewBackendAdapter: HarnessBackendAdapter {
    func startSession(_ request: StartSessionRequest) async throws -> BackendSession {
        BackendSession(
            id: UUID().uuidString,
            backendName: "planner-response-failing-test",
            project: request.project
        )
    }

    func resumeSession(_ request: ResumeSessionRequest) async throws -> BackendSession {
        request.session
    }

    func startTurn(_ request: StartTurnRequest) async throws -> AsyncThrowingStream<BackendEvent, Error> {
        AsyncThrowingStream { continuation in
            continuation.yield(.turnStarted(sessionID: request.session.id))
            if request.prompt.contains("You are the planner agent responding") {
                continuation.yield(
                    .turnFailed(ProcessResult(exitCode: 1, output: "Planner response failed"))
                )
            } else {
                continuation.yield(.outputChunk("pass"))
                continuation.yield(.turnCompleted(ProcessResult(exitCode: 0, output: "pass")))
            }
            continuation.finish()
        }
    }

    func respondToApproval(_ response: ApprovalResponse) async throws {}

    func cancelTurn(_ request: CancelTurnRequest) async throws {}
}

final class FailingAfterFirstPlanningReviewMessageStore: PlanningReviewMessagePersisting {
    private var callCount = 0

    func persistMessages(
        _ messages: [WorkflowMessage],
        project: WorkflowProject,
        sessionID: String
    ) throws -> [String] {
        callCount += 1
        if callCount > 1 {
            throw PersistenceFailure()
        }
        return messages.map {
            PlanningReviewMessageStore.relativeMessagePath(sessionID: sessionID, messageID: $0.id)
        }
    }

    private struct PersistenceFailure: LocalizedError {
        var errorDescription: String? {
            "Intentional workflow message persistence failure."
        }
    }
}

let validPlanMarkdown = """
    # Plan

    ## Summary
    Build the interactive planning workflow.

    ## Scope
    - Generate and submit a plan.

    ## Non-Goals
    - Do not build the full workflow builder.

    ## Implementation Approach
    - Materialize the selected draft.

    ## Validation
    - Run focused unit tests.

    ## Open Questions
    - What is the long-term pause envelope?
    """
