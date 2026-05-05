import Foundation
import HephaestusKernel

enum FileToolValidation {
    static func targetURL(from resolved: ResolvedWorkspacePath) throws -> URL {
        guard resolved.location != .unsafe, let path = resolved.resolvedPath else {
            throw FileToolFailure.invalidPath(resolved.rawPath)
        }
        return URL(fileURLWithPath: path)
    }

    static func validateText(_ text: String) throws {
        guard !text.unicodeScalars.contains(where: { $0.value == 0 }) else {
            throw FileToolFailure.unsafeContent
        }
    }
}
