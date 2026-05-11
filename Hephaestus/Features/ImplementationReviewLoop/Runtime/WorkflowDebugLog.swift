import Foundation

actor WorkflowDebugLog {
    let directoryURL: URL
    let fileURL: URL
    private let fileManager: FileManager

    init(projectName: String, fileManager: FileManager = .default) {
        self.fileManager = fileManager
        let baseURL =
            fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        let directoryURL =
            baseURL
            .appendingPathComponent("Hephaestus", isDirectory: true)
            .appendingPathComponent("WorkflowLogs", isDirectory: true)
        try? fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        let safeProjectName =
            projectName
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
        let runDirectoryName = "\(Self.timestamp())-\(safeProjectName)"
        self.directoryURL = directoryURL.appendingPathComponent(runDirectoryName, isDirectory: true)
        try? fileManager.createDirectory(at: self.directoryURL, withIntermediateDirectories: true)
        fileURL = self.directoryURL.appendingPathComponent("run.log")
        fileManager.createFile(atPath: fileURL.path, contents: nil)
    }

    func append(_ text: String) {
        append(text, to: fileURL)
    }

    func append(_ text: String, to fileName: String) {
        append(text, to: fileURL(for: fileName))
    }

    private func append(_ text: String, to url: URL) {
        guard let data = text.data(using: .utf8) else {
            return
        }
        if !fileManager.fileExists(atPath: url.path) {
            fileManager.createFile(atPath: url.path, contents: nil)
        }
        guard let handle = try? FileHandle(forWritingTo: url) else { return }
        defer { try? handle.close() }
        do {
            _ = try handle.seekToEnd()
            try handle.write(contentsOf: data)
        } catch {
            return
        }
    }

    private func fileURL(for fileName: String) -> URL {
        let safeFileName =
            fileName
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
        return directoryURL.appendingPathComponent(safeFileName)
    }

    private static func timestamp() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss-SSS"
        return formatter.string(from: Date())
    }
}
