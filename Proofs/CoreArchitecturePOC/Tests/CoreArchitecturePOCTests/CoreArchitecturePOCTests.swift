import Anvil
import ChatContracts
import ChatFeature
import HephaestusKernel
import HephaestusLLM
import LinkProbeFeature
import SwiftUI
import Testing

@Suite
struct CoreArchitecturePOCTests {
    @Test
    func typedRouteInputCanNavigateAcrossPackageBoundary() async throws {
        let router = await Router<AnyRouteInput, AnyModalInput>()
        let run = makeRun()
        let useCase = KernelSubmitUserMessageUseCase(run: run)
        let context = RouteBuildContext(router: router) { type in
            if type == SubmitUserMessageUseCase.self {
                return useCase
            }
            throw RouteBuildError.missingDependency(String(describing: type))
        }
        let registry = try DestinationRegistry(
            routes: [ChatRoutes.registration],
            modals: [ChatRoutes.settingsModalRegistration]
        )

        let input = try AnyRouteInput(ChatRouteInput(runID: nil))
        await router.push(input)

        #expect(await router.path == [input])
        _ = try await registry.buildRoute(input, context: context)
    }

    @Test
    func separateFeatureCanLinkToChatUsingContractsOnly() throws {
        let runID = UUID()
        let intent = try ChatLinkProbe.openChat(runID: runID)

        guard case .push(let erasedInput) = intent else {
            Issue.record("Expected push intent")
            return
        }

        let input = try erasedInput.decode(ChatRouteInput.self)
        #expect(input.runID == runID)
    }

    @Test
    func routeBuildFailsWhenRequiredDependencyIsMissing() async throws {
        let router = await Router<AnyRouteInput, AnyModalInput>()
        let context = RouteBuildContext(router: router) { type in
            throw RouteBuildError.missingDependency(String(describing: type))
        }
        let registry = try DestinationRegistry(
            routes: [ChatRoutes.registration],
            modals: [ChatRoutes.settingsModalRegistration]
        )
        let input = try AnyRouteInput(ChatRouteInput(runID: nil))

        await #expect(throws: RouteBuildError.missingDependency("SubmitUserMessageUseCase")) {
            _ = try await registry.buildRoute(input, context: context)
        }
    }

    @Test
    func deepLinkDecodesIntoSameRouteInputPath() async throws {
        let registry = try DestinationRegistry(
            routes: [ChatRoutes.registration],
            modals: [ChatRoutes.settingsModalRegistration]
        )
        let runID = UUID()
        let url = try #require(URL(string: "hephaestus://route/hephaestus.chat.main?runID=\(runID.uuidString)"))

        let intent = try registry.decodeDeepLink(url)

        guard case .push(let erasedInput) = intent else {
            Issue.record("Expected push intent")
            return
        }
        let input = try erasedInput.decode(ChatRouteInput.self)
        #expect(input.runID == runID)
    }

    @Test
    func modalDeepLinkUsesSeparateModalInputType() throws {
        let registry = try DestinationRegistry(
            routes: [ChatRoutes.registration],
            modals: [ChatRoutes.settingsModalRegistration]
        )
        let url = try #require(URL(string: "hephaestus://modal/hephaestus.chat.settings"))

        let intent = try registry.decodeDeepLink(url)

        guard case .presentModal(let erasedInput) = intent else {
            Issue.record("Expected modal intent")
            return
        }
        _ = try erasedInput.decode(ChatSettingsModalInput.self)
    }

    @Test
    func duplicateRouteRegistrationsFailAtStartup() throws {
        #expect(throws: DestinationRegistryError.duplicateRouteID(ChatRouteInput.routeID)) {
            try DestinationRegistry(
                routes: [ChatRoutes.registration, ChatRoutes.registration],
                modals: []
            )
        }
    }

    @Test
    func mockKernelCompletesTwoTurnsWithContinuity() async throws {
        let recorder = MockProviderRecorder()
        let run = makeRun(recorder: recorder)

        let first = try await run.submitUserMessage("first")
        let second = try await run.submitUserMessage("second")
        let requests = await recorder.allRequests()

        #expect(first.text.contains("first"))
        #expect(second.text.contains("second"))
        #expect(requests.count == 2)
        #expect(requests[1].messages.contains(ProviderMessage(role: .user, text: "first")))
        #expect(requests[1].messages.contains(where: { $0.role == .assistant && $0.text.contains("first") }))
        #expect(requests[1].messages.filter { $0.role == .user && $0.text == "second" }.count == 1)
    }

    private func makeRun(recorder: MockProviderRecorder = MockProviderRecorder()) -> Run {
        let profile = AgentProfile(
            name: "Test Agent",
            systemPrompt: "You are a test agent.",
            defaultModel: "mock-model",
            contextPolicyID: "recent"
        )
        let agent = Agent(name: "Agent", profile: profile)
        return Run(
            agent: agent,
            contextManager: RecentContextManager(),
            provider: MockProviderClient(recorder: recorder)
        )
    }
}
