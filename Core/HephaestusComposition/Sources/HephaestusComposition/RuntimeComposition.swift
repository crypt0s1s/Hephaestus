import Foundation
import HephaestusHarness
import HephaestusKernel
import HephaestusLLM
import HephaestusRuntime

public struct RuntimeHarness: Sendable {
    public let runStore: InMemoryRunStore
    public let createRun: DefaultCreateRunUseCase
    public let streamUserMessage: DefaultStreamUserMessageUseCase
    public let submitUserMessage: DefaultSubmitUserMessageUseCase
    public let observeRunEvents: DefaultObserveRunEventsUseCase

    public init(
        runStore: InMemoryRunStore,
        createRun: DefaultCreateRunUseCase,
        streamUserMessage: DefaultStreamUserMessageUseCase,
        submitUserMessage: DefaultSubmitUserMessageUseCase,
        observeRunEvents: DefaultObserveRunEventsUseCase
    ) {
        self.runStore = runStore
        self.createRun = createRun
        self.streamUserMessage = streamUserMessage
        self.submitUserMessage = submitUserMessage
        self.observeRunEvents = observeRunEvents
    }
}

public struct PersistentRuntimeHarness: Sendable {
    public let store: AppStateStore
    public let runStore: InMemoryRunStore
    public let providerSettings: DefaultProviderSettingsUseCase
    public let validateProviderSettings: OpenAICompatibleProviderSettingsValidator
    public let listSessions: DefaultListSessionsUseCase
    public let loadSession: DefaultLoadSessionUseCase
    public let createSession: DefaultCreateSessionUseCase
    public let streamUserMessage: PersistentStreamUserMessageUseCase
    public let submitUserMessage: DefaultSubmitUserMessageUseCase
    public let observeRunEvents: DefaultObserveRunEventsUseCase
    public let inspectRun: DefaultInspectRunUseCase

    public init(
        store: AppStateStore,
        runStore: InMemoryRunStore,
        providerSettings: DefaultProviderSettingsUseCase,
        validateProviderSettings: OpenAICompatibleProviderSettingsValidator,
        listSessions: DefaultListSessionsUseCase,
        loadSession: DefaultLoadSessionUseCase,
        createSession: DefaultCreateSessionUseCase,
        streamUserMessage: PersistentStreamUserMessageUseCase,
        submitUserMessage: DefaultSubmitUserMessageUseCase,
        observeRunEvents: DefaultObserveRunEventsUseCase,
        inspectRun: DefaultInspectRunUseCase
    ) {
        self.store = store
        self.runStore = runStore
        self.providerSettings = providerSettings
        self.validateProviderSettings = validateProviderSettings
        self.listSessions = listSessions
        self.loadSession = loadSession
        self.createSession = createSession
        self.streamUserMessage = streamUserMessage
        self.submitUserMessage = submitUserMessage
        self.observeRunEvents = observeRunEvents
        self.inspectRun = inspectRun
    }
}

public enum RuntimeProviderMode: String, Sendable, Equatable {
    case mock
    case openAICompatible = "openai-compatible"
}

public struct OpenAICompatibleEnvironmentConfiguration: Sendable, Equatable {
    public static let defaultBaseURL = "https://api.openai.com/v1"
    public static let defaultModel = "gpt-4.1-mini"

    public let baseURLString: String
    public let apiKey: String?
    public let model: String

    public init(baseURLString: String, apiKey: String?, model: String) {
        self.baseURLString = baseURLString
        self.apiKey = apiKey
        self.model = model
    }
}

public enum RuntimeProviderSelection: Sendable, Equatable {
    case mock
    case openAICompatible(OpenAICompatibleEnvironmentConfiguration)
}

public struct RuntimeProviderConfigurationError: Error, Sendable, Equatable, CustomStringConvertible {
    public let description: String

    public init(_ description: String) {
        self.description = description
    }
}

public enum RuntimeProviderConfiguration {
    public static func resolveExplicitOverride(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) throws -> RuntimeProviderSelection? {
        guard let provider = trimmed(environment["HEPHAESTUS_PROVIDER"]),
            !provider.isEmpty
        else {
            return nil
        }

        return try resolve(environment: environment)
    }

