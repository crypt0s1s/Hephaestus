import Foundation
import HephaestusKernel
import HephaestusLLM
import HephaestusRuntime

struct ConfigurationFailingProviderClient: ProviderClient {
  let reason: String

  func stream(request: ProviderRequest) -> AsyncThrowingStream<ProviderResponseChunk, Error> {
    AsyncThrowingStream { continuation in
      continuation.finish(throwing: RuntimeProviderConfigurationError(reason))
    }
  }
}

public struct OpenAICompatibleProviderSettingsValidator: ValidateProviderSettingsUseCase {
  private let transport: OpenAICompatibleTransport

  public init(transport: OpenAICompatibleTransport = URLSessionOpenAICompatibleTransport()) {
    self.transport = transport
  }

  public func validateProviderSettings(_ draft: ProviderSettingsDraft) async
    -> ProviderSettingsValidationResult {
    let baseURLString = draft.baseURLString.trimmingCharacters(in: .whitespacesAndNewlines)
    let model = draft.model.trimmingCharacters(in: .whitespacesAndNewlines)
    let apiKey = draft.apiKey?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

    guard !apiKey.isEmpty else {
      return .failure("API key is required.")
    }
    guard !model.isEmpty else {
      return .failure("Model is required.")
    }
    guard let baseURL = URL(string: baseURLString),
      baseURL.scheme?.isEmpty == false,
      baseURL.host?.isEmpty == false
    else {
      return .failure("Base URL is invalid.")
    }

    let provider = OpenAICompatibleProviderClient(
      configuration: OpenAICompatibleClientConfiguration(
        baseURL: baseURL,
        apiKey: apiKey,
        model: model
      ),
      transport: transport
    )
    let request = ProviderRequest(
      runID: UUID(),
      turnID: UUID(),
      model: model,
      messages: [
        ProviderMessage(role: .system, text: "Validate the Hephaestus provider configuration."),
        ProviderMessage(role: .user, text: "Reply with ok."),
      ],
      stream: false
    )

    do {
      for try await _ in provider.stream(request: request) {}
      return .success
    } catch {
      return .failure(String(describing: error))
    }
  }
}
