import Anvil
import Foundation
import HephaestusKernel
import HephaestusObservation
import HephaestusRuntime
import TaskWorkspaceContracts
import TaskWorkspaceFeature
import Testing

@MainActor
func makeInteractor(
  runID: UUID?,
  createRun: CreateRunUseCase = RecordingCreateRunUseCase(runID: UUID()),
  streamUserMessage: StreamUserMessageUseCase,
  sessionRegistry: TaskSessionServiceRegistry? = nil,
  workspace: TaskWorkspaceService? = nil,
  loadProviderSettings: LoadProviderSettingsUseCase? = nil,
  saveProviderSettings: SaveProviderSettingsUseCase? = nil,
  clearProviderSettings: ClearProviderSettingsUseCase? = nil,
  validateProviderSettings: ValidateProviderSettingsUseCase? = nil,
  listSessions: ListSessionsUseCase? = nil,
  loadSession: LoadSessionUseCase? = nil,
  createSession: CreateSessionUseCase? = nil,
  loadRunInspection: LoadRunInspectionUseCase? = nil,
  router: Router<AnyRouteInput, AnyModalInput>? = nil
) -> TaskWorkspaceInteractor {
  let registry =
    sessionRegistry
    ?? TaskSessionServiceRegistry(
      createRun: createRun,
      streamUserMessage: streamUserMessage,
      loadSession: loadSession,
      createSession: createSession
    )
  let workspace =
    workspace
    ?? TaskWorkspaceService(
      registry: registry,
      listSessions: listSessions,
      router: router
    )
  return TaskWorkspaceInteractor(
    input: TaskWorkspaceRouteInput(taskID: runID),
    workspace: workspace,
    loadProviderSettings: loadProviderSettings,
    saveProviderSettings: saveProviderSettings,
    clearProviderSettings: clearProviderSettings,
    validateProviderSettings: validateProviderSettings,
    loadRunInspection: loadRunInspection
  )
}

func runtimeHeader(
  runID: UUID,
  turnID: UUID?,
  sequence: Int
) -> RuntimeEventHeader {
  RuntimeEventHeader(
    id: UUID(),
    runID: runID,
    turnID: turnID,
    sequence: sequence,
    createdAt: Date()
  )
}

@MainActor
func waitUntil(
  _ predicate: @escaping @MainActor () -> Bool,
  sourceLocation: SourceLocation = #_sourceLocation
) async {
  for _ in 0..<100 {
    if predicate() {
      return
    }
    try? await Task.sleep(nanoseconds: 5_000_000)
  }
  Issue.record("Timed out waiting for state transition", sourceLocation: sourceLocation)
}

struct ConversationStreamRequest: Equatable, Sendable {
  let runID: UUID
  let text: String
}

actor RecordingCreateRunUseCase: CreateRunUseCase {
  private let runID: UUID
  private var callCount = 0

  init(runID: UUID) {
    self.runID = runID
  }

  func createRun() async -> UUID {
    callCount += 1
    return runID
  }

  func calls() -> Int {
    callCount
  }
}

actor ImmediateStreamUserMessageUseCase: StreamUserMessageUseCase {
  private var recordedRequests: [ConversationStreamRequest] = []

  func streamUserMessage(
    runID: UUID,
    text: String
  ) async throws -> AsyncThrowingStream<RuntimeEvent, Error> {
    recordedRequests.append(ConversationStreamRequest(runID: runID, text: text))

    return AsyncThrowingStream { continuation in
      let turnID = UUID()
      continuation.yield(
        .userMessageAccepted(
          runtimeHeader(runID: runID, turnID: turnID, sequence: 1),
          messageID: UUID(),
          text: text
        ))
      continuation.yield(
        .assistantMessageCompleted(
          runtimeHeader(runID: runID, turnID: turnID, sequence: 2),
          messageID: UUID(),
          text: "done \(text)"
        ))
      continuation.finish()
    }
  }

  func requests() -> [ConversationStreamRequest] {
    recordedRequests
  }
}

