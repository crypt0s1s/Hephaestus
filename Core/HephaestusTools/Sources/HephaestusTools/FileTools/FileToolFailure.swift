public enum FileToolFailure: Error, Sendable, Equatable, CustomStringConvertible {
    case invalidPath(String)
    case workspaceRootUnavailable(String)
    case sessionCurrentDirectoryUnavailable(String)
    case targetIsDirectory(String)
    case parentDirectoryMissing(String)
    case fileAlreadyExists(String)
    case fileNotFound(String)
    case nonUTF8File(String)
    case invalidExpectedOccurrences(Int)
    case unexpectedOccurrenceCount(expected: Int, actual: Int)
    case unsafeContent
    case writeFailed(String)

    public var description: String {
        switch self {
        case .invalidPath(let path):
            return "Invalid file tool path: \(path)"
        case .workspaceRootUnavailable(let path):
            return "Workspace root is unavailable: \(path)"
        case .sessionCurrentDirectoryUnavailable(let path):
            return "Session current directory is unavailable: \(path)"
        case .targetIsDirectory(let path):
            return "Target is a directory: \(path)"
        case .parentDirectoryMissing(let path):
            return "Parent directory does not exist: \(path)"
        case .fileAlreadyExists(let path):
            return "File already exists: \(path)"
        case .fileNotFound(let path):
            return "File was not found: \(path)"
        case .nonUTF8File(let path):
            return "File is not valid UTF-8 text: \(path)"
        case .invalidExpectedOccurrences(let count):
            return "Expected occurrences must be greater than zero: \(count)"
        case .unexpectedOccurrenceCount(let expected, let actual):
            return "Expected \(expected) occurrences, found \(actual)."
        case .unsafeContent:
            return "Content appears to be binary."
        case .writeFailed(let reason):
            return "Write failed: \(reason)"
        }
    }
}
