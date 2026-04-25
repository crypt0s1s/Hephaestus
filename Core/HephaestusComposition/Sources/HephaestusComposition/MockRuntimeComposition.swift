import Foundation
import HephaestusKernel
import HephaestusLLM
import HephaestusRuntime

public struct MockRuntimeHarness: Sendable {
    public let runStore: InMemoryRunStore
    public let recorder: MockProviderRecorder
    public let createRun: DefaultCreateRunUseCase
    public let streamUserMessage: DefaultStreamUserMessageUseCase
    public let submitUserMessage: DefaultSubmitUserMessageUseCase
    public let observeRunEvents: DefaultObserveRunEventsUseCase

    public init(
        runStore: InMemoryRunStore,
        recorder: MockProviderRecorder,
        createRun: DefaultCreateRunUseCase,
        streamUserMessage: DefaultStreamUserMessageUseCase,
        submitUserMessage: DefaultSubmitUserMessageUseCase,
        observeRunEvents: DefaultObserveRunEventsUseCase
    ) {
        self.runStore = runStore
        self.recorder = recorder
        self.createRun = createRun
        self.streamUserMessage = streamUserMessage
        self.submitUserMessage = submitUserMessage
        self.observeRunEvents = observeRunEvents
    }
}

public enum MockRuntimeComposition {
    public static func make(delayNanoseconds: UInt64 = 0) -> MockRuntimeHarness {
        let recorder = MockProviderRecorder()
        let eventHub = RuntimeEventHub()
        let runStore = InMemoryRunStore {
            let profile = AgentProfile(
                name: "Mock Agent",
                systemPrompt: "You are a mock assistant used for deterministic harness tests.",
                defaultModel: "mock-model",
                contextPolicyID: "recent"
            )
            let agent = Agent(name: "Mock Agent", profile: profile)
            return Run(
                agent: agent,
                contextManager: RecentContextManager(),
                provider: MockProviderClient(
                    recorder: recorder,
                    delayNanoseconds: delayNanoseconds
                )
            )
        }
        let createRun = DefaultCreateRunUseCase(runStore: runStore)
        let streamUserMessage = DefaultStreamUserMessageUseCase(
            runStore: runStore,
            eventHub: eventHub
        )
        return MockRuntimeHarness(
            runStore: runStore,
            recorder: recorder,
            createRun: createRun,
            streamUserMessage: streamUserMessage,
            submitUserMessage: DefaultSubmitUserMessageUseCase(streamUserMessage: streamUserMessage),
            observeRunEvents: DefaultObserveRunEventsUseCase(runStore: runStore, eventHub: eventHub)
        )
    }
}
