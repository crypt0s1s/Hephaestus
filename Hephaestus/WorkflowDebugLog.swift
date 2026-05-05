import Foundation

actor WorkflowDebugLog {
    let fileURL: URL
    private let fileManager: FileManager

    init(projectName: String, fileManager: FileManager = .default) {
        self.fileManager = fileManager
        let baseURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        let directoryURL = baseURL
            .appendingPathComponent("Hephaestus", isDirectory: true)
            .appendingPathComponent("WorkflowLogs", isDirectory: true)
        try? fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        let safeProjectName = projectName
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
        let fileName = "\(Self.timestamp())-\(safeProjectName)-implementation-review.log"
        fileURL = directoryURL.appendingPathComponent(fileName)
        fileManager.createFile(atPath: fileURL.path, contents: nil)
    }

    func append(_ text: String) {
        guard let data = text.data(using: .utf8),
              let handle = try? FileHandle(forWritingTo: fileURL) else {
            return
        }
        defer { try? handle.close() }
        try? handle.seekToEnd()
        try? handle.write(contentsOf: data)
    }

    private static func timestamp() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: Date())
    }
}
