import Combine
import Foundation

@MainActor
final class WorkflowBuilderModel: ObservableObject {
    @Published private(set) var state = WorkflowBuilderState()

    private let store: WorkflowDefinitionStore
    private let validator: WorkflowDefinitionValidator

    init(
        store: WorkflowDefinitionStore = WorkflowDefinitionStore(),
        validator: WorkflowDefinitionValidator = WorkflowDefinitionValidator()
    ) {
        self.store = store
        self.validator = validator
    }

    func setProject(_ project: WorkflowProject) {
        guard state.projectID != project.id else { return }
        var nextState = WorkflowBuilderState(projectID: project.id)
        do {
            nextState.savedDefinitions = try store.loadDefinitions(project: project)
            nextState.definition = nextState.savedDefinitions.first ?? WorkflowPatternLibrary.planningLoop()
            nextState.selectedNodeID = nextState.definition?.nodes.first?.id
            nextState.validationResult = nextState.definition.map(validator.validate)
            nextState.statusMessage = nextState.savedDefinitions.isEmpty
                ? "Started from the planning loop pattern."
                : "Loaded \(nextState.savedDefinitions.count) saved workflow definition(s)."
        } catch {
            nextState.definition = WorkflowPatternLibrary.planningLoop()
            nextState.selectedNodeID = nextState.definition?.nodes.first?.id
            nextState.validationResult = nextState.definition.map(validator.validate)
            nextState.statusMessage = "Could not load saved workflows: \(error)"
        }
        state = nextState
    }

    func createEmptyWorkflow() {
        replaceDefinition(WorkflowPatternLibrary.emptyWorkflow())
    }

    func insertPattern(_ pattern: WorkflowBuilderPattern) {
        switch pattern {
        case .planningLoop:
            replaceDefinition(WorkflowPatternLibrary.planningLoop())
        case .reviewLoop:
            replaceDefinition(WorkflowPatternLibrary.reviewLoop())
        case .implementationLoop:
            replaceDefinition(WorkflowPatternLibrary.implementationLoop())
        }
    }

    func selectNode(_ nodeID: String) {
        state.selectedNodeID = nodeID
    }

    func updateTitle(_ title: String) {
        updateDefinition {
            $0.metadata.title = title
            $0.metadata.updatedAt = Date()
        }
    }

    func updateSummary(_ summary: String) {
        updateDefinition {
            $0.metadata.summary = summary
            $0.metadata.updatedAt = Date()
        }
    }

    func updateSelectedNodeTitle(_ title: String) {
        updateSelectedNode { $0.title = title }
    }

    func updateSelectedNodeInstructions(_ instructions: String) {
        updateSelectedNode { $0.instructions = instructions }
    }

    func updateSelectedNodeRole(_ role: WorkflowStepRole) {
        updateSelectedNode { $0.role = role }
    }

    func updateSelectedNodeExecutionMode(_ mode: WorkflowExecutionMode) {
        updateSelectedNode { node in
            node.executionMode = mode
            if mode == .approvalGate && node.approvalPolicy == .none {
                node.approvalPolicy = .beforeContinue
            }
        }
    }

    func updateSelectedNodeActor(_ actorID: String) {
        updateSelectedNode { $0.actorID = actorID }
    }

    func updateSelectedNodeToolList(_ tools: String) {
        updateSelectedNode {
            $0.capabilityScope.allowedTools = Self.commaSeparatedValues(from: tools)
        }
    }

    func updateSelectedNodeSkillList(_ skills: String) {
        updateSelectedNode {
            $0.capabilityScope.allowedSkills = Self.commaSeparatedValues(from: skills)
        }
    }

    func updateSelectedNodeMCPList(_ servers: String) {
        updateSelectedNode {
            $0.capabilityScope.allowedMCPServers = Self.commaSeparatedValues(from: servers)
        }
    }

    func updateSelectedNodeInputs(_ inputs: String) {
        updateSelectedNode {
            $0.inputs = Self.ioDeclarations(from: inputs, prefix: "input")
        }
    }

    func updateSelectedNodeOutputs(_ outputs: String) {
        updateSelectedNode {
            $0.outputs = Self.ioDeclarations(from: outputs, prefix: "output")
        }
    }

