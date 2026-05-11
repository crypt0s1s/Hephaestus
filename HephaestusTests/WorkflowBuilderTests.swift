import Foundation
import Testing

@testable import Hephaestus

struct WorkflowBuilderTests {
    @Test
    func bundledWorkflowPatternsAreValidAndCoverRequiredLoops() {
        let patterns = WorkflowPatternLibrary.allPatterns(now: Date(timeIntervalSince1970: 0))
        let validator = WorkflowDefinitionValidator()

        #expect(patterns.map(\.metadata.title) == ["Planning Loop", "Review Loop", "Implementation Loop"])
        for pattern in patterns {
            let result = validator.validate(pattern)
            #expect(!result.hasBlockingIssues, "\(pattern.metadata.title) should be valid: \(result.issues)")
            #expect(!pattern.nodes.isEmpty)
            #expect(!pattern.links.isEmpty)
            #expect(!pattern.loops.isEmpty)
        }
    }

    @Test
    func validatorReportsMissingActorIncompatibleBindingAndUnboundedLoop() {
        var definition = WorkflowPatternLibrary.planningLoop(now: Date(timeIntervalSince1970: 0))
        definition.nodes[0].actorID = "missing-actor"
        definition.nodes[1].inputs[0].valueKind = .message
        definition.loops[0].stopCondition = .manual
        definition.loops[0].userBreakpointNodeIDs = []

        let result = WorkflowDefinitionValidator().validate(definition)
        let codes = Set(result.issues.map(\.code))

        #expect(result.hasBlockingIssues)
        #expect(codes.contains(.unresolvedActor))
        #expect(codes.contains(.incompatibleBinding))
        #expect(codes.contains(.unboundedLoop))
    }

    @Test
    func workflowDefinitionStorePersistsProjectLocalDefinitions() throws {
        let project = WorkflowProject(url: try makeBuilderTemporaryProject(), bookmarkData: nil)
        let store = WorkflowDefinitionStore()
        var definition = WorkflowPatternLibrary.reviewLoop(now: Date(timeIntervalSince1970: 0))
        definition.metadata.title = "Saved Review Loop"

        try store.save(definition, project: project)
        let loaded = try store.loadDefinitions(project: project)
        let savedURL = URL(fileURLWithPath: project.path, isDirectory: true)
            .appendingPathComponent(".hephaestus/workflows/\(definition.id).workflow.json")

        #expect(FileManager.default.fileExists(atPath: savedURL.path))
        #expect(loaded.count == 1)
        #expect(loaded.first?.metadata.title == "Saved Review Loop")
        #expect(loaded.first?.nodes.map(\.id) == definition.nodes.map(\.id))
        #expect(loaded.first?.links.map(\.id) == definition.links.map(\.id))
    }
}

@MainActor
struct WorkflowBuilderModelTests {
    @Test
    func builderModelCreatesSavesLoadsAndReopensDefinitions() throws {
        let project = WorkflowProject(url: try makeBuilderTemporaryProject(), bookmarkData: nil)
        let model = WorkflowBuilderModel()

        model.setProject(project)
        model.createEmptyWorkflow()
        model.updateTitle("Project Custom Workflow")
        model.addStep()
        let firstStepID = try #require(model.state.selectedNodeID)
        model.addStep()
        model.selectNode(firstStepID)
        model.connectSelectedToNext()
        model.updateSelectedNodeInputs("Task:message")
        model.updateSelectedNodeOutputs("Result:message")
        model.wrapAllStepsInLoop()
        model.updateFirstLoopStopPreset(.untilApproval)
        model.updateFirstLoopMaxIterations(4)
        model.validate()

        #expect(model.state.definition?.metadata.title == "Project Custom Workflow")
        #expect(model.state.validationResult?.hasBlockingIssues == false)
        #expect(model.state.selectedNode?.inputs.first?.name == "Task")
        #expect(model.state.selectedNode?.outputs.first?.name == "Result")
        #expect(model.state.definition?.loops.first?.stopCondition.maxIterations == 4)

        model.save(project: project)
        let savedID = try #require(model.state.definition?.id)
        #expect(model.state.savedDefinitions.contains { $0.id == savedID })

        model.createEmptyWorkflow()
        #expect(model.state.definition?.id != savedID)

        model.reopen(savedID)
        #expect(model.state.definition?.id == savedID)
        #expect(model.normalizedDefinitionJSON().contains("Project Custom Workflow"))
    }
}

private func makeBuilderTemporaryProject() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("HephaestusWorkflowBuilderTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}
