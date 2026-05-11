import Foundation

nonisolated enum WorkflowBuilderSchema {
    static let currentVersion = 1
}

nonisolated struct WorkflowGraphDefinition: Codable, Identifiable, Equatable {
    var id: String
    var schemaVersion: Int
    var metadata: WorkflowGraphMetadata
    var nodes: [WorkflowNode]
    var links: [WorkflowLink]
    var loops: [WorkflowLoop]
    var actors: [WorkflowActorProfile]

    init(
        id: String,
        schemaVersion: Int = WorkflowBuilderSchema.currentVersion,
        metadata: WorkflowGraphMetadata,
        nodes: [WorkflowNode] = [],
        links: [WorkflowLink] = [],
        loops: [WorkflowLoop] = [],
        actors: [WorkflowActorProfile] = []
    ) {
        self.id = id
        self.schemaVersion = schemaVersion
        self.metadata = metadata
        self.nodes = nodes
        self.links = links
        self.loops = loops
        self.actors = actors
    }
}

nonisolated struct WorkflowGraphMetadata: Codable, Equatable {
    var title: String
    var summary: String
    var createdAt: Date
    var updatedAt: Date
}

nonisolated struct WorkflowNode: Codable, Identifiable, Equatable {
    var id: String
    var title: String
    var role: WorkflowStepRole
    var executionMode: WorkflowExecutionMode
    var actorID: String
    var instructions: String
    var inputs: [WorkflowIODeclaration]
    var outputs: [WorkflowIODeclaration]
    var capabilityScope: WorkflowCapabilityScope
    var approvalPolicy: WorkflowApprovalPolicy
    var position: WorkflowCanvasPosition

    init(
        id: String,
        title: String,
        role: WorkflowStepRole,
        executionMode: WorkflowExecutionMode,
        actorID: String,
        instructions: String,
        inputs: [WorkflowIODeclaration] = [],
        outputs: [WorkflowIODeclaration] = [],
        capabilityScope: WorkflowCapabilityScope = .codexReadOnly,
        approvalPolicy: WorkflowApprovalPolicy = .none,
        position: WorkflowCanvasPosition
    ) {
        self.id = id
        self.title = title
        self.role = role
        self.executionMode = executionMode
        self.actorID = actorID
        self.instructions = instructions
        self.inputs = inputs
        self.outputs = outputs
        self.capabilityScope = capabilityScope
        self.approvalPolicy = approvalPolicy
        self.position = position
    }
}

nonisolated enum WorkflowStepRole: String, CaseIterable, Codable, Equatable, Identifiable {
    case planning
    case implementation
    case review
    case terminalAssisted
    case interactiveCodex
    case automatedExecution

    var id: String { rawValue }

    var title: String {
        switch self {
        case .planning:
            "Planning"
        case .implementation:
            "Implementation"
        case .review:
            "Review"
        case .terminalAssisted:
            "Terminal-assisted"
        case .interactiveCodex:
            "Interactive Codex"
        case .automatedExecution:
            "Automated"
        }
    }
}

nonisolated enum WorkflowExecutionMode: String, CaseIterable, Codable, Equatable, Identifiable {
    case automatic
    case interactivePause
    case approvalGate
    case terminalAssisted
    case separateCodexInstance
    case manualOnly

    var id: String { rawValue }

    var title: String {
        switch self {
        case .automatic:
            "Automatic"
        case .interactivePause:
            "Interactive pause"
        case .approvalGate:
            "Approval gate"
        case .terminalAssisted:
            "Terminal-assisted"
        case .separateCodexInstance:
            "Separate Codex"
        case .manualOnly:
            "Manual only"
        }
    }
}

nonisolated struct WorkflowIODeclaration: Codable, Identifiable, Equatable {
    var id: String
    var name: String
    var valueKind: WorkflowValueKind
    var required: Bool
}

nonisolated enum WorkflowValueKind: String, CaseIterable, Codable, Equatable, Identifiable {
    case message
    case artifactReference
    case decision
    case plan
    case reviewFeedback
    case terminalTranscript
    case approvalResult
    case opaqueJSON

    var id: String { rawValue }
}

