import Foundation
import HephaestusKernel

public struct WriteFileToolExecutor: ToolExecutor {
  public let definition = ToolDefinition(
    name: FileToolName.writeFile,
    description:
      """
      Write a complete UTF-8 text file. Workspace-relative paths inside the session directory \
      are allowed by default; other explicit targets require elevated approval.
      """,
    inputSchema: ToolInputSchema(
      jsonSchema: """
        {
          "type": "object",
          "properties": {
            "path": { "type": "string" },
            "content": { "type": "string" },
            "createIntermediateDirectories": { "type": "boolean" },
            "overwrite": { "type": "boolean" }
          },
          "required": ["path", "content"]
        }
        """)
  )

  public init() {}

  public func execute(_ request: ToolExecutionRequest) async -> ToolExecutionResult {
    do {
      let arguments = try JSONDecoder().decode(
        WriteFileArguments.self, from: Data(request.argumentsJSON.utf8))
      let resolved = try FileToolPathResolver.resolve(
        rawPath: arguments.path,
        workspaceRoot: request.workspaceRoot,
        sessionCurrentDirectory: request.sessionCurrentDirectory
      )
      let target = try FileToolValidation.targetURL(from: resolved)
      try FileToolValidation.validateText(arguments.content)
      try write(arguments: arguments, target: target)

      let metadata = [
        "path": resolved.workspaceRelativePath ?? target.path,
        "bytesWritten": String(Data(arguments.content.utf8).count),
        "location": resolved.location.rawValue,
      ]
      return ToolExecutionResult(
        status: .succeeded,
        outputText: "Wrote \(metadata["path"] ?? target.path).",
        metadata: metadata
      )
    } catch {
      return ToolExecutionResult(status: .failed, outputText: "", error: String(describing: error))
    }
  }

  private func write(arguments: WriteFileArguments, target: URL) throws {
    var isDirectory: ObjCBool = false
    if FileManager.default.fileExists(atPath: target.path, isDirectory: &isDirectory) {
      guard !isDirectory.boolValue else { throw FileToolFailure.targetIsDirectory(target.path) }
      guard arguments.overwrite else { throw FileToolFailure.fileAlreadyExists(target.path) }
    }

    let parent = target.deletingLastPathComponent()
    if !FileManager.default.fileExists(atPath: parent.path) {
      guard arguments.createIntermediateDirectories else {
        throw FileToolFailure.parentDirectoryMissing(parent.path)
      }
      try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
    }

    do {
      try arguments.content.write(to: target, atomically: true, encoding: .utf8)
    } catch {
      throw FileToolFailure.writeFailed(String(describing: error))
    }
  }
}
