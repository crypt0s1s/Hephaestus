import Foundation
import HephaestusKernel

public protocol LoadProviderSettingsUseCase: Sendable {
    func loadProviderSettings() async throws -> ProviderSettingsSummary?
}

public protocol SaveProviderSettingsUseCase: Sendable {
    func saveProviderSettings(_ draft: ProviderSettingsDraft, validatedAt: Date?) async throws
}

public protocol ClearProviderSettingsUseCase: Sendable {
    func clearProviderSettings() async throws
}

public protocol ValidateProviderSettingsUseCase: Sendable {
    func validateProviderSettings(_ draft: ProviderSettingsDraft) async -> ProviderSettingsValidationResult
}

public protocol ListSessionsUseCase: Sendable {
    func listSessions() async throws -> [PersistedSessionSummary]
}

public protocol LoadSessionUseCase: Sendable {
    func loadSession(id: UUID) async throws -> PersistedSession
}

public protocol CreateSessionUseCase: Sendable {
    func createSession(title: String?) async throws -> PersistedSession
}

public protocol InspectRunUseCase: Sendable {
    func inspectRun(sessionID: UUID) async throws -> PersistedRunInspection
}

public struct DefaultProviderSettingsUseCase:
    LoadProviderSettingsUseCase,
    SaveProviderSettingsUseCase,
    ClearProviderSettingsUseCase
{
    private let store: AppStateStore

    public init(store: AppStateStore) {
        self.store = store
    }

    public func loadProviderSettings() async throws -> ProviderSettingsSummary? {
        guard let settings = try await store.load().providerSettings else {
            return nil
        }
        return settings.summary
    }

    public func saveProviderSettings(_ draft: ProviderSettingsDraft, validatedAt: Date?) async throws {
        var state = try await store.load()
        state.providerSettings = PersistedProviderSettings(
            baseURLString: draft.baseURLString,
            apiKey: draft.apiKey,
            model: draft.model,
            validatedAt: validatedAt
        )
        try await store.save(state)
    }

    public func clearProviderSettings() async throws {
        var state = try await store.load()
        state.providerSettings = nil
        try await store.save(state)
    }
}

public struct DefaultListSessionsUseCase: ListSessionsUseCase {
    private let store: AppStateStore

    public init(store: AppStateStore) {
        self.store = store
    }

    public func listSessions() async throws -> [PersistedSessionSummary] {
        try await store.load().sessions
            .map(\.summary)
            .sorted { $0.updatedAt > $1.updatedAt }
    }
}

public struct DefaultLoadSessionUseCase: LoadSessionUseCase {
    private let store: AppStateStore
    private let runStore: InMemoryRunStore
    private let makeRun: @Sendable (PersistedSession) -> Run

    public init(
        store: AppStateStore,
        runStore: InMemoryRunStore,
        makeRun: @escaping @Sendable (PersistedSession) -> Run
    ) {
        self.store = store
        self.runStore = runStore
        self.makeRun = makeRun
    }

    public func loadSession(id: UUID) async throws -> PersistedSession {
        let session = try await session(id: id)
        if await !runStore.contains(id: id) {
            await runStore.insert(makeRun(session))
        }
        return session
    }

    private func session(id: UUID) async throws -> PersistedSession {
        let state = try await store.load()
        guard let session = state.sessions.first(where: { $0.id == id }) else {
            throw AppStateStoreFailure.sessionNotFound(id)
        }
        return session
    }
}

public struct DefaultCreateSessionUseCase: CreateRunUseCase, CreateSessionUseCase {
    private let store: AppStateStore
    private let runStore: InMemoryRunStore
    private let makeRun: @Sendable (PersistedSession) -> Run

    public init(
        store: AppStateStore,
        runStore: InMemoryRunStore,
        makeRun: @escaping @Sendable (PersistedSession) -> Run
    ) {
        self.store = store
        self.runStore = runStore
        self.makeRun = makeRun
    }

    public func createRun() async -> UUID {
        do {
            return try await createSession(title: nil).id
        } catch {
            return await runStore.createRun()
        }
    }

