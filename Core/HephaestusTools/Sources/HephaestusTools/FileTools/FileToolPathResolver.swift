import Foundation
import HephaestusKernel

public enum FileToolPathResolver {
    public static func resolve(
        rawPath: String,
        workspaceRoot: URL,
        sessionCurrentDirectory: URL
    ) throws -> ResolvedWorkspacePath {
        let trimmed = rawPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return ResolvedWorkspacePath(
                rawPath: rawPath,
                workspaceRelativePath: nil,
                resolvedPath: nil,
                location: .unsafe
            )
        }
        guard !containsParentTraversal(trimmed) else {
            return ResolvedWorkspacePath(
                rawPath: rawPath,
                workspaceRelativePath: nil,
                resolvedPath: nil,
                location: .unsafe
            )
        }

        let canonicalWorkspace = try canonicalExistingDirectory(workspaceRoot, failure: .workspaceRootUnavailable(workspaceRoot.path))
        let canonicalSession = try canonicalExistingDirectory(
            sessionCurrentDirectory,
            failure: .sessionCurrentDirectoryUnavailable(sessionCurrentDirectory.path)
        )
        guard contains(canonicalSession, in: canonicalWorkspace) else {
            return ResolvedWorkspacePath(
                rawPath: rawPath,
                workspaceRelativePath: nil,
                resolvedPath: canonicalSession.path,
                location: .unsafe
            )
        }

        let isAbsolute = trimmed.hasPrefix("/")
        let target = isAbsolute
            ? URL(fileURLWithPath: trimmed)
            : canonicalWorkspace.appendingPathComponent(trimmed)
        let resolved = resolvePossiblyNewTarget(target)
        let workspaceRelative = contains(resolved, in: canonicalWorkspace)
            ? relativePath(from: canonicalWorkspace, to: resolved)
            : nil

        if isAbsolute {
            return ResolvedWorkspacePath(
                rawPath: rawPath,
                workspaceRelativePath: workspaceRelative,
                resolvedPath: resolved.path,
                location: contains(resolved, in: canonicalSession)
                    ? .insideSessionCurrentDirectory
                    : (contains(resolved, in: canonicalWorkspace) ? .insideWorkspaceOutsideSessionCurrentDirectory : .outsideWorkspace)
            )
        }

        guard contains(resolved, in: canonicalWorkspace) else {
            return ResolvedWorkspacePath(
                rawPath: rawPath,
                workspaceRelativePath: workspaceRelative,
                resolvedPath: resolved.path,
                location: .unsafe
            )
        }
        return ResolvedWorkspacePath(
            rawPath: rawPath,
            workspaceRelativePath: workspaceRelative,
            resolvedPath: resolved.path,
            location: contains(resolved, in: canonicalSession)
                ? .insideSessionCurrentDirectory
                : .insideWorkspaceOutsideSessionCurrentDirectory
        )
    }

    public static func authorizationDecision(
        toolCallID: String,
        toolName: String,
        operation: ToolOperation,
        rawPath: String,
        argumentSummary: String,
        policy: ToolPolicy
    ) -> ToolAuthorizationDecision {
        let workspace = URL(fileURLWithPath: policy.workspaceRootPath, isDirectory: true)
        let session = URL(fileURLWithPath: policy.sessionCurrentDirectoryPath, isDirectory: true)

        do {
            let resolved = try resolve(rawPath: rawPath, workspaceRoot: workspace, sessionCurrentDirectory: session)
            switch resolved.location {
            case .insideSessionCurrentDirectory:
                return .allow(PermissionGrant(
                    source: .defaultCurrentDirectory,
                    toolName: toolName,
                    operations: [operation],
                    scope: .directory(session.resolvingSymlinksInPath().standardizedFileURL.path),
                    lifetime: .session
                ))
            case .insideWorkspaceOutsideSessionCurrentDirectory, .outsideWorkspace:
                return .requireApproval(PermissionRequest(
                    toolCallID: toolCallID,
                    toolName: toolName,
                    operation: operation,
                    rawPath: rawPath,
                    resolvedPath: resolved.resolvedPath ?? rawPath,
                    argumentSummary: argumentSummary
                ))
            case .unsafe:
                return .deny("Path is unsafe or escapes the approved scope.")
            }
        } catch {
            return .deny(String(describing: error))
        }
    }

    public static func contains(_ child: URL, in parent: URL) -> Bool {
        let childComponents = child.standardizedFileURL.pathComponents
        let parentComponents = parent.standardizedFileURL.pathComponents
        guard childComponents.count >= parentComponents.count else { return false }
        return Array(childComponents.prefix(parentComponents.count)) == parentComponents
    }

    private static func containsParentTraversal(_ path: String) -> Bool {
        path.split(separator: "/", omittingEmptySubsequences: false).contains("..")
    }

    private static func canonicalExistingDirectory(_ url: URL, failure: FileToolFailure) throws -> URL {
        var isDirectory: ObjCBool = false
        let path = url.path
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw failure
        }
        return url.resolvingSymlinksInPath().standardizedFileURL
    }

    private static func resolvePossiblyNewTarget(_ target: URL) -> URL {
        if FileManager.default.fileExists(atPath: target.path) {
            return target.resolvingSymlinksInPath().standardizedFileURL
        }

        var missingComponents: [String] = [target.lastPathComponent]
        var parent = target.deletingLastPathComponent()
        while !FileManager.default.fileExists(atPath: parent.path), parent.path != "/" {
            missingComponents.insert(parent.lastPathComponent, at: 0)
            parent.deleteLastPathComponent()
        }

        var resolved = parent.resolvingSymlinksInPath().standardizedFileURL
        for component in missingComponents {
            resolved.appendPathComponent(component)
        }
        return resolved.standardizedFileURL
    }

    private static func relativePath(from parent: URL, to child: URL) -> String {
        let parentComponents = parent.standardizedFileURL.pathComponents
        let childComponents = child.standardizedFileURL.pathComponents
        let suffix = childComponents.dropFirst(parentComponents.count)
        return suffix.joined(separator: "/")
    }
}
