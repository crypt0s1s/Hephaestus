import Foundation

nonisolated struct WorkflowValidationIssue: Identifiable, Equatable {
    let id: String
    let severity: WorkflowValidationSeverity
    let location: WorkflowValidationLocation
    let code: WorkflowValidationCode
    let message: String
    let suggestedFix: String?
}

nonisolated enum WorkflowValidationSeverity: String, Equatable {
    case error
    case warning
}

nonisolated enum WorkflowValidationLocation: Equatable {
    case workflow
    case node(String)
    case link(String)
    case loop(String)
    case actor(String)
}

nonisolated enum WorkflowValidationCode: String, Equatable {
    case unsupportedSchemaVersion
    case duplicateID
    case missingStartNode
    case missingNodeTitle
    case missingInstructions
    case missingActor
    case unresolvedActor
    case danglingLink
    case unresolvedBinding
    case incompatibleBinding
    case invalidLoop
    case unboundedLoop
    case unresolvedCapability
    case missingApprovalGate
}

nonisolated struct WorkflowValidationResult: Equatable {
    let issues: [WorkflowValidationIssue]

    var hasBlockingIssues: Bool {
        issues.contains { $0.severity == .error }
    }
}

nonisolated struct WorkflowDefinitionValidator {
    var knownSkills: Set<String> = []
    var knownMCPServers: Set<String> = []
    var knownTools: Set<String> = ["shell", "apply_patch"]

    func validate(_ definition: WorkflowGraphDefinition) -> WorkflowValidationResult {
        var issues: [WorkflowValidationIssue] = []
        if definition.schemaVersion > WorkflowBuilderSchema.currentVersion {
            issues.append(issue(
                .unsupportedSchemaVersion,
                .workflow,
                "Schema version \(definition.schemaVersion) is newer than this app supports."
            ))
        }

        issues.append(contentsOf: duplicateIDIssues(definition))
        issues.append(contentsOf: startNodeIssues(definition))
        issues.append(contentsOf: nodeIssues(definition))
        issues.append(contentsOf: linkIssues(definition))
        issues.append(contentsOf: loopIssues(definition))

        return WorkflowValidationResult(issues: issues)
    }

    private func duplicateIDIssues(_ definition: WorkflowGraphDefinition) -> [WorkflowValidationIssue] {
        let ids = definition.nodes.map(\.id)
            + definition.links.map(\.id)
            + definition.loops.map(\.id)
            + definition.actors.map(\.id)
        let duplicates = Dictionary(grouping: ids, by: { $0 }).filter { $0.value.count > 1 }.keys
        return duplicates.map {
            issue(.duplicateID, .workflow, "Duplicate workflow identifier '\($0)' must be unique.")
        }
    }

    private func startNodeIssues(_ definition: WorkflowGraphDefinition) -> [WorkflowValidationIssue] {
        guard !definition.nodes.isEmpty else {
            return [issue(.missingStartNode, .workflow, "Add at least one workflow step.")]
        }
        let incomingNodeIDs = Set(definition.links.map(\.toNodeID))
        let startNodes = definition.nodes.filter { !incomingNodeIDs.contains($0.id) }
        if startNodes.count == 1 {
            return []
        }
        return [
            issue(
                .missingStartNode,
                .workflow,
                startNodes.isEmpty
                    ? "Workflow needs an explicit start step; all steps currently have incoming links."
                    : "Workflow has multiple possible start steps. Connect the graph or choose a start policy."
            )
        ]
    }

    private func nodeIssues(_ definition: WorkflowGraphDefinition) -> [WorkflowValidationIssue] {
        var issues: [WorkflowValidationIssue] = []
        let actorIDs = Set(definition.actors.map(\.id))
        for node in definition.nodes {
            if node.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                issues.append(issue(.missingNodeTitle, .node(node.id), "Step title is required."))
            }
            if node.instructions.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                issues.append(issue(.missingInstructions, .node(node.id), "Step instructions are required."))
            }
            if node.actorID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                issues.append(issue(.missingActor, .node(node.id), "Step needs an actor."))
            } else if !actorIDs.contains(node.actorID) {
                issues.append(issue(.unresolvedActor, .node(node.id), "Step references missing actor '\(node.actorID)'."))
            }
            if node.executionMode == .approvalGate && node.approvalPolicy == .none {
                issues.append(issue(
                    .missingApprovalGate,
                    .node(node.id),
                    "Approval-gated steps must declare an approval policy."
                ))
            }
            issues.append(contentsOf: capabilityIssues(node))
        }
        return issues
    }

    private func capabilityIssues(_ node: WorkflowNode) -> [WorkflowValidationIssue] {
        var issues: [WorkflowValidationIssue] = []
        for skill in node.capabilityScope.allowedSkills where !knownSkills.contains(skill) {
            issues.append(issue(
                .unresolvedCapability,
                .node(node.id),
                "Skill '\(skill)' is not available in the current catalog.",
                severity: .warning
            ))
        }
        for server in node.capabilityScope.allowedMCPServers where !knownMCPServers.contains(server) {
            issues.append(issue(
                .unresolvedCapability,
                .node(node.id),
                "MCP server '\(server)' is not available in the current catalog.",
                severity: .warning
            ))
        }
        for tool in node.capabilityScope.allowedTools where !knownTools.contains(tool) {
            issues.append(issue(
                .unresolvedCapability,
                .node(node.id),
                "Tool '\(tool)' is not available in the current catalog."
            ))
        }
        return issues
    }

    private func linkIssues(_ definition: WorkflowGraphDefinition) -> [WorkflowValidationIssue] {
        var issues: [WorkflowValidationIssue] = []
        let nodesByID = Dictionary(uniqueKeysWithValues: definition.nodes.map { ($0.id, $0) })
        for link in definition.links {
            guard let from = nodesByID[link.fromNodeID], let to = nodesByID[link.toNodeID] else {
                issues.append(issue(.danglingLink, .link(link.id), "Link references a missing step."))
                continue
            }
            let output = link.fromOutputID.flatMap { id in from.outputs.first { $0.id == id } }
            let input = link.toInputID.flatMap { id in to.inputs.first { $0.id == id } }
            if link.kind != .control {
                if output == nil || input == nil {
                    issues.append(issue(
                        .unresolvedBinding,
                        .link(link.id),
                        "Non-control links must bind a source output to a target input."
                    ))
                } else if output?.valueKind != input?.valueKind {
                    issues.append(issue(
                        .incompatibleBinding,
                        .link(link.id),
                        "Link binds incompatible output and input value kinds."
                    ))
                }
            }
        }
        return issues
    }

    private func loopIssues(_ definition: WorkflowGraphDefinition) -> [WorkflowValidationIssue] {
        var issues: [WorkflowValidationIssue] = []
        let nodeIDs = Set(definition.nodes.map(\.id))
        for loop in definition.loops {
            if loop.memberNodeIDs.isEmpty || loop.entryNodeIDs.isEmpty || loop.exitNodeIDs.isEmpty {
                issues.append(issue(.invalidLoop, .loop(loop.id), "Loop needs member, entry, and exit steps."))
            }
            let referencedIDs = Set(
                loop.memberNodeIDs
                    + loop.entryNodeIDs
                    + loop.exitNodeIDs
                    + loop.userBreakpointNodeIDs
            )
            if !referencedIDs.isSubset(of: nodeIDs) {
                issues.append(issue(.invalidLoop, .loop(loop.id), "Loop references steps that no longer exist."))
            }
            if loop.stopCondition.maxIterations == nil && loop.userBreakpointNodeIDs.isEmpty {
                issues.append(issue(.unboundedLoop, .loop(loop.id), "Loop needs a max iteration count or a user breakpoint."))
            }
            if let maxIterations = loop.stopCondition.maxIterations, maxIterations < 1 {
                issues.append(issue(.unboundedLoop, .loop(loop.id), "Loop max iterations must be at least 1."))
            }
        }
        return issues
    }

    private func issue(
        _ code: WorkflowValidationCode,
        _ location: WorkflowValidationLocation,
        _ message: String,
        severity: WorkflowValidationSeverity = .error,
        suggestedFix: String? = nil
    ) -> WorkflowValidationIssue {
        WorkflowValidationIssue(
            id: "\(code.rawValue)-\(message)",
            severity: severity,
            location: location,
            code: code,
            message: message,
            suggestedFix: suggestedFix
        )
    }
}
