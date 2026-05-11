import Foundation

struct ImplementationReviewWorkflowRequest: Equatable {
    var planRelativePath: String
    var buildCommand: String
    var maxReviewCycles = 3

    var normalizedBuildCommand: String {
        let trimmed = buildCommand.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "swift build" : trimmed
    }
}

struct ReviewFinding: Equatable {
    let reviewerName: String
    let transcript: String

    var hasBlockingIssue: Bool {
        let normalized = transcript.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if normalized == "pass" {
            return false
        }
        return normalized.split(separator: "\n").contains { line in
            ReviewFindingSummary.isBlockingSeverityFindingLine(String(line))
        }
    }

    var displaySummary: String {
        ReviewFindingSummary.extract(from: transcript)
            ?? """
            Reviewer output did not include a concise finding summary. \
            Open latest output or full logs for the raw transcript.
            """
    }
}

struct ReviewFindingSummary {
    static func extract(from transcript: String) -> String? {
        let trimmed = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let normalized = trimmed.lowercased()
        if normalized == "pass" {
            return "pass"
        }

        let findingLines =
            trimmed
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { isSeverityFindingLine($0) }
            .stableUnique()

        guard !findingLines.isEmpty else { return nil }
        return findingLines.prefix(8).joined(separator: "\n")
    }

    static func isBlockingSeverityFindingLine(_ line: String) -> Bool {
        severityLevel(in: line).map { $0 == "p1" || $0 == "p2" } ?? false
    }

    private static func isSeverityFindingLine(_ line: String) -> Bool {
        severityLevel(in: line) != nil
    }

    private static func severityLevel(in line: String) -> String? {
        var normalized = line.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        for prefix in ["-", "*"] where normalized.hasPrefix(prefix) {
            normalized.removeFirst(prefix.count)
            normalized = normalized.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        if normalized.hasPrefix("[p1]") { return "p1" }
        if normalized.hasPrefix("[p2]") { return "p2" }
        if normalized.hasPrefix("[p3]") { return "p3" }

        for severity in ["p1", "p2", "p3"] where normalized.hasPrefix(severity) {
            var delimiterIndex = normalized.index(normalized.startIndex, offsetBy: severity.count)
            while delimiterIndex < normalized.endIndex,
                normalized[delimiterIndex].isWhitespace {
                delimiterIndex = normalized.index(after: delimiterIndex)
            }
            guard delimiterIndex < normalized.endIndex else { return nil }
            let delimiter = normalized[delimiterIndex]
            if delimiter == ":" || delimiter == "-" || delimiter == "[" || delimiter == "]"
                || delimiter == "." {
                return severity
            }
        }
        return nil
    }
}

extension Array where Element == String {
    fileprivate func stableUnique() -> [String] {
        var seen = Set<String>()
        return filter { line in
            seen.insert(line).inserted
        }
    }
}

struct PlanDocument: Equatable {
    let relativePath: String
    let absoluteURL: URL
    let contents: String
}

enum PlanFileValidationError: Error, LocalizedError, Equatable {
    case emptyPath
    case absolutePathNotAllowed
    case nonMarkdownPath(String)
    case escapesProject(String)
    case fileMissing(String)
    case unreadable(String)

    var errorDescription: String? {
        switch self {
        case .emptyPath:
            return "Enter a project-relative markdown plan path."
        case .absolutePathNotAllowed:
            return "Plan path must be relative to the selected project."
        case .nonMarkdownPath(let path):
            return "Plan path must point to a .md file: \(path)"
        case .escapesProject(let path):
            return "Plan path must stay inside the selected project: \(path)"
        case .fileMissing(let path):
            return "Plan file does not exist: \(path)"
        case .unreadable(let path):
            return "Plan file could not be read: \(path)"
        }
    }
}

struct PlanFileValidator {
    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func loadPlan(project: WorkflowProject, relativePath: String) throws -> PlanDocument {
        let trimmedPath = relativePath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPath.isEmpty else {
            throw PlanFileValidationError.emptyPath
        }
        guard !trimmedPath.hasPrefix("/") else {
            throw PlanFileValidationError.absolutePathNotAllowed
        }
        guard URL(fileURLWithPath: trimmedPath).pathExtension.lowercased() == "md" else {
            throw PlanFileValidationError.nonMarkdownPath(trimmedPath)
        }

        let projectURL = URL(fileURLWithPath: project.path, isDirectory: true).standardizedFileURL
        let planURL = projectURL.appendingPathComponent(trimmedPath).standardizedFileURL
        guard planURL.path == projectURL.path || planURL.path.hasPrefix(projectURL.path + "/") else {
            throw PlanFileValidationError.escapesProject(trimmedPath)
        }

        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: planURL.path, isDirectory: &isDirectory),
            !isDirectory.boolValue
        else {
            throw PlanFileValidationError.fileMissing(trimmedPath)
        }
        guard let contents = try? String(contentsOf: planURL, encoding: .utf8) else {
            throw PlanFileValidationError.unreadable(trimmedPath)
        }
        return PlanDocument(relativePath: trimmedPath, absoluteURL: planURL, contents: contents)
    }
}
