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
        if normalized == "pass" || normalized.hasPrefix("pass\n") || normalized.hasPrefix("pass ") {
            return false
        }
        return normalized.split(separator: "\n").contains { line in
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.hasPrefix("p1")
                || trimmed.hasPrefix("p2")
                || trimmed.hasPrefix("- p1")
                || trimmed.hasPrefix("- p2")
                || trimmed.hasPrefix("* p1")
                || trimmed.hasPrefix("* p2")
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
        guard fileManager.fileExists(atPath: planURL.path, isDirectory: &isDirectory), !isDirectory.boolValue else {
            throw PlanFileValidationError.fileMissing(trimmedPath)
        }
        guard let contents = try? String(contentsOf: planURL, encoding: .utf8) else {
            throw PlanFileValidationError.unreadable(trimmedPath)
        }
        return PlanDocument(relativePath: trimmedPath, absoluteURL: planURL, contents: contents)
    }
}
