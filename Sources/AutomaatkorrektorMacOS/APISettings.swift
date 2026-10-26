import Combine
import Foundation

struct APIBaseURL: Sendable, Equatable {
  enum ValidationError: Error {
    case invalid
  }

  static let `default` = try! APIBaseURL(validating: "http://127.0.0.1:8000")

  let url: URL

  init(validating value: String) throws {
    guard !value.isEmpty,
      value == value.trimmingCharacters(in: .whitespacesAndNewlines),
      let components = URLComponents(string: value),
      let scheme = components.scheme?.lowercased(),
      let host = components.host?.lowercased(),
      !host.isEmpty,
      components.user == nil,
      components.password == nil,
      components.path.isEmpty,
      components.query == nil,
      components.fragment == nil,
      let resolvedURL = components.url
    else {
      throw ValidationError.invalid
    }

    switch scheme {
    case "https":
      break
    case "http" where Self.loopbackHosts.contains(host):
      break
    default:
      throw ValidationError.invalid
    }

    url = resolvedURL
  }

  private static let loopbackHosts: Set<String> = ["127.0.0.1", "localhost", "::1", "[::1]"]
}

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

  @Published private(set) var baseURL: APIBaseURL
  @Published private(set) var draftBaseURL: String
  @Published private(set) var validationMessage: String?

  private let storage: any APISettingsPersisting

  init(storage: any APISettingsPersisting = UserDefaultsAPISettingsStorage()) {
    self.storage = storage

    if let stored = storage.string(forKey: Self.storageKey),
      let validated = try? APIBaseURL(validating: stored)
    {
      baseURL = validated
      draftBaseURL = stored
    } else {
      baseURL = .default
      draftBaseURL = APIBaseURL.default.url.absoluteString
      storage.set(draftBaseURL, forKey: Self.storageKey)
    }
  }

  func updateBaseURL(_ value: String) {
    draftBaseURL = value
    do {
      let validated = try APIBaseURL(validating: value)
      baseURL = validated
      validationMessage = nil
      storage.set(validated.url.absoluteString, forKey: Self.storageKey)
    } catch {
      validationMessage = "Kasuta HTTPS-aadressi. HTTP on lubatud ainult kohalikule teenusele."
    }
  }

  func currentBaseURL() -> URL {
    baseURL.url
  }
}
