import Foundation

@testable import Hephaestus

func makeTemporaryPlanningProject() throws -> URL {
    let url = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("hephaestus-planning-review-tests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

@MainActor
func makePlanningReviewWorkflowRunner() -> PlanningReviewWorkflowRunner {
    PlanningReviewWorkflowRunner(
        automation: PlanningReviewPrototypeAutomation(
            agent: CodexPlanningAgentRunner(backendAdapter: MockHarnessBackendAdapter()),
            artifactStore: PlanningPlanArtifactStore()
        ))
}

@MainActor
func makePlanningReviewModel(
    projectURL: URL,
    backendAdapter: any HarnessBackendAdapter = MockHarnessBackendAdapter(),
    planArtifactMaterializer: (any PlanningPlanArtifactMaterializing)? = nil
) -> WorkflowRunnerModel {
    let project = WorkflowProject(url: projectURL, bookmarkData: nil)
    let planningReviewServices = PlanningReviewServices(
        backendAdapter: backendAdapter,
        planArtifactMaterializer: planArtifactMaterializer ?? PlanningPlanArtifactStore()
    )
    let interactiveSessionStore = WorkflowInteractiveSessionStore()
    return WorkflowRunnerModel(
        projectStore: StaticProjectStore(project: project),
        projectPicker: EmptyProjectPicker(),
        branchReader: GitBranchReader(
            processRunner: RecordingProcessRunner(results: [ProcessResult(exitCode: 0, output: "main")])
        ),
        builtInWorkflowCatalog: .production(
            processRunner: RecordingProcessRunner(results: []),
            environment: [:],
            interactiveSessionStore: interactiveSessionStore,
            planningReviewServices: planningReviewServices
        ),
        externalWorkflowDiscovery: ExternalWorkflowDiscovery(
            environment: [:],
            processRunner: RecordingProcessRunner(results: [])
        ),
        externalWorkflowRunner: ExternalWorkflowRunner(),
        interactiveSessionStore: interactiveSessionStore,
        environment: [:]
    )
}

struct StaticProjectStore: ProjectStore {
    let project: WorkflowProject

    func load() -> ProjectStoreSnapshot {
        ProjectStoreSnapshot(projects: [project], selectedProjectID: project.id)
    }

    func saveProjects(_ projects: [WorkflowProject]) {}

    func saveSelectedProjectID(_ id: WorkflowProject.ID?) {}
}

struct EmptyProjectPicker: ProjectPicker {
    func pickProject() throws -> WorkflowProject? { nil }
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

let alternateValidPlanMarkdown = """
    # Plan

    ## Summary
    Build the edited interactive planning workflow.

    ## Scope
    - Promote the edited draft.

    ## Non-Goals
    - Do not use the original generated draft after edits.

    ## Implementation Approach
    - Accept the current editor candidate.

    ## Validation
    - Verify the accepted artifact content.

    ## Open Questions
    - None.
    """

struct PersistedPlanningAcceptanceRecordForTests: Decodable {
    let kind: String
    let outputID: String
    let acceptedRevision: Int
    let contentHash: String
    let acceptedAt: Date
    let idempotencyKey: String
    let contentType: String
    let content: String
    let projectRelativePath: String
}

func loadPersistedPlanningAcceptanceRecord(
    projectURL: URL,
    sessionID: String,
    kind: PersistedPlanningAcceptanceKindForTests
) throws -> PersistedPlanningAcceptanceRecordForTests {
    let acceptanceURL = projectURL.appendingPathComponent(kind.path(sessionID: sessionID))
    let data = try Data(contentsOf: acceptanceURL)
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return try decoder.decode(PersistedPlanningAcceptanceRecordForTests.self, from: data)
}

enum PersistedPlanningAcceptanceKindForTests {
    case draft
    case final

    func path(sessionID: String) -> String {
        switch self {
        case .draft:
            return PlanningPlanArtifactPolicy.draftAcceptanceRecordPath(sessionID: sessionID)
        case .final:
            return PlanningPlanArtifactPolicy.finalAcceptanceRecordPath(sessionID: sessionID)
        }
    }
}
