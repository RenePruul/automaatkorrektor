import AutomaatkorrektorCore
import Combine
import Foundation

protocol APISettingsPersisting: Sendable {
  func string(forKey key: String) -> String?
  func set(_ value: String, forKey key: String)
}

private final class UserDefaultsAPISettingsStorage: APISettingsPersisting, @unchecked Sendable {
  private let defaults: UserDefaults

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
  }

  func string(forKey key: String) -> String? {
    defaults.string(forKey: key)
  }

  func set(_ value: String, forKey key: String) {
    defaults.set(value, forKey: key)
  }
}

@MainActor
final class APISettingsStore: ObservableObject {
  static let storageKey = "languageAPIBaseURL"

  @Published private(set) var endpoint: LanguageServiceEndpoint
  @Published private(set) var draftBaseURL: String
  @Published private(set) var validationMessage: String?

  private let storage: any APISettingsPersisting

  init(storage: any APISettingsPersisting = UserDefaultsAPISettingsStorage()) {
    self.storage = storage

    if let stored = storage.string(forKey: Self.storageKey),
      let validated = try? LanguageServiceEndpoint(validating: stored)
    {
      endpoint = validated
      draftBaseURL = stored
    } else {
      endpoint = .default
      draftBaseURL = LanguageServiceEndpoint.default.transportBaseURL
      storage.set(draftBaseURL, forKey: Self.storageKey)
    }
  }

  func updateBaseURL(_ value: String) {
    draftBaseURL = value
    do {
      let validated = try LanguageServiceEndpoint(validating: value)
      endpoint = validated
      validationMessage = nil
      storage.set(validated.transportBaseURL, forKey: Self.storageKey)
    } catch {
      validationMessage = "Kasuta HTTPS-aadressi. HTTP on lubatud ainult kohalikule teenusele."
    }
  }

  func currentConfiguration() -> LanguageCheckConfiguration {
    LanguageCheckConfiguration(endpoint: endpoint)
  }
}

extension APISettingsStore: LanguageCheckConfiguring {}