actor ControlledStreamUserMessageUseCase: StreamUserMessageUseCase {
  private typealias Continuation = AsyncThrowingStream<RuntimeEvent, Error>.Continuation

  private var recordedRequests: [ConversationStreamRequest] = []
  private var continuation: Continuation?
  private var requestWaiters: [CheckedContinuation<Void, Never>] = []
  private var streamWaiters: [CheckedContinuation<Void, Never>] = []
  private var terminationCount = 0
  private var terminationWaiters: [CheckedContinuation<Void, Never>] = []

  func streamUserMessage(
    runID: UUID,
    text: String
  ) async throws -> AsyncThrowingStream<RuntimeEvent, Error> {
    recordedRequests.append(ConversationStreamRequest(runID: runID, text: text))
    resumeRequestWaiters()

    return AsyncThrowingStream { continuation in
      continuation.onTermination = { @Sendable _ in
        Task {
          await self.recordTermination()
        }
      }
      Task {
        self.setContinuation(continuation)
      }
    }
  }

  func yield(_ event: RuntimeEvent) {
    continuation?.yield(event)
  }

  func finish() {
    continuation?.finish()
    continuation = nil
  }

  func waitUntilRequestCount(_ expectedCount: Int) async {
    if recordedRequests.count < expectedCount {
      await withCheckedContinuation { waiter in
        requestWaiters.append(waiter)
      }
    }

    if continuation == nil {
      await withCheckedContinuation { waiter in
        streamWaiters.append(waiter)
      }
    }
  }

  func waitUntilTerminationCount(_ expectedCount: Int) async {
    if terminationCount >= expectedCount {
      return
    }

    await withCheckedContinuation { waiter in
      terminationWaiters.append(waiter)
    }
  }

  func requests() -> [ConversationStreamRequest] {
    recordedRequests
  }

  private func setContinuation(_ continuation: Continuation) {
    self.continuation = continuation
    let waiters = streamWaiters
    streamWaiters.removeAll()
    for waiter in waiters {
      waiter.resume()
    }
  }

  private func resumeRequestWaiters() {
    let waiters = requestWaiters
    requestWaiters.removeAll()
    for waiter in waiters {
      waiter.resume()
    }
  }

  private func recordTermination() {
    terminationCount += 1
    let waiters = terminationWaiters
    terminationWaiters.removeAll()
    for waiter in waiters {
      waiter.resume()
    }
  }
}

actor StubSessionUseCase: ListSessionsUseCase, LoadSessionUseCase, CreateSessionUseCase {
  private var sessions: [PersistedSession]
  private let createdSession: PersistedSession
  private var createCalls = 0
  private var loadCalls = 0
  private var listCalls = 0

  init(
    sessions: [PersistedSession],
    createdSession: PersistedSession = PersistedSession(title: "New Task")
  ) {
    self.sessions = sessions
    self.createdSession = createdSession
  }

  func listSessions() async throws -> [PersistedSessionSummary] {
    listCalls += 1
    return sessions.map(\.summary)
  }

  func loadSession(id: UUID) async throws -> PersistedSession {
    loadCalls += 1
    guard let session = sessions.first(where: { $0.id == id }) else {
      throw AppStateStoreFailure.sessionNotFound(id)
    }
    return session
  }

  func createSession(title: String?) async throws -> PersistedSession {
    createCalls += 1
    sessions.append(createdSession)
    return createdSession
  }

  func createdCount() -> Int {
    createCalls
  }

  func loadedCount() -> Int {
    loadCalls
  }

  func listedCount() -> Int {
    listCalls
  }
}

actor StubProviderSettingsUseCase:
  LoadProviderSettingsUseCase,
  SaveProviderSettingsUseCase,
  ClearProviderSettingsUseCase,
  ValidateProviderSettingsUseCase {
  private var summary: ProviderSettingsSummary?
  private var saved: ProviderSettingsDraft?
  private var cleared = false
  var validationResult: ProviderSettingsValidationResult = .success

  func loadProviderSettings() async throws -> ProviderSettingsSummary? {
    summary
  }

  func saveProviderSettings(_ draft: ProviderSettingsDraft, validatedAt: Date?) async throws {
    saved = draft
    summary = ProviderSettingsSummary(
      baseURLString: draft.baseURLString,
      model: draft.model,
      hasSavedAPIKey: draft.apiKey?.isEmpty == false,
      validatedAt: validatedAt
    )
  }

  func clearProviderSettings() async throws {
    summary = nil
    saved = nil
    cleared = true
  }

  func validateProviderSettings(_ draft: ProviderSettingsDraft) async
    -> ProviderSettingsValidationResult {
    validationResult
  }

  func savedDraft() -> ProviderSettingsDraft? {
    saved
  }

  func wasCleared() -> Bool {
    cleared
  }
}

actor StubLoadRunInspectionUseCase: LoadRunInspectionUseCase {
  private let inspection: RunInspectionSnapshot

  init(inspection: RunInspectionSnapshot) {
    self.inspection = inspection
  }

  func loadRunInspection(runID: UUID) async throws -> RunInspectionSnapshot {
    inspection
  }
}

struct FailingListSessionsUseCase: ListSessionsUseCase {
  func listSessions() async throws -> [PersistedSessionSummary] {
    throw StubFailure.boom
  }
}

struct FailingLoadSessionUseCase: LoadSessionUseCase {
  func loadSession(id: UUID) async throws -> PersistedSession {
    throw StubFailure.boom
  }
}

enum StubFailure: Error, CustomStringConvertible {
  case boom

  var description: String {
    "boom"
  }
}
