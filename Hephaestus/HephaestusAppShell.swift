import Anvil
import Foundation
import HephaestusComposition
import HephaestusObservation
import HephaestusRuntime
import SwiftUI
import TaskWorkspaceFeature
import TaskWorkspaceContracts

@MainActor
struct HephaestusAppShell: View {
    @StateObject private var router: Router<AnyRouteInput, AnyModalInput>

    private let registry: DestinationRegistry
    private let runtime: PersistentAppRuntime
    private let taskSessionRegistry: TaskSessionServiceRegistry
    private let taskWorkspace: TaskWorkspaceService

    init() throws {
        let appRouter = Router<AnyRouteInput, AnyModalInput>()
        _router = StateObject(wrappedValue: appRouter)
        runtime = try PersistentAppRuntime(store: FileAppStateStore(fileURL: Self.defaultAppStateURL))
        taskSessionRegistry = TaskSessionServiceRegistry(
            createRun: runtime,
            streamUserMessage: runtime,
            loadSession: runtime,
            createSession: runtime
        )
        taskWorkspace = TaskWorkspaceService(
            registry: taskSessionRegistry,
            listSessions: runtime,
            router: appRouter
        )
        registry = try DestinationRegistry(
            routes: [TaskWorkspaceRoutes.registration],
            modals: [TaskWorkspaceRoutes.settingsModalRegistration]
        )
        let initialRoute = try AnyRouteInput(TaskWorkspaceRouteInput(taskID: nil))
        appRouter.replaceStack([initialRoute])
    }

    var body: some View {
        RouteHost(
            router: router,
            registry: registry,
            context: buildContext()
        )
    }

    private func buildContext() -> RouteBuildContext {
        RouteBuildContext(router: router) { type in
            if type == CreateRunUseCase.self {
                return runtime
            } else if type == StreamUserMessageUseCase.self {
                return runtime
            } else if type == LoadProviderSettingsUseCase.self {
                return runtime
            } else if type == SaveProviderSettingsUseCase.self {
                return runtime
            } else if type == ClearProviderSettingsUseCase.self {
                return runtime
            } else if type == ValidateProviderSettingsUseCase.self {
                return runtime
            } else if type == ListSessionsUseCase.self {
                return runtime
            } else if type == LoadSessionUseCase.self {
                return runtime
            } else if type == CreateSessionUseCase.self {
                return runtime
            } else if type == InspectRunUseCase.self {
                return runtime
            } else if type == LoadRunInspectionUseCase.self {
                return runtime
            } else if type == TaskWorkspaceService.self {
                return taskWorkspace
            } else {
                throw RouteBuildError.missingDependency(String(describing: type))
            }
        }
    }

    private static var defaultAppStateURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        return base
            .appendingPathComponent("Hephaestus", isDirectory: true)
            .appendingPathComponent("app-state.json")
    }
}

actor PersistentAppRuntime:
    CreateRunUseCase,
    StreamUserMessageUseCase,
    LoadProviderSettingsUseCase,
    SaveProviderSettingsUseCase,
    ClearProviderSettingsUseCase,
    ValidateProviderSettingsUseCase,
    ListSessionsUseCase,
    LoadSessionUseCase,
    CreateSessionUseCase,
    InspectRunUseCase,
    LoadRunInspectionUseCase
{
    private let store: AppStateStore
    private let providerOverride: RuntimeProviderSelection?
    private var harness: PersistentRuntimeHarness?

    init(
        store: AppStateStore,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) throws {
        self.store = store
        providerOverride = try RuntimeProviderConfiguration.resolveExplicitOverride(environment: environment)
    }

    func createRun() async -> UUID {
        await (await currentHarness()).createSession.createRun()
    }

    func streamUserMessage(runID: UUID, text: String) async throws -> AsyncThrowingStream<RuntimeEvent, Error> {
        try await (await currentHarness()).streamUserMessage.streamUserMessage(runID: runID, text: text)
    }

    func loadProviderSettings() async throws -> ProviderSettingsSummary? {
        try await (await currentHarness()).providerSettings.loadProviderSettings()
    }

    func saveProviderSettings(_ draft: ProviderSettingsDraft, validatedAt: Date?) async throws {
        let resolvedDraft = try await draftWithPreservedKey(draft)
        try await (await currentHarness()).providerSettings.saveProviderSettings(resolvedDraft, validatedAt: validatedAt)
        harness = nil
        _ = await currentHarness()
    }

    func clearProviderSettings() async throws {
        try await (await currentHarness()).providerSettings.clearProviderSettings()
        harness = nil
        _ = await currentHarness()
    }

    func validateProviderSettings(_ draft: ProviderSettingsDraft) async -> ProviderSettingsValidationResult {
        do {
            let resolvedDraft = try await draftWithPreservedKey(draft)
            return await (await currentHarness()).validateProviderSettings.validateProviderSettings(resolvedDraft)
        } catch {
            return .failure(String(describing: error))
        }
    }

    func listSessions() async throws -> [PersistedSessionSummary] {
        try await (await currentHarness()).listSessions.listSessions()
    }

    func loadSession(id: UUID) async throws -> PersistedSession {
        try await (await currentHarness()).loadSession.loadSession(id: id)
    }

    func createSession(title: String?) async throws -> PersistedSession {
        try await (await currentHarness()).createSession.createSession(title: title)
    }

    func inspectRun(sessionID: UUID) async throws -> PersistedRunInspection {
        try await (await currentHarness()).inspectRun.inspectRun(sessionID: sessionID)
    }

    func loadRunInspection(runID: UUID) async throws -> RunInspectionSnapshot {
        try await (await currentHarness()).inspectRun.loadRunInspection(runID: runID)
    }

    private func currentHarness() async -> PersistentRuntimeHarness {
        if let harness {
            return harness
        }

        let nextHarness = await makeHarness()
        harness = nextHarness
        return nextHarness
    }

    private func makeHarness() async -> PersistentRuntimeHarness {
        switch providerOverride {
        case .openAICompatible(let configuration):
            return RuntimeComposition.makePersistentOpenAICompatible(store: store, configuration: configuration)
        case .mock:
            return RuntimeComposition.makePersistentMock(store: store, delayNanoseconds: 80_000_000)
        case nil:
            break
        }

        if let settings = try? await storedProviderSettings(),
           let apiKey = settings.apiKey,
           !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let configuration = OpenAICompatibleEnvironmentConfiguration(
                baseURLString: settings.baseURLString,
                apiKey: apiKey,
                model: settings.model
            )
            return RuntimeComposition.makePersistentOpenAICompatible(store: store, configuration: configuration)
        }

        return RuntimeComposition.makePersistentMock(store: store, delayNanoseconds: 80_000_000)
    }

    private func draftWithPreservedKey(_ draft: ProviderSettingsDraft) async throws -> ProviderSettingsDraft {
        let apiKey = draft.apiKey?.trimmingCharacters(in: .whitespacesAndNewlines)
        if apiKey?.isEmpty == false {
            return ProviderSettingsDraft(
                baseURLString: draft.baseURLString,
                apiKey: apiKey,
                model: draft.model
            )
        }

        let existingKey = try await storedProviderSettings()?.apiKey
        return ProviderSettingsDraft(
            baseURLString: draft.baseURLString,
            apiKey: existingKey,
            model: draft.model
        )
    }

    private func storedProviderSettings() async throws -> PersistedProviderSettings? {
        try await store.load().providerSettings
    }
}