    func updateSelectedNodeFilesystemPolicy(_ policy: WorkflowFilesystemPolicy) {
        updateSelectedNode { $0.capabilityScope.filesystemPolicy = policy }
    }

    func updateSelectedNodeNetworkPolicy(_ policy: WorkflowNetworkPolicy) {
        updateSelectedNode { $0.capabilityScope.networkPolicy = policy }
    }

    func addStep() {
        updateDefinition { definition in
            let actorID = definition.actors.first?.id ?? "actor-codex-collaborator"
            if definition.actors.isEmpty {
                definition.actors.append(
                    WorkflowActorProfile(
                        id: actorID,
                        displayName: "Codex collaborator",
                        backend: .codex,
                        rolePrompt: "You are a Codex collaborator in a Hephaestus workflow.",
                        instancePolicy: .newInstancePerStep,
                        defaultCapabilityScope: .codexReadOnly
                    ))
            }
            let index = definition.nodes.count + 1
            let node = WorkflowNode(
                id: "step-\(UUID().uuidString.lowercased())",
                title: "Step \(index)",
                role: .automatedExecution,
                executionMode: .automatic,
                actorID: actorID,
                instructions: "Describe what this step should do.",
                inputs: [WorkflowIODeclaration(id: "input", name: "Input", valueKind: .message, required: false)],
                outputs: [WorkflowIODeclaration(id: "output", name: "Output", valueKind: .message, required: true)],
                position: WorkflowCanvasPosition(
                    x: 80 + Double(index - 1) * 220,
                    y: 300 + Double((index - 1) % 2) * 90
                )
            )
            definition.nodes.append(node)
            state.selectedNodeID = node.id
        }
    }

    func connectSelectedToNext() {
        guard var definition = state.definition, let selectedNodeID = state.selectedNodeID,
            let selectedIndex = definition.nodes.firstIndex(where: { $0.id == selectedNodeID }),
            selectedIndex + 1 < definition.nodes.count
        else { return }
        let from = definition.nodes[selectedIndex]
        let to = definition.nodes[selectedIndex + 1]
        let output = from.outputs.first
        let compatibleInput = output.flatMap { output in
            to.inputs.first { $0.valueKind == output.valueKind }
        } ?? to.inputs.first
        definition.links.append(
            WorkflowLink(
                id: "link-\(UUID().uuidString.lowercased())",
                fromNodeID: from.id,
                fromOutputID: output?.id,
                toNodeID: to.id,
                toInputID: compatibleInput?.id,
                kind: output == nil ? .control : .data
            ))
        replaceDefinition(definition, status: "Connected \(from.title) to \(to.title).")
    }

    func deleteSelectedNode() {
        guard var definition = state.definition, let selectedNodeID = state.selectedNodeID else { return }
        definition.nodes.removeAll { $0.id == selectedNodeID }
        definition.links.removeAll { $0.fromNodeID == selectedNodeID || $0.toNodeID == selectedNodeID }
        for index in definition.loops.indices {
            definition.loops[index].memberNodeIDs.removeAll { $0 == selectedNodeID }
            definition.loops[index].entryNodeIDs.removeAll { $0 == selectedNodeID }
            definition.loops[index].exitNodeIDs.removeAll { $0 == selectedNodeID }
            definition.loops[index].userBreakpointNodeIDs.removeAll { $0 == selectedNodeID }
        }
        state.selectedNodeID = definition.nodes.first?.id
        replaceDefinition(definition, status: "Deleted selected step.")
    }

    func wrapAllStepsInLoop() {
        updateDefinition { definition in
            guard !definition.nodes.isEmpty else { return }
            definition.loops = [
                WorkflowLoop(
                    id: "loop-\(UUID().uuidString.lowercased())",
                    title: "Custom loop",
                    memberNodeIDs: definition.nodes.map(\.id),
                    entryNodeIDs: [definition.nodes.first?.id].compactMap { $0 },
                    exitNodeIDs: [definition.nodes.last?.id].compactMap { $0 },
                    stopCondition: .maxIterations(3),
                    userBreakpointNodeIDs: []
                )
            ]
        }
    }

