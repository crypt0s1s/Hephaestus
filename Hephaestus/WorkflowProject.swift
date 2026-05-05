import Foundation

struct WorkflowProject: Codable, Identifiable, Equatable {
    var id: String { path }
    let name: String
    let path: String
    let bookmarkData: Data?

    init(url: URL, bookmarkData: Data?) {
        self.name = url.lastPathComponent.isEmpty ? url.path : url.lastPathComponent
        self.path = url.path
        self.bookmarkData = bookmarkData
    }
}