    public static func resolve(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) throws -> RuntimeProviderSelection {
        let provider = trimmed(environment["HEPHAESTUS_PROVIDER"])
        let modeValue = provider?.isEmpty == false ? provider! : RuntimeProviderMode.mock.rawValue

        guard let mode = RuntimeProviderMode(rawValue: modeValue) else {
            throw RuntimeProviderConfigurationError(
                "Unsupported HEPHAESTUS_PROVIDER '\(modeValue)'. Use 'mock' or 'openai-compatible'."
            )
        }

        switch mode {
        case .mock:
            return .mock
        case .openAICompatible:
            return .openAICompatible(
                OpenAICompatibleEnvironmentConfiguration(
                    baseURLString: nonEmpty(
                        environment["HEPHAESTUS_OPENAI_BASE_URL"],
                        default: OpenAICompatibleEnvironmentConfiguration.defaultBaseURL
                    ),
                    apiKey: trimmed(environment["HEPHAESTUS_OPENAI_API_KEY"]),
                    model: nonEmpty(
                        environment["HEPHAESTUS_OPENAI_MODEL"],
                        default: OpenAICompatibleEnvironmentConfiguration.defaultModel
                    )
                )
            )
        }
    }

    private static func trimmed(_ value: String?) -> String? {
        value?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func nonEmpty(_ value: String?, default defaultValue: String) -> String {
        let trimmedValue = trimmed(value)
        return trimmedValue?.isEmpty == false ? trimmedValue! : defaultValue
    }
}

public enum RuntimeComposition {
    public static var nativeBackendDescriptor: HarnessBackendDescriptor {
        FoundryBackend.descriptor
    }

    public static func make(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        mockDelayNanoseconds: UInt64 = 0
    ) throws -> RuntimeHarness {
        switch try RuntimeProviderConfiguration.resolve(environment: environment) {
        case .mock:
            return makeMock(delayNanoseconds: mockDelayNanoseconds)
        case .openAICompatible(let configuration):
            return makeOpenAICompatible(configuration: configuration)
        }
    }

    public static func makeMock(delayNanoseconds: UInt64 = 0) -> RuntimeHarness {
        let harness = MockRuntimeComposition.make(delayNanoseconds: delayNanoseconds)
        return RuntimeHarness(
            runStore: harness.runStore,
            createRun: harness.createRun,
            streamUserMessage: harness.streamUserMessage,
            submitUserMessage: harness.submitUserMessage,
            observeRunEvents: harness.observeRunEvents
        )
    }

    public static func makeOpenAICompatible(
        configuration: OpenAICompatibleEnvironmentConfiguration,
        transport: OpenAICompatibleTransport = URLSessionOpenAICompatibleTransport()
    ) -> RuntimeHarness {
        let provider = makeProvider(configuration: configuration, transport: transport)
        let eventHub = RuntimeEventHub()
        let runStore = InMemoryRunStore {
            let profile = AgentProfile(
                name: "OpenAI-Compatible Agent",
                systemPrompt: "You are a helpful assistant in the Hephaestus harness.",
                defaultModel: configuration.model,
                contextPolicyID: "recent"
            )
            let agent = Agent(name: "OpenAI-Compatible Agent", profile: profile)
            return Run(
                agent: agent,
                contextManager: RecentContextManager(),
                provider: provider
            )
        }
        let createRun = DefaultCreateRunUseCase(runStore: runStore)
        let streamUserMessage = DefaultStreamUserMessageUseCase(
            runStore: runStore,
            eventHub: eventHub
        )
        return RuntimeHarness(
            runStore: runStore,
            createRun: createRun,
            streamUserMessage: streamUserMessage,
            submitUserMessage: DefaultSubmitUserMessageUseCase(streamUserMessage: streamUserMessage),
            observeRunEvents: DefaultObserveRunEventsUseCase(runStore: runStore, eventHub: eventHub)
        )
    }

    public static func makePersistentMock(
        store: AppStateStore,
        delayNanoseconds: UInt64 = 0,
        messageLimit: Int = 20
    ) -> PersistentRuntimeHarness {
        let recorder = MockProviderRecorder()
        let provider = MockProviderClient(recorder: recorder, delayNanoseconds: delayNanoseconds)
        return makePersistent(
            store: store,
            provider: provider,
            agentName: "Mock Agent",
            model: "mock-model",
            systemPrompt: "You are a helpful mock assistant in the Hephaestus harness.",
            messageLimit: messageLimit,
            validationTransport: URLSessionOpenAICompatibleTransport()
        )
    }

