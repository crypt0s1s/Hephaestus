import Foundation

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
