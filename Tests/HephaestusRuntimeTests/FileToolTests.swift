import Foundation
import HephaestusKernel
import HephaestusTools
import Testing

@Suite
struct FileToolTests {
  @Test
  func writeFileCreatesFileInsideSessionCurrentDirectory() async throws {
    let workspace = try TemporaryWorkspace()
    let arguments = WriteFileArguments(path: "Sources/New.swift", content: "let value = 1\n")
    let request = try makeRequest(arguments, workspace: workspace, toolName: FileToolName.writeFile)

    let result = await WriteFileToolExecutor().execute(request)

    #expect(result.status == .succeeded)
    #expect(
      try String(
        contentsOf: workspace.root.appendingPathComponent("Sources/New.swift"), encoding: .utf8)
        == "let value = 1\n")
    #expect(result.metadata["path"] == "Sources/New.swift")
  }

  @Test
  func writeFileRequiresApprovalOutsideCurrentDirectoryInsideWorkspace() throws {
    let workspace = try TemporaryWorkspace(currentDirectoryRelativePath: "Sources")
    let policy = ToolPolicy(
      workspaceRootPath: workspace.root.path,
      sessionCurrentDirectoryPath: workspace.currentDirectory.path
    )

    let decision = FileToolPathResolver.authorizationDecision(
      toolCallID: "call-1",
      toolName: FileToolName.writeFile,
      operation: .write,
      rawPath: "Tests/New.swift",
      argumentSummary: "write Tests/New.swift",
      policy: policy
    )

    guard case .requireApproval(let request) = decision else {
      Issue.record("Expected elevated approval.")
      return
    }
    #expect(request.toolCallID == "call-1")
    #expect(request.resolvedPath.hasSuffix("/Tests/New.swift"))
  }

  @Test
  func writeFileRequiresApprovalForExplicitAbsoluteOutsideWorkspacePath() throws {
    let workspace = try TemporaryWorkspace()
    let outside = FileManager.default.temporaryDirectory
      .appendingPathComponent("hephaestus-outside-\(UUID().uuidString)")
      .appendingPathComponent("note.txt")
    let policy = ToolPolicy(
      workspaceRootPath: workspace.root.path,
      sessionCurrentDirectoryPath: workspace.currentDirectory.path
    )

    let decision = FileToolPathResolver.authorizationDecision(
      toolCallID: "call-absolute",
      toolName: FileToolName.writeFile,
      operation: .write,
      rawPath: outside.path,
      argumentSummary: "write outside workspace",
      policy: policy
    )

    guard case .requireApproval(let request) = decision else {
      Issue.record("Expected absolute outside-workspace path to require approval.")
      return
    }
    #expect(request.resolvedPath == outside.path)
  }

  @Test
  func workspaceRelativeParentTraversalIsDenied() throws {
    let workspace = try TemporaryWorkspace()
    let policy = ToolPolicy(
      workspaceRootPath: workspace.root.path,
      sessionCurrentDirectoryPath: workspace.currentDirectory.path
    )

    let decision = FileToolPathResolver.authorizationDecision(
      toolCallID: "call-traversal",
      toolName: FileToolName.writeFile,
      operation: .write,
      rawPath: "../outside.txt",
      argumentSummary: "traversal",
      policy: policy
    )

    guard case .deny(let reason) = decision else {
      Issue.record("Expected parent traversal to be denied.")
      return
    }
    #expect(reason.contains("unsafe") || reason.contains("Invalid"))
  }

  @Test
  func symlinkEscapeFromWorkspaceRelativePathIsDenied() throws {
    let workspace = try TemporaryWorkspace()
    let outsideDirectory = try makeTemporaryDirectory(name: "hephaestus-target")
    let link = workspace.root.appendingPathComponent("Sources/link-out")
    try FileManager.default.createSymbolicLink(
      at: link,
      withDestinationURL: outsideDirectory
    )
    let resolved = try FileToolPathResolver.resolve(
      rawPath: "Sources/link-out/file.txt",
      workspaceRoot: workspace.root,
      sessionCurrentDirectory: workspace.currentDirectory
    )

    #expect(resolved.location == .unsafe)
  }

  @Test
  func editFileReplacesExpectedOccurrence() async throws {
    let workspace = try TemporaryWorkspace()
    let file = workspace.root.appendingPathComponent("Sources/App.swift")
    try "let title = \"Old\"\n".write(to: file, atomically: true, encoding: .utf8)
    let arguments = EditFileArguments(
      path: "Sources/App.swift",
      oldText: "Old",
      newText: "New",
      expectedOccurrences: 1
    )
    let request = try makeRequest(arguments, workspace: workspace, toolName: FileToolName.editFile)

    let result = await EditFileToolExecutor().execute(request)

    #expect(result.status == .succeeded)
    #expect(try String(contentsOf: file, encoding: .utf8) == "let title = \"New\"\n")
  }

  @Test
  func editFileFailsOnUnexpectedOccurrenceCountWithoutChangingFile() async throws {
    let workspace = try TemporaryWorkspace()
    let file = workspace.root.appendingPathComponent("Sources/App.swift")
    try "Old Old\n".write(to: file, atomically: true, encoding: .utf8)
    let arguments = EditFileArguments(
      path: "Sources/App.swift",
      oldText: "Old",
      newText: "New",
      expectedOccurrences: 1
    )
    let request = try makeRequest(arguments, workspace: workspace, toolName: FileToolName.editFile)

    let result = await EditFileToolExecutor().execute(request)

    #expect(result.status == .failed)
    #expect(result.error?.contains("Expected 1 occurrences, found 2") == true)
    #expect(try String(contentsOf: file, encoding: .utf8) == "Old Old\n")
  }

  private func makeRequest<T: Encodable>(
    _ arguments: T,
    workspace: TemporaryWorkspace,
    toolName: String
  ) throws -> ToolExecutionRequest {
    let data = try JSONEncoder().encode(arguments)
    let argumentsJSON = String(data: data, encoding: .utf8) ?? "{}"
    let path: String
    if let writeArguments = arguments as? WriteFileArguments {
      path = writeArguments.path
    } else if let editArguments = arguments as? EditFileArguments {
      path = editArguments.path
    } else {
      path = ""
    }
    let resolved = try FileToolPathResolver.resolve(
      rawPath: path,
      workspaceRoot: workspace.root,
      sessionCurrentDirectory: workspace.currentDirectory
    )
    return ToolExecutionRequest(
      runID: UUID(),
      turnID: UUID(),
      providerToolCallID: "call-\(UUID().uuidString)",
      toolName: toolName,
      argumentsJSON: argumentsJSON,
      workspaceRoot: workspace.root,
      sessionCurrentDirectory: workspace.currentDirectory,
      resolvedTarget: resolved
    )
  }
}

private struct TemporaryWorkspace {
  let root: URL
  let currentDirectory: URL

  init(currentDirectoryRelativePath: String = "Sources") throws {
    root = try makeTemporaryDirectory(name: "hephaestus-workspace")
    currentDirectory = root.appendingPathComponent(currentDirectoryRelativePath, isDirectory: true)
    try FileManager.default.createDirectory(at: currentDirectory, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(
      at: root.appendingPathComponent("Tests", isDirectory: true), withIntermediateDirectories: true
    )
  }
}

private func makeTemporaryDirectory(name: String) throws -> URL {
  let url = FileManager.default.temporaryDirectory
    .appendingPathComponent("\(name)-\(UUID().uuidString)", isDirectory: true)
  try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
  return url
}
