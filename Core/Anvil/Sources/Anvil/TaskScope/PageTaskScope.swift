import Foundation

@MainActor
public final class PageTaskScope {
    private var tasks: [UUID: Task<Void, Never>] = [:]

    public init() {}

    @discardableResult
    public func run(_ operation: @escaping @MainActor () async -> Void) -> UUID {
        let id = UUID()
        tasks[id] = Task { [self] in
            await operation()
            removeTask(id)
        }
        return id
    }

    public func cancel(_ id: UUID) {
        tasks[id]?.cancel()
        tasks[id] = nil
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
