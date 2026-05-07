import Anvil
import Foundation
import HephaestusRuntime
import TaskWorkspaceContracts

@MainActor
public final class TaskWorkspaceService {
    public private(set) var snapshot: TaskWorkspaceSnapshot

    private let registry: TaskSessionServiceRegistry
    private let listSessions: ListSessionsUseCase?
    private let router: Router<AnyRouteInput, AnyModalInput>?
    private var selectedService: TaskSessionService?
    private var selectedSnapshotTask: Task<Void, Never>?
    private var snapshotContinuations: [UUID: AsyncStream<TaskWorkspaceSnapshot>.Continuation] = [:]

    public init(
        registry: TaskSessionServiceRegistry,
        listSessions: ListSessionsUseCase? = nil,
        router: Router<AnyRouteInput, AnyModalInput>? = nil,
        snapshot: TaskWorkspaceSnapshot = TaskWorkspaceSnapshot()
    ) {
        self.registry = registry
        self.listSessions = listSessions
        self.router = router
        self.snapshot = snapshot
        registry.setOnServiceSummaryChanged { [weak self] in
            Task { @MainActor in
                await self?.refreshSummaries()
            }
        }
    }

    deinit {
        selectedSnapshotTask?.cancel()
    }

    public func subscribeSnapshots() -> AsyncStream<TaskWorkspaceSnapshot> {
        AsyncStream { continuation in
            let subscriptionID = UUID()
            snapshotContinuations[subscriptionID] = continuation
            continuation.yield(snapshot)
            continuation.onTermination = { @Sendable _ in
                Task { @MainActor in
                    self.snapshotContinuations[subscriptionID] = nil
                }
            }
        }
    }

    @discardableResult
    public func selectTask(_ id: UUID, force: Bool = false) async -> Bool {
        guard force || snapshot.selectedTaskID != id else { return false }
        do {
            let service = try await registry.service(for: id)
            attach(to: service)
            return true
        } catch {
            detachSelection(error: TaskWorkspaceServiceError(error))
            return false
        }
    }

    @discardableResult
    public func createNewTask(title: String? = nil) async -> Bool {
        do {
            let service = try await registry.createService(title: title)
            attach(to: service)
            await refreshSummaries()
            return true
        } catch {
            setSessions(.error(TaskWorkspaceServiceError(error)))
            return false
        }
    }

    public func sendMessage(_ text: String) async -> Bool {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else { return false }

        let service: TaskSessionService
        if let selectedService {
            service = selectedService
        } else {
            do {
                service = try await registry.createService(title: nil)
                attach(to: service)
                await refreshSummaries()
            } catch {
                setSessions(.error(TaskWorkspaceServiceError(error)))
                return false
            }
        }

        service.send(trimmedText)
        applySelectedServiceSnapshot(service.snapshot)
        return true
    }

    public func cancelSelectedTurn() {
        selectedService?.cancelActiveTurn()
        if let selectedService {
            applySelectedServiceSnapshot(selectedService.snapshot)
        }
    }

    public func refreshSummaries() async {
        guard let listSessions else { return }
        setSessions(.loading(placeholder: snapshot.sessions.data))
        do {
            let summaries = try await listSessions.listSessions()
            setSessions(.loaded(summaries.map(TaskSummaryState.init(summary:))))
        } catch {
            setSessions(.error(TaskWorkspaceServiceError(error)))
        }
    }

    private func attach(to service: TaskSessionService) {
        selectedSnapshotTask?.cancel()
        selectedService = service
        updateSnapshot { snapshot in
            snapshot.selectedTaskID = service.id
            snapshot.selectedTask = service.snapshot
            snapshot.selectionError = nil
        }
        syncSelectedRoute(service.id)
        selectedSnapshotTask = Task { [weak self, service] in
            for await snapshot in service.subscribeSnapshots(includeCurrent: false) {
                await MainActor.run {
                    self?.applySelectedServiceSnapshot(snapshot)
                }
            }
        }
    }

    private func detachSelection(error: TaskWorkspaceServiceError) {
        selectedSnapshotTask?.cancel()
        selectedSnapshotTask = nil
        selectedService = nil
        updateSnapshot { snapshot in
            snapshot.selectedTaskID = nil
            snapshot.selectedTask = nil
            snapshot.selectionError = error
        }
    }

    private func syncSelectedRoute(_ id: UUID) {
        guard let router,
              let route = try? AnyRouteInput(TaskWorkspaceRouteInput(taskID: id))
        else { return }
        if let current = router.path.last,
           (try? current.decode(TaskWorkspaceRouteInput.self).taskID) == id {
            return
        }
        router.replaceStack([route])
    }

    private func applySelectedServiceSnapshot(_ serviceSnapshot: TaskSessionSnapshot) {
        guard snapshot.selectedTaskID == serviceSnapshot.id else { return }
        updateSnapshot { snapshot in
            snapshot.selectedTaskID = serviceSnapshot.id
            snapshot.selectedTask = serviceSnapshot
        }
    }

    private func setSessions(_ sessions: StoreState<[TaskSummaryState], TaskWorkspaceServiceError>) {
        updateSnapshot { snapshot in
            snapshot.sessions = sessions
        }
    }

    private func updateSnapshot(_ update: (inout TaskWorkspaceSnapshot) -> Void) {
        update(&snapshot)
        snapshot.revision += 1
        publishSnapshot()
    }

    private func publishSnapshot() {
        for continuation in snapshotContinuations.values {
            continuation.yield(snapshot)
        }
    }
}