    public func createSession(title: String?) async throws -> PersistedSession {
        let now = Date()
        let session = PersistedSession(
            title: title?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? "New Chat",
            createdAt: now,
            updatedAt: now
        )
        var state = try await store.load()
        state.sessions.append(session)
        try await store.save(state)
        await runStore.insert(makeRun(session))
        return session
    }
}

public struct DefaultInspectRunUseCase: InspectRunUseCase {
    private let store: AppStateStore

    public init(store: AppStateStore) {
        self.store = store
    }

    public func inspectRun(sessionID: UUID) async throws -> PersistedRunInspection {
        let state = try await store.load()
        guard let session = state.sessions.first(where: { $0.id == sessionID }) else {
            throw AppStateStoreFailure.sessionNotFound(sessionID)
        }
        return PersistedRunInspection(session: session)
    }
}

public struct PersistentStreamUserMessageUseCase: StreamUserMessageUseCase {
    private let store: AppStateStore
    private let runStore: InMemoryRunStore
    private let eventHub: RuntimeEventHub
    private let makeRun: @Sendable (PersistedSession) -> Run

    public init(
        store: AppStateStore,
        runStore: InMemoryRunStore,
        eventHub: RuntimeEventHub,
        makeRun: @escaping @Sendable (PersistedSession) -> Run
    ) {
        self.store = store
        self.runStore = runStore
        self.eventHub = eventHub
        self.makeRun = makeRun
    }

    public func streamUserMessage(
        runID: UUID,
        text: String
    ) async throws -> AsyncThrowingStream<RuntimeEvent, Error> {
        let session = try await session(id: runID)
        if await !runStore.contains(id: runID) {
            await runStore.insert(makeRun(session))
        }

        let run = try await runStore.run(id: runID)
        let runEvents = await run.streamUserMessage(text)

        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    for try await event in runEvents {
                        let runtimeEvent = RuntimeEvent(event)
                        try await persist(event, runtimeEvent: runtimeEvent, sessionID: runID)
                        await eventHub.publish(runtimeEvent, runID: runID)
                        continuation.yield(runtimeEvent)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { @Sendable _ in
                task.cancel()
            }
        }
    }

    private func session(id: UUID) async throws -> PersistedSession {
        let state = try await store.load()
        guard let session = state.sessions.first(where: { $0.id == id }) else {
            throw AppStateStoreFailure.sessionNotFound(id)
        }
        return session
    }

    private func persist(
        _ event: RunEvent,
        runtimeEvent: RuntimeEvent,
        sessionID: UUID
    ) async throws {
        var state = try await store.load()
        guard let index = state.sessions.firstIndex(where: { $0.id == sessionID }) else {
            throw AppStateStoreFailure.sessionNotFound(sessionID)
        }

        var session = state.sessions[index]
        session.apply(event, runtimeEvent: runtimeEvent)
        state.sessions[index] = session
        try await store.save(state)
    }
}

extension PersistedProviderSettings {
    public var summary: ProviderSettingsSummary {
        ProviderSettingsSummary(
            baseURLString: baseURLString,
            model: model,
            hasSavedAPIKey: apiKey?.isEmpty == false,
            validatedAt: validatedAt
        )
    }
}

extension PersistedSession {
    public var summary: PersistedSessionSummary {
        PersistedSessionSummary(
            id: id,
            title: title,
            createdAt: createdAt,
            updatedAt: updatedAt,
            messageCount: messages.count
        )
    }