nonisolated struct WorkflowLink: Codable, Identifiable, Equatable {
    var id: String
    var fromNodeID: String
    var fromOutputID: String?
    var toNodeID: String
    var toInputID: String?
    var kind: WorkflowLinkKind
}

nonisolated enum WorkflowLinkKind: String, CaseIterable, Codable, Equatable, Identifiable {
    case control
    case data
    case artifact
    case decision
    case approval

    var id: String { rawValue }

    var title: String {
        rawValue.prefix(1).uppercased() + rawValue.dropFirst()
    }
}

nonisolated struct WorkflowLoop: Codable, Identifiable, Equatable {
    var id: String
    var title: String
    var memberNodeIDs: [String]
    var entryNodeIDs: [String]
    var exitNodeIDs: [String]
    var stopCondition: WorkflowLoopStopCondition
    var userBreakpointNodeIDs: [String]
}

nonisolated enum WorkflowLoopStopCondition: Codable, Equatable {
    case maxIterations(Int)
    case untilApproval(maxIterations: Int)
    case untilReviewPasses(maxIterations: Int)
    case untilNoBlockingFindings(maxIterations: Int)
    case manual
}

nonisolated extension WorkflowLoopStopCondition {
    var label: String {
        switch self {
        case .maxIterations(let count):
            "Max \(count) iterations"
        case .untilApproval(let count):
            "Until approval, max \(count)"
        case .untilReviewPasses(let count):
            "Until review passes, max \(count)"
        case .untilNoBlockingFindings(let count):
            "Until no blocking findings, max \(count)"
        case .manual:
            "Manual stop"
        }
    }

    var maxIterations: Int? {
        switch self {
        case .maxIterations(let count),
            .untilApproval(let count),
            .untilReviewPasses(let count),
            .untilNoBlockingFindings(let count):
            count
        case .manual:
            nil
        }
    }
}

nonisolated struct WorkflowActorProfile: Codable, Identifiable, Equatable {
    var id: String
    var displayName: String
    var backend: WorkflowBackendKind
    var rolePrompt: String
    var instancePolicy: WorkflowActorInstancePolicy
    var defaultCapabilityScope: WorkflowCapabilityScope
}

nonisolated enum WorkflowBackendKind: String, CaseIterable, Codable, Equatable, Identifiable {
    case codex
    case foundry
    case claudeCode
    case custom

    var id: String { rawValue }
}

nonisolated enum WorkflowActorInstancePolicy: String, CaseIterable, Codable, Equatable, Identifiable {
    case reuseWithinRun
    case newInstancePerStep
    case newInstancePerIteration

    var id: String { rawValue }
}

nonisolated struct WorkflowCapabilityScope: Codable, Equatable {
    var allowedSkills: [String]
    var allowedMCPServers: [String]
    var allowedTools: [String]
    var filesystemPolicy: WorkflowFilesystemPolicy
    var networkPolicy: WorkflowNetworkPolicy

    static let codexReadOnly = WorkflowCapabilityScope(
        allowedSkills: [],
        allowedMCPServers: [],
        allowedTools: [],
        filesystemPolicy: .readOnly,
        networkPolicy: .disabled
    )

    static let codexWorkspaceWrite = WorkflowCapabilityScope(
        allowedSkills: [],
        allowedMCPServers: [],
        allowedTools: ["shell", "apply_patch"],
        filesystemPolicy: .workspaceWrite,
        networkPolicy: .disabled
    )
}

nonisolated enum WorkflowFilesystemPolicy: String, CaseIterable, Codable, Equatable, Identifiable {
    case readOnly
    case workspaceWrite
    case approvalRequired

    var id: String { rawValue }
}

nonisolated enum WorkflowNetworkPolicy: String, CaseIterable, Codable, Equatable, Identifiable {
    case disabled
    case allowed
    case approvalRequired

    var id: String { rawValue }
}

nonisolated enum WorkflowApprovalPolicy: String, CaseIterable, Codable, Equatable, Identifiable {
    case none
    case beforeStart
    case beforeContinue
    case beforeToolUse

    var id: String { rawValue }
}

nonisolated struct WorkflowCanvasPosition: Codable, Equatable {
    var x: Double
    var y: Double
}
