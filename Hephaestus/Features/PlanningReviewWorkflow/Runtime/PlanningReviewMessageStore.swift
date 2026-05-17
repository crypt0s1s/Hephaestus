import Foundation

protocol PlanningReviewMessagePersisting {
    func persistMessages(
        _ messages: [WorkflowMessage],
        project: WorkflowProject,
        sessionID: String
    ) throws -> [String]
}

struct PlanningReviewMessageStore: PlanningReviewMessagePersisting {
    private let fileManager: FileManager
    private let encoder: JSONEncoder

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.encoder = encoder
    }

    func persistMessages(
        _ messages: [WorkflowMessage],
        project: WorkflowProject,
        sessionID: String
    ) throws -> [String] {
        guard !messages.isEmpty else { return [] }
        let projectURL = URL(fileURLWithPath: project.path, isDirectory: true)
        let directoryURL = projectURL.appendingPathComponent(
            Self.relativeDirectoryPath(sessionID: sessionID),
            isDirectory: true
        )
        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        return try messages.map { message in
            let relativePath = Self.relativeMessagePath(sessionID: sessionID, messageID: message.id)
            let messageURL = projectURL.appendingPathComponent(relativePath)
            try encoder.encode(message).write(to: messageURL, options: .atomic)
            return relativePath
        }
    }

    static func relativeDirectoryPath(sessionID: String) -> String {
        ".hephaestus/planning-review/\(sessionID)/messages"
    }

    static func relativeMessagePath(sessionID: String, messageID: WorkflowMessage.ID) -> String {
        "\(relativeDirectoryPath(sessionID: sessionID))/\(messageID).json"
    }
}
