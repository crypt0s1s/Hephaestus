import Foundation

enum SwiftPackageScratchPath {
    static func url(for packageURL: URL) -> URL {
        let sanitizedPath = packageURL.path
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: ":", with: "_")
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("HephaestusExternalSwiftPackages", isDirectory: true)
            .appendingPathComponent(sanitizedPath, isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
