import Foundation
import HephaestusKernel

public struct EditFileToolExecutor: ToolExecutor {
  public let definition = ToolDefinition(
    name: FileToolName.editFile,
    description:
      "Replace exact UTF-8 text in a file. The edit fails unless the expected occurrence count matches.",
    inputSchema: ToolInputSchema(
      jsonSchema: """
        {
          "type": "object",
          "properties": {
            "path": { "type": "string" },
            "oldText": { "type": "string" },
            "newText": { "type": "string" },
            "expectedOccurrences": { "type": "integer", "minimum": 1 }
          },
          "required": ["path", "oldText", "newText"]
        }
        """)
  )

  public init() {}

  public func execute(_ request: ToolExecutionRequest) async -> ToolExecutionResult {
    do {
      let arguments = try JSONDecoder().decode(
        EditFileArguments.self, from: Data(request.argumentsJSON.utf8))
      guard arguments.expectedOccurrences > 0 else {
        throw FileToolFailure.invalidExpectedOccurrences(arguments.expectedOccurrences)
      }
      let resolved = try FileToolPathResolver.resolve(
        rawPath: arguments.path,
        workspaceRoot: request.workspaceRoot,
        sessionCurrentDirectory: request.sessionCurrentDirectory
      )
      let target = try FileToolValidation.targetURL(from: resolved)
      try edit(arguments: arguments, target: target)

      let metadata = [
        "path": resolved.workspaceRelativePath ?? target.path,
        "replacements": String(arguments.expectedOccurrences),
        "byteDelta": String(
          Data(arguments.newText.utf8).count - Data(arguments.oldText.utf8).count),
        "location": resolved.location.rawValue,
      ]
      return ToolExecutionResult(
        status: .succeeded,
        outputText:
          "Edited \(metadata["path"] ?? target.path). Replaced \(arguments.expectedOccurrences) occurrence(s).",
        metadata: metadata
      )
    } catch {
      return ToolExecutionResult(status: .failed, outputText: "", error: String(describing: error))
    }
  }

  private func edit(arguments: EditFileArguments, target: URL) throws {
    guard FileManager.default.fileExists(atPath: target.path) else {
      throw FileToolFailure.fileNotFound(target.path)
    }
    var isDirectory: ObjCBool = false
    FileManager.default.fileExists(atPath: target.path, isDirectory: &isDirectory)
    guard !isDirectory.boolValue else {
      throw FileToolFailure.targetIsDirectory(target.path)
    }
    guard let text = try String(data: Data(contentsOf: target), encoding: .utf8) else {
      throw FileToolFailure.nonUTF8File(target.path)
    }

    let count = text.components(separatedBy: arguments.oldText).count - 1
    guard count == arguments.expectedOccurrences else {
      throw FileToolFailure.unexpectedOccurrenceCount(
        expected: arguments.expectedOccurrences, actual: count)
    }

    let updated = text.replacingOccurrences(of: arguments.oldText, with: arguments.newText)
    try FileToolValidation.validateText(updated)
    do {
      try updated.write(to: target, atomically: true, encoding: .utf8)
    } catch {
      throw FileToolFailure.writeFailed(String(describing: error))
    }
  }
}
