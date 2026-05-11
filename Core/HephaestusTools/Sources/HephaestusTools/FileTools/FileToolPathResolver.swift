import Foundation
import HephaestusKernel

public enum FileToolPathResolver {
    public static func resolve(
        rawPath: String,
        workspaceRoot: URL,
        sessionCurrentDirectory: URL
    ) throws -> ResolvedWorkspacePath {
        try FileToolPathResolutionContext(
            rawPath: rawPath,
            workspaceRoot: workspaceRoot,
            sessionCurrentDirectory: sessionCurrentDirectory
        ).resolve()
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
            let resolved = try resolve(
                rawPath: rawPath, workspaceRoot: workspace, sessionCurrentDirectory: session)
            switch resolved.location {
            case .insideSessionCurrentDirectory:
                return .allow(
                    PermissionGrant(
                        source: .defaultCurrentDirectory,
                        toolName: toolName,
                        operations: [operation],
                        scope: .directory(session.resolvingSymlinksInPath().standardizedFileURL.path),
                        lifetime: .session
                    ))
            case .insideWorkspaceOutsideSessionCurrentDirectory, .outsideWorkspace:
                return .requireApproval(
                    PermissionRequest(
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
}

private struct FileToolPathResolutionContext {
    let rawPath: String
    let workspaceRoot: URL
    let sessionCurrentDirectory: URL

    func resolve() throws -> ResolvedWorkspacePath {
        let trimmed = rawPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return Self.unsafePath(rawPath: rawPath)
        }
        guard !Self.containsParentTraversal(trimmed) else {
            return Self.unsafePath(rawPath: rawPath)
        }

        let context = try canonicalContext()
        return resolve(trimmed: trimmed, context: context)
    }

    private func resolve(
        trimmed: String,
        context: CanonicalFileToolPathContext
    ) -> ResolvedWorkspacePath {
        let canonicalWorkspace = context.workspace
        let canonicalSession = context.session
        guard FileToolPathResolver.contains(canonicalSession, in: canonicalWorkspace) else {
            return Self.unsafePath(rawPath: rawPath, resolvedPath: canonicalSession.path)
        }

        let isAbsolute = trimmed.hasPrefix("/")
        let target =
            isAbsolute
            ? URL(fileURLWithPath: trimmed)
            : canonicalWorkspace.appendingPathComponent(trimmed)
        let resolved = Self.resolvePossiblyNewTarget(target)
        let workspaceRelative = Self.workspaceRelativePath(
            for: resolved,
            canonicalWorkspace: canonicalWorkspace
        )

        if isAbsolute {
            return absolutePathResult(
                resolved: resolved,
                workspaceRelative: workspaceRelative,
                canonicalSession: canonicalSession,
                canonicalWorkspace: canonicalWorkspace
            )
        }

        return relativePathResult(
            resolved: resolved,
            workspaceRelative: workspaceRelative,
            canonicalSession: canonicalSession,
            canonicalWorkspace: canonicalWorkspace
        )
    }

    private func canonicalContext() throws -> CanonicalFileToolPathContext {
        let canonicalWorkspace = try Self.canonicalExistingDirectory(
            workspaceRoot, failure: .workspaceRootUnavailable(workspaceRoot.path))
        let canonicalSession = try Self.canonicalExistingDirectory(
            sessionCurrentDirectory,
            failure: .sessionCurrentDirectoryUnavailable(sessionCurrentDirectory.path)
        )
        return CanonicalFileToolPathContext(workspace: canonicalWorkspace, session: canonicalSession)
    }

    private func relativePathResult(
        resolved: URL,
        workspaceRelative: String?,
        canonicalSession: URL,
        canonicalWorkspace: URL
    ) -> ResolvedWorkspacePath {
        guard FileToolPathResolver.contains(resolved, in: canonicalWorkspace) else {
            return Self.unsafePath(
                rawPath: rawPath,
                workspaceRelativePath: workspaceRelative,
                resolvedPath: resolved.path
            )
        }
        return ResolvedWorkspacePath(
            rawPath: rawPath,
            workspaceRelativePath: workspaceRelative,
            resolvedPath: resolved.path,
            location: FileToolPathResolver.contains(resolved, in: canonicalSession)
                ? .insideSessionCurrentDirectory
                : .insideWorkspaceOutsideSessionCurrentDirectory
        )
    }

    private func absolutePathResult(
        resolved: URL,
        workspaceRelative: String?,
        canonicalSession: URL,
        canonicalWorkspace: URL
    ) -> ResolvedWorkspacePath {
        ResolvedWorkspacePath(
            rawPath: rawPath,
            workspaceRelativePath: workspaceRelative,
            resolvedPath: resolved.path,
            location: Self.absoluteLocation(
                for: resolved,
                canonicalSession: canonicalSession,
                canonicalWorkspace: canonicalWorkspace
            )
        )
    }

    private static func workspaceRelativePath(for resolved: URL, canonicalWorkspace: URL) -> String? {
        FileToolPathResolver.contains(resolved, in: canonicalWorkspace)
            ? relativePath(from: canonicalWorkspace, to: resolved)
            : nil
    }

    private static func containsParentTraversal(_ path: String) -> Bool {
        path.split(separator: "/", omittingEmptySubsequences: false).contains("..")
    }

    private static func unsafePath(
        rawPath: String,
        workspaceRelativePath: String? = nil,
        resolvedPath: String? = nil
    ) -> ResolvedWorkspacePath {
        ResolvedWorkspacePath(
            rawPath: rawPath,
            workspaceRelativePath: workspaceRelativePath,
            resolvedPath: resolvedPath,
            location: .unsafe
        )
    }

    private static func absoluteLocation(
        for resolved: URL,
        canonicalSession: URL,
        canonicalWorkspace: URL
    ) -> ResolvedWorkspacePath.Location {
        if FileToolPathResolver.contains(resolved, in: canonicalSession) {
            return .insideSessionCurrentDirectory
        }
        if FileToolPathResolver.contains(resolved, in: canonicalWorkspace) {
            return .insideWorkspaceOutsideSessionCurrentDirectory
        }
        return .outsideWorkspace
    }

    private static func canonicalExistingDirectory(_ url: URL, failure: FileToolFailure) throws -> URL {
        var isDirectory: ObjCBool = false
        let path = url.path
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory),
            isDirectory.boolValue
        else {
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

private struct CanonicalFileToolPathContext {
    let workspace: URL
    let session: URL
}
