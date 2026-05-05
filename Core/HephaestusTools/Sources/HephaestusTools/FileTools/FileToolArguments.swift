public enum FileToolName {
    public static let writeFile = "write_file"
    public static let editFile = "edit_file"
}

public struct WriteFileArguments: Sendable, Hashable, Codable {
    public let path: String
    public let content: String
    public let createIntermediateDirectories: Bool
    public let overwrite: Bool

    public init(
        path: String,
        content: String,
        createIntermediateDirectories: Bool = false,
        overwrite: Bool = false
    ) {
        self.path = path
        self.content = content
        self.createIntermediateDirectories = createIntermediateDirectories
        self.overwrite = overwrite
    }
}

public struct EditFileArguments: Sendable, Hashable, Codable {
    public let path: String
    public let oldText: String
    public let newText: String
    public let expectedOccurrences: Int

    public init(path: String, oldText: String, newText: String, expectedOccurrences: Int = 1) {
        self.path = path
        self.oldText = oldText
        self.newText = newText
        self.expectedOccurrences = expectedOccurrences
    }
}