    func updateFirstLoopStopPreset(_ preset: WorkflowLoopStopPreset) {
        updateDefinition { definition in
            guard !definition.loops.isEmpty else { return }
            let maxIterations = definition.loops[0].stopCondition.maxIterations ?? 3
            definition.loops[0].stopCondition = preset.stopCondition(maxIterations: maxIterations)
            if preset == .manual && definition.loops[0].userBreakpointNodeIDs.isEmpty {
                definition.loops[0].userBreakpointNodeIDs = definition.loops[0].exitNodeIDs
            }
        }
    }

    func updateFirstLoopMaxIterations(_ maxIterations: Int) {
        updateDefinition { definition in
            guard !definition.loops.isEmpty else { return }
            let clamped = max(1, maxIterations)
            switch definition.loops[0].stopCondition {
            case .maxIterations:
                definition.loops[0].stopCondition = .maxIterations(clamped)
            case .untilApproval:
                definition.loops[0].stopCondition = .untilApproval(maxIterations: clamped)
            case .untilReviewPasses:
                definition.loops[0].stopCondition = .untilReviewPasses(maxIterations: clamped)
            case .untilNoBlockingFindings:
                definition.loops[0].stopCondition = .untilNoBlockingFindings(maxIterations: clamped)
            case .manual:
                definition.loops[0].stopCondition = .maxIterations(clamped)
            }
        }
    }

    func validate() {
        guard let definition = state.definition else { return }
        state.validationResult = validator.validate(definition)
        if state.validationResult?.hasBlockingIssues == true {
            state.statusMessage = "Validation found blocking issues."
        } else {
            state.statusMessage = "Workflow definition is valid."
        }
    }

    func save(project: WorkflowProject) {
        guard var definition = state.definition else { return }
        definition.metadata.updatedAt = Date()
        do {
            try store.save(definition, project: project)
            let savedDefinitions = try store.loadDefinitions(project: project)
            state.definition = definition
            state.savedDefinitions = savedDefinitions
            state.validationResult = validator.validate(definition)
            state.statusMessage = "Saved \(definition.metadata.title)."
        } catch {
            state.statusMessage = "Could not save workflow: \(error)"
        }
    }

    func reopen(_ definitionID: String) {
        guard let definition = state.savedDefinitions.first(where: { $0.id == definitionID }) else { return }
        replaceDefinition(definition, status: "Opened \(definition.metadata.title).")
    }

    func normalizedDefinitionJSON() -> String {
        guard let definition = state.definition else { return "{}" }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(definition) else { return "{}" }
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    private func updateSelectedNode(_ mutate: (inout WorkflowNode) -> Void) {
        guard let selectedNodeID = state.selectedNodeID else { return }
        updateDefinition { definition in
            guard let index = definition.nodes.firstIndex(where: { $0.id == selectedNodeID }) else { return }
            mutate(&definition.nodes[index])
            definition.metadata.updatedAt = Date()
        }
    }

    private func updateDefinition(_ mutate: (inout WorkflowGraphDefinition) -> Void) {
        guard var definition = state.definition else { return }
        mutate(&definition)
        replaceDefinition(definition)
    }

    private func replaceDefinition(_ definition: WorkflowGraphDefinition, status: String? = nil) {
        state.definition = definition
        if state.selectedNodeID == nil || !definition.nodes.contains(where: { $0.id == state.selectedNodeID }) {
            state.selectedNodeID = definition.nodes.first?.id
        }
        state.validationResult = validator.validate(definition)
        state.statusMessage = status
    }

    private static func commaSeparatedValues(from value: String) -> [String] {
        value
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private static func ioDeclarations(from value: String, prefix: String) -> [WorkflowIODeclaration] {
        value
            .split(separator: ",")
            .enumerated()
            .map { index, item in
                let parts = item.split(separator: ":", maxSplits: 1)
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                let name = parts.first?.isEmpty == false ? parts[0] : "\(prefix.capitalized) \(index + 1)"
                let kindName = parts.count > 1 ? parts[1] : WorkflowValueKind.message.rawValue
                let kind = WorkflowValueKind.allCases.first {
                    $0.rawValue.caseInsensitiveCompare(kindName) == .orderedSame
                }
                    ?? .message
                return WorkflowIODeclaration(
                    id: index == 0 ? prefix : "\(prefix)-\(index + 1)",
                    name: name,
                    valueKind: kind,
                    required: true
                )
            }
    }
}
