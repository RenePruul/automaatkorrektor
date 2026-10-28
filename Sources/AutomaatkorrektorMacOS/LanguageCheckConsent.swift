import AutomaatkorrektorCore
import Combine
import Foundation

protocol LanguageCheckConsentPersisting: Sendable {
  func string(forKey key: String) -> String?
  func set(_ value: String, forKey key: String)
  func removeValue(forKey key: String)
}

enum LanguageCheckConsentStatus: Sendable, Equatable {
  case local
  case origin(LanguageServiceOrigin, hasConsent: Bool)
}

private final class UserDefaultsLanguageCheckConsentPersistence:
  LanguageCheckConsentPersisting, @unchecked Sendable
{
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

  func removeValue(forKey key: String) {
    defaults.removeObject(forKey: key)
  }
}

private struct LanguageCheckConsentRecord: Codable, Equatable {
  static let currentVersion = 1

  let version: Int
  let origin: Origin

  struct Origin: Codable, Equatable {
    let scheme: String
    let host: String
    let port: Int
  }
}

private struct LanguageCheckConsentRecordCodec {
  private let encoder: JSONEncoder = {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    return encoder
  }()
  private let decoder = JSONDecoder()

  func encode(_ origin: LanguageServiceOrigin) -> String? {
    let record = LanguageCheckConsentRecord(
      version: LanguageCheckConsentRecord.currentVersion,
      origin: .init(scheme: origin.scheme, host: origin.host, port: origin.port)
    )
    guard let data = try? encoder.encode(record) else { return nil }
    return String(data: data, encoding: .utf8)
  }

  func decode(_ value: String) -> LanguageServiceOrigin? {
    guard let data = value.data(using: .utf8),
      let record = try? decoder.decode(LanguageCheckConsentRecord.self, from: data),
      record.version == LanguageCheckConsentRecord.currentVersion,
      (1...65_535).contains(record.origin.port),
      let endpoint = try? LanguageServiceEndpoint(
        validating: Self.displayValue(for: record.origin)
      ),
      let origin = endpoint.languageCheckConsentOrigin,
      origin.scheme == record.origin.scheme,
      origin.host == record.origin.host,
      origin.port == record.origin.port,
      encode(origin) == value
    else {
      return nil
    }
    return origin
  }

  private static func displayValue(for origin: LanguageCheckConsentRecord.Origin) -> String {
    let host = origin.host.contains(":") ? "[\(origin.host)]" : origin.host
    return "\(origin.scheme)://\(host):\(origin.port)"
  }
}

@MainActor
final class LanguageCheckConsentStore: ObservableObject, LanguageCheckConsenting {
  static let storageKey = "languageCheckConsentRecord"

  @Published private(set) var consentedOrigin: LanguageServiceOrigin?

  private let persistence: any LanguageCheckConsentPersisting
  private let codec = LanguageCheckConsentRecordCodec()

  init(
    persistence: any LanguageCheckConsentPersisting =
      UserDefaultsLanguageCheckConsentPersistence()
  ) {
    self.persistence = persistence

    if let stored = persistence.string(forKey: Self.storageKey),
      let origin = codec.decode(stored)
    {
      consentedOrigin = origin
    } else {
      consentedOrigin = nil
      persistence.removeValue(forKey: Self.storageKey)
    }
  }

  func hasConsent(for origin: LanguageServiceOrigin) -> Bool {
    consentedOrigin == origin
  }

  func grantConsent(for origin: LanguageServiceOrigin) {
    guard let encoded = codec.encode(origin) else {
      revokeConsent()
      return
    }
    consentedOrigin = origin
    persistence.set(encoded, forKey: Self.storageKey)
  }

  func revokeConsent() {
    consentedOrigin = nil
    persistence.removeValue(forKey: Self.storageKey)
  }

  func status(for endpoint: LanguageServiceEndpoint) -> LanguageCheckConsentStatus {
    guard let origin = endpoint.languageCheckConsentOrigin else { return .local }
    return .origin(origin, hasConsent: hasConsent(for: origin))
  }
}
