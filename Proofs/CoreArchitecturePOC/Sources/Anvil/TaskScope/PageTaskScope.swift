import Foundation

@MainActor
public final class PageTaskScope {
    private var tasks: [UUID: Task<Void, Never>] = [:]

    public init() {}

    public func run(_ operation: @escaping @MainActor () async -> Void) {
        let id = UUID()
        tasks[id] = Task { [self] in
            await operation()
            removeTask(id)
        }
    }

    public func cancelAll() {
        for task in tasks.values {
            task.cancel()
        }
        tasks.removeAll()
    }

    private func removeTask(_ id: UUID) {
        tasks[id] = nil
    }
}
