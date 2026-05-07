import Foundation
import HephaestusRuntime

@MainActor
public final class TaskSessionServiceRegistry {
    private let createRun: CreateRunUseCase
    private let streamUserMessage: StreamUserMessageUseCase
    private let loadSession: LoadSessionUseCase?
    private let createSession: CreateSessionUseCase?
    private var services: [UUID: TaskSessionService] = [:]
    private var onServiceSummaryChanged: @MainActor () -> Void = {}

    public init(
        createRun: CreateRunUseCase,
        streamUserMessage: StreamUserMessageUseCase,
        loadSession: LoadSessionUseCase? = nil,
        createSession: CreateSessionUseCase? = nil
    ) {
        self.createRun = createRun
        self.streamUserMessage = streamUserMessage
        self.loadSession = loadSession
        self.createSession = createSession
    }

    public func setOnServiceSummaryChanged(_ onServiceSummaryChanged: @escaping @MainActor () -> Void) {
        self.onServiceSummaryChanged = onServiceSummaryChanged
    }

    public func service(for id: UUID) async throws -> TaskSessionService {
        if let service = services[id] {
            return service
        }

        let service: TaskSessionService
        if let loadSession {
            let session = try await loadSession.loadSession(id: id)
            service = makeService(session: session)
        } else {
            service = makeService(snapshot: TaskSessionSnapshot(id: id, title: "New Task"))
        }
        services[service.id] = service
        return service
    }

    public func createService(title: String? = nil) async throws -> TaskSessionService {
        let service: TaskSessionService
        if let createSession {
            let session = try await createSession.createSession(title: title)
            service = makeService(session: session)
        } else {
            let id = await createRun.createRun()
            service = makeService(snapshot: TaskSessionSnapshot(id: id, title: title ?? "New Task"))
        }

        services[service.id] = service
        return service
    }

    private func makeService(session: PersistedSession) -> TaskSessionService {
        TaskSessionService(
            session: session,
            streamUserMessage: streamUserMessage,
            onSummaryChanged: onServiceSummaryChanged
        )
    }

    private func makeService(snapshot: TaskSessionSnapshot) -> TaskSessionService {
        TaskSessionService(
            snapshot: snapshot,
            streamUserMessage: streamUserMessage,
            onSummaryChanged: onServiceSummaryChanged
        )
    }
}