    public static func makePersistentOpenAICompatible(
        store: AppStateStore,
        configuration: OpenAICompatibleEnvironmentConfiguration,
        transport: OpenAICompatibleTransport = URLSessionOpenAICompatibleTransport(),
        messageLimit: Int = 20
    ) -> PersistentRuntimeHarness {
        makePersistent(
            store: store,
            provider: makeProvider(configuration: configuration, transport: transport),
            agentName: "OpenAI-Compatible Agent",
            model: configuration.model,
            systemPrompt: "You are a helpful assistant in the Hephaestus harness.",
            messageLimit: messageLimit,
            validationTransport: transport
        )
    }

    private static func makePersistent(
        store: AppStateStore,
        provider: any ProviderClient,
        agentName: String,
        model: String,
        systemPrompt: String,
        messageLimit: Int,
        validationTransport: OpenAICompatibleTransport
    ) -> PersistentRuntimeHarness {
        let eventHub = RuntimeEventHub()
        let makeRun = persistentRunFactory(
            provider: provider,
            agentName: agentName,
            model: model,
            systemPrompt: systemPrompt,
            messageLimit: messageLimit
        )
        let runStore = InMemoryRunStore {
            makeRun(PersistedSession(title: "New Chat"))
        }
        let providerSettings = DefaultProviderSettingsUseCase(store: store)
        let listSessions = DefaultListSessionsUseCase(store: store)
        let loadSession = DefaultLoadSessionUseCase(store: store, runStore: runStore, makeRun: makeRun)
        let createSession = DefaultCreateSessionUseCase(
            store: store, runStore: runStore, makeRun: makeRun)
        let streamUserMessage = PersistentStreamUserMessageUseCase(
            store: store,
            runStore: runStore,
            eventHub: eventHub,
            makeRun: makeRun
        )
        return PersistentRuntimeHarness(
            store: store,
            runStore: runStore,
            providerSettings: providerSettings,
            validateProviderSettings: OpenAICompatibleProviderSettingsValidator(
                transport: validationTransport),
            listSessions: listSessions,
            loadSession: loadSession,
            createSession: createSession,
            streamUserMessage: streamUserMessage,
            submitUserMessage: DefaultSubmitUserMessageUseCase(streamUserMessage: streamUserMessage),
            observeRunEvents: DefaultObserveRunEventsUseCase(runStore: runStore, eventHub: eventHub),
            inspectRun: DefaultInspectRunUseCase(store: store)
        )
    }

    private static func persistentRunFactory(
        provider: any ProviderClient,
        agentName: String,
        model: String,
        systemPrompt: String,
        messageLimit: Int
    ) -> @Sendable (PersistedSession) -> Run {
        { session in
            Run(
                id: session.id,
                agent: Agent(
                    name: agentName,
                    profile: AgentProfile(
                        name: agentName,
                        systemPrompt: systemPrompt,
                        defaultModel: model,
                        contextPolicyID: "recent"
                    )
                ),
                contextManager: RecentContextManager(messageLimit: messageLimit),
                provider: provider,
                initialMessages: session.messages,
                initialTurns: session.turns,
                initialSequence: session.events.map(\.sequence).max() ?? 0
            )
        }
    }

    private static func makeProvider(
        configuration: OpenAICompatibleEnvironmentConfiguration,
        transport: OpenAICompatibleTransport
    ) -> any ProviderClient {
        guard let apiKey = configuration.apiKey, !apiKey.isEmpty else {
            return ConfigurationFailingProviderClient(
                reason: "Missing HEPHAESTUS_OPENAI_API_KEY for HEPHAESTUS_PROVIDER=openai-compatible."
            )
        }

        guard let baseURL = URL(string: configuration.baseURLString),
            baseURL.scheme?.isEmpty == false,
            baseURL.host?.isEmpty == false
        else {
            return ConfigurationFailingProviderClient(
                reason: "Invalid HEPHAESTUS_OPENAI_BASE_URL '\(configuration.baseURLString)'."
            )
        }

        return OpenAICompatibleProviderClient(
            configuration: OpenAICompatibleClientConfiguration(
                baseURL: baseURL,
                apiKey: apiKey,
                model: configuration.model
            ),
            transport: transport
        )
    }
}