    mutating func apply(_ event: RunEvent, runtimeEvent: RuntimeEvent) {
        updatedAt = runtimeEvent.header.createdAt
        events.append(PersistedRuntimeEvent(runtimeEvent))

        switch event {
        case .userMessageAccepted(_, let message):
            messages.append(message)
            title = title == "New Chat" ? message.text.firstLineTitle : title
            turns.append(Turn(
                id: message.turnID ?? runtimeEvent.header.turnID ?? UUID(),
                runID: id,
                status: .accepted,
                userMessageID: message.id
            ))
        case .contextPrepared(let header, let trace):
            guard let turnID = header.turnID else { return }
            contextTraces.append(PersistedContextTrace(
                runID: id,
                turnID: turnID,
                policyID: "recent",
                policyName: "Recent messages",
                messageLimit: trace.messageLimit,
                includedMessageIDs: trace.includedMessageIDs,
                excludedMessageIDs: trace.excludedMessageIDs,
                createdAt: header.createdAt
            ))
            updateTurn(turnID) { $0.status = .preparingContext }
        case .providerRequestPrepared(let header, let request):
            guard let turnID = header.turnID else { return }
            providerRequests.append(PersistedProviderRequestSummary(request: request, createdAt: header.createdAt))
            updateTurn(turnID) {
                $0.status = .awaitingProvider
                $0.providerRequestID = request.id
            }
        case .providerChunkReceived(let header, _, _):
            guard let turnID = header.turnID else { return }
            updateTurn(turnID) { $0.status = .streaming }
        case .assistantMessageCompleted(_, let message):
            messages.append(message)
            if let turnID = message.turnID {
                updateTurn(turnID) {
                    $0.status = .succeeded
                    $0.assistantMessageID = message.id
                }
            }
        case .turnCancelled(let header):
            guard let turnID = header.turnID else { return }
            updateTurn(turnID) { $0.status = .cancelled }
        case .turnFailed(let header, _):
            guard let turnID = header.turnID else { return }
            updateTurn(turnID) { $0.status = .failed }
        }
    }

    private mutating func updateTurn(_ id: UUID, update: (inout Turn) -> Void) {
        guard let index = turns.firstIndex(where: { $0.id == id }) else { return }
        update(&turns[index])
    }
}

extension PersistedRuntimeEvent {
    public init(_ event: RuntimeEvent) {
        switch event {
        case .runCreated(let header, let runID):
            self.init(header: header, kind: .runCreated, summary: "Run created", messageID: runID)
        case .userMessageAccepted(let header, let messageID, let text):
            self.init(header: header, kind: .userMessageAccepted, summary: "User message accepted: \(text)", messageID: messageID)
        case .contextPrepared(let header, let includedMessageCount):
            self.init(header: header, kind: .contextPrepared, summary: "Context prepared with \(includedMessageCount) messages")
        case .providerRequestPrepared(let header, let requestID, let model, let messageCount):
            self.init(
                header: header,
                kind: .providerRequestPrepared,
                summary: "Provider request prepared for \(model) with \(messageCount) messages",
                providerRequestID: requestID
            )
        case .assistantTextDelta(let header, let text):
            self.init(header: header, kind: .assistantTextDelta, summary: "Assistant delta: \(text)")
        case .assistantMessageCompleted(let header, let messageID, let text):
            self.init(header: header, kind: .assistantMessageCompleted, summary: "Assistant message completed: \(text)", messageID: messageID)
        case .turnCancelled(let header):
            self.init(header: header, kind: .turnCancelled, summary: "Turn cancelled")
        case .turnFailed(let header, let reason):
            self.init(header: header, kind: .turnFailed, summary: "Turn failed: \(reason)", error: reason)
        }
    }

    private init(
        header: RuntimeEventHeader,
        kind: Kind,
        summary: String,
        messageID: UUID? = nil,
        providerRequestID: UUID? = nil,
        error: String? = nil
    ) {
        self.init(
            id: header.id,
            runID: header.runID,
            turnID: header.turnID,
            sequence: header.sequence,
            createdAt: header.createdAt,
            kind: kind,
            summary: summary,
            messageID: messageID,
            providerRequestID: providerRequestID,
            error: error
        )
    }
}

extension PersistedProviderRequestSummary {
    public init(request: ProviderRequest, createdAt: Date) {
        self.init(
            id: request.id,
            runID: request.runID,
            turnID: request.turnID,
            model: request.model,
            messageCount: request.messages.count,
            systemPromptIncluded: request.messages.contains(where: { $0.role == .system }),
            stream: request.stream,
            createdAt: createdAt
        )
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }

    var firstLineTitle: String {
        let firstLine = split(whereSeparator: \.isNewline).first.map(String.init) ?? self
        let trimmed = firstLine.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "New Chat" : String(trimmed.prefix(80))
    }
}
