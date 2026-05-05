import Foundation

public struct ToolDefinition: Sendable, Hashable, Codable {
    public let name: String
    public let description: String
    public let inputSchema: ToolInputSchema

    public init(name: String, description: String, inputSchema: ToolInputSchema) {
        self.name = name
        self.description = description
        self.inputSchema = inputSchema
    }
}

public struct ToolInputSchema: Sendable, Hashable, Codable {
    public let jsonSchema: String

    public init(jsonSchema: String) {
        self.jsonSchema = jsonSchema
    }
}

public enum ToolOperation: String, Sendable, Hashable, Codable {
    case write
    case edit
}

public enum ToolResultStatus: String, Sendable, Hashable, Codable {
    case succeeded
    case failed
    case denied
    case awaitingApproval
}

public struct ProviderToolCall: Sendable, Hashable, Codable, Identifiable {
    public let id: String
    public let name: String
    public let argumentsJSON: String

    public init(id: String, name: String, argumentsJSON: String) {
        self.id = id
        self.name = name
        self.argumentsJSON = argumentsJSON
    }
}

public struct ToolResultMessage: Sendable, Hashable, Codable {
    public let providerToolCallID: String
    public let toolName: String
    public let status: ToolResultStatus
    public let text: String

    public init(providerToolCallID: String, toolName: String, status: ToolResultStatus, text: String) {
        self.providerToolCallID = providerToolCallID
        self.toolName = toolName
        self.status = status
        self.text = text
    }
}

public struct PermissionGrant: Sendable, Hashable, Codable {
    public enum Source: String, Sendable, Hashable, Codable {
        case defaultCurrentDirectory
        case elevatedUserApproval
        case test
    }

    public let source: Source
    public let toolName: String
    public let operations: [ToolOperation]
    public let scope: PermissionScope
    public let lifetime: GrantLifetime
    public let providerToolCallID: String?

    public init(
        source: Source,
        toolName: String,
        operations: [ToolOperation],
        scope: PermissionScope,
        lifetime: GrantLifetime,
        providerToolCallID: String? = nil
    ) {
        self.source = source
        self.toolName = toolName
        self.operations = operations
        self.scope = scope
        self.lifetime = lifetime
        self.providerToolCallID = providerToolCallID
    }
}

public enum PermissionScope: Sendable, Hashable, Codable {
    case directory(String)
    case exactPath(String)
}

public enum GrantLifetime: String, Sendable, Hashable, Codable {
    case once
    case turn
    case session
}

public struct PermissionRequest: Sendable, Hashable, Codable {
    public let toolCallID: String
    public let toolName: String
    public let operation: ToolOperation
    public let rawPath: String
    public let resolvedPath: String
    public let argumentSummary: String

    public init(
        toolCallID: String,
        toolName: String,
        operation: ToolOperation,
        rawPath: String,
        resolvedPath: String,
        argumentSummary: String
    ) {
        self.toolCallID = toolCallID
        self.toolName = toolName
        self.operation = operation
        self.rawPath = rawPath
        self.resolvedPath = resolvedPath
        self.argumentSummary = argumentSummary
    }
}

public enum ToolAuthorizationDecision: Sendable, Hashable {
    case allow(PermissionGrant)
    case deny(String)
    case requireApproval(PermissionRequest)
}

public struct ToolPolicy: Sendable, Hashable, Codable {
    public let workspaceRootPath: String
    public let sessionCurrentDirectoryPath: String
    public let grants: [PermissionGrant]

    public init(workspaceRootPath: String, sessionCurrentDirectoryPath: String, grants: [PermissionGrant] = []) {
        self.workspaceRootPath = workspaceRootPath
        self.sessionCurrentDirectoryPath = sessionCurrentDirectoryPath
        self.grants = grants
    }
}

public struct ResolvedWorkspacePath: Sendable, Hashable, Codable {
    public enum Location: String, Sendable, Hashable, Codable {
        case insideSessionCurrentDirectory
        case insideWorkspaceOutsideSessionCurrentDirectory
        case outsideWorkspace
        case unsafe
    }

    public let rawPath: String
    public let workspaceRelativePath: String?
    public let resolvedPath: String?
    public let location: Location

    public init(
        rawPath: String,
        workspaceRelativePath: String?,
        resolvedPath: String?,
        location: Location
    ) {
        self.rawPath = rawPath
        self.workspaceRelativePath = workspaceRelativePath
        self.resolvedPath = resolvedPath
        self.location = location
    }
}

public struct ToolExecutionRequest: Sendable, Hashable {
    public let id: UUID
    public let runID: UUID
    public let turnID: UUID
    public let providerToolCallID: String
    public let toolName: String
    public let argumentsJSON: String
    public let workspaceRoot: URL
    public let sessionCurrentDirectory: URL
    public let resolvedTarget: ResolvedWorkspacePath

    public init(
        id: UUID = UUID(),
        runID: UUID,
        turnID: UUID,
        providerToolCallID: String,
        toolName: String,
        argumentsJSON: String,
        workspaceRoot: URL,
        sessionCurrentDirectory: URL,
        resolvedTarget: ResolvedWorkspacePath
    ) {
        self.id = id
        self.runID = runID
        self.turnID = turnID
        self.providerToolCallID = providerToolCallID
        self.toolName = toolName
        self.argumentsJSON = argumentsJSON
        self.workspaceRoot = workspaceRoot
        self.sessionCurrentDirectory = sessionCurrentDirectory
        self.resolvedTarget = resolvedTarget
    }
}

public struct ToolExecutionResult: Sendable, Hashable, Codable {
    public let status: ToolResultStatus
    public let outputText: String
    public let metadata: [String: String]
    public let error: String?

    public init(
        status: ToolResultStatus,
        outputText: String,
        metadata: [String: String] = [:],
        error: String? = nil
    ) {
        self.status = status
        self.outputText = outputText
        self.metadata = metadata
        self.error = error
    }
}

public protocol ToolExecutor: Sendable {
    var definition: ToolDefinition { get }
    func execute(_ request: ToolExecutionRequest) async -> ToolExecutionResult
}
