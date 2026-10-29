import Foundation

public struct SelectedText: Sendable, Equatable {
  public let value: String

  public init(_ value: String) {
    self.value = value
  }
}

public struct LanguageServiceOrigin: Sendable, Equatable, Hashable {
  public let scheme: String
  public let host: String
  public let port: Int

  fileprivate init(scheme: String, host: String, port: Int) {
    self.scheme = scheme
    self.host = host
    self.port = port
  }

  public var displayValue: String {
    let formattedHost = host.contains(":") ? "[\(host)]" : host
    if (scheme == "https" && port == 443) || (scheme == "http" && port == 80) {
      return "\(scheme)://\(formattedHost)"
    }
    return "\(scheme)://\(formattedHost):\(port)"
  }
}

/// A validated language-service endpoint used by both consent policy and transport.
///
/// Constructing this value validates the complete URL, normalizes its origin,
/// and classifies literal loopback destinations without DNS resolution.
public struct LanguageServiceEndpoint: Sendable, Equatable {
  public enum ValidationError: Error, Sendable, Equatable {
    case invalid
  }

  public static let `default` = try! LanguageServiceEndpoint(
    validating: "http://127.0.0.1:8000"
  )

  public let transportBaseURL: String
  public let languageCheckConsentOrigin: LanguageServiceOrigin?

  public init(validating value: String) throws {
    guard !value.isEmpty,
      value == value.trimmingCharacters(in: .whitespacesAndNewlines),
      let parsed = URLComponents(string: value),
      let scheme = parsed.scheme?.lowercased(),
      let parsedHost = parsed.host?.lowercased(),
      !parsedHost.isEmpty,
      parsed.user == nil,
      parsed.password == nil,
      parsed.path.isEmpty,
      parsed.query == nil,
      parsed.fragment == nil,
      let port = Self.validatedPort(in: value, components: parsed),
      parsed.url != nil
    else {
      throw ValidationError.invalid
    }

    let host = Self.canonicalHost(parsedHost)
    if Self.looksLikeIPv4Literal(host), Self.ipv4Octets(host) == nil {
      throw ValidationError.invalid
    }
    let isLoopback = Self.isLiteralLoopback(host)
    guard scheme == "https" || (scheme == "http" && isLoopback) else {
      throw ValidationError.invalid
    }

    var normalized = parsed
    normalized.scheme = scheme
    normalized.host = parsedHost
    guard let normalizedURL = normalized.url else {
      throw ValidationError.invalid
    }

    transportBaseURL = normalizedURL.absoluteString
    languageCheckConsentOrigin =
      isLoopback
      ? nil
      : LanguageServiceOrigin(scheme: scheme, host: host, port: port)
  }

  private static func validatedPort(
    in value: String,
    components: URLComponents
  ) -> Int? {
    if let explicitPort = components.port {
      return (1...65_535).contains(explicitPort) ? explicitPort : nil
    }

    // URLComponents can return a nil port for some malformed authorities.
    // If the authority visibly contains a port delimiter, fail closed.
    guard let schemeRange = value.range(of: "://") else { return nil }
    let authority = value[schemeRange.upperBound...].prefix { $0 != "/" && $0 != "?" && $0 != "#" }
    if authority.hasPrefix("[") {
      guard let closingBracket = authority.firstIndex(of: "]") else { return nil }
      let suffix = authority[authority.index(after: closingBracket)...]
      guard suffix.isEmpty else { return nil }
    } else if authority.contains(":") {
      return nil
    }

    return components.scheme?.lowercased() == "https" ? 443 : 80
  }

  private static func isLiteralLoopback(_ host: String) -> Bool {
    if host == "localhost" || host == "::1" { return true }
    guard let octets = ipv4Octets(host) else { return false }
    return octets[0] == "127"
  }

  private static func looksLikeIPv4Literal(_ host: String) -> Bool {
    host.contains(".") && host.allSatisfy { $0.isNumber || $0 == "." }
  }

  private static func ipv4Octets(_ host: String) -> [Substring]? {
    let octets = host.split(separator: ".", omittingEmptySubsequences: false)
    guard octets.count == 4,
      octets.allSatisfy({ octet in
        !octet.isEmpty && octet.allSatisfy(\.isNumber)
          && Int(octet).map { (0...255).contains($0) } == true
      })
    else {
      return nil
    }
    return octets
  }

  private static func canonicalHost(_ host: String) -> String {
    guard host.hasPrefix("["), host.hasSuffix("]") else { return host }
    return String(host.dropFirst().dropLast())
  }
}

/// An immutable, already-validated snapshot for one explicit check.
///
/// Platform adapters own URL validation. Core deliberately keeps the value as
/// a string so it stays independent of Foundation networking types.
public struct LanguageCheckConfiguration: Sendable, Equatable {
  public let endpoint: LanguageServiceEndpoint

  public init(endpoint: LanguageServiceEndpoint) {
    self.endpoint = endpoint
  }
}

public enum LanguageVerdict: Sendable, Equatable {
  case estonian
  case notEstonian
  case uncertain
}

public enum LanguageCheckFailure: Error, Sendable, Equatable {
  case invalidInput
  case selectionTooLarge
  case timeout
  case unavailableService
  case insecureConnection
  case rateLimited
  case incompatibleService
  case invalidResponse
  case serverFailure
  case otherHTTPFailure
}

public enum LanguageCheckBlock: Error, Sendable, Equatable {
  case accessibilityPermissionRequired
  case unsupportedTextField
  case noSelection
  case languageCheckConsentRequired(LanguageServiceOrigin)
}

public protocol SelectionReading: Sendable {
  func readSelectedText() async throws -> SelectedText
}

public protocol LanguageCheckConfiguring: Sendable {
  func currentConfiguration() async -> LanguageCheckConfiguration
}

public protocol LanguageDetecting: Sendable {
  func detectLanguage(
    of selectedText: SelectedText,
    configuration: LanguageCheckConfiguration
  ) async throws -> LanguageVerdict
}

public protocol LanguageCheckConsenting: Sendable {
  func hasConsent(for origin: LanguageServiceOrigin) async -> Bool
}

private struct DenyLanguageCheckConsent: LanguageCheckConsenting {
  func hasConsent(for origin: LanguageServiceOrigin) -> Bool { false }
}

public actor LanguageCheckUseCase {
  private let configurationProvider: any LanguageCheckConfiguring
  private let selectionReader: any SelectionReading
  private let languageDetector: any LanguageDetecting
  private let languageCheckConsent: any LanguageCheckConsenting
  private var generation = 0
  private var activeCheck: Task<LanguageVerdict, any Error>?

  public init(
    configurationProvider: any LanguageCheckConfiguring,
    selectionReader: any SelectionReading,
    languageDetector: any LanguageDetecting
  ) {
    self.init(
      configurationProvider: configurationProvider,
      selectionReader: selectionReader,
      languageDetector: languageDetector,
      languageCheckConsent: DenyLanguageCheckConsent()
    )
  }

  public init(
    configurationProvider: any LanguageCheckConfiguring,
    selectionReader: any SelectionReading,
    languageDetector: any LanguageDetecting,
    languageCheckConsent: any LanguageCheckConsenting
  ) {
    self.configurationProvider = configurationProvider
    self.selectionReader = selectionReader
    self.languageDetector = languageDetector
    self.languageCheckConsent = languageCheckConsent
  }

  public func check() async throws -> LanguageVerdict {
    activeCheck?.cancel()
    generation += 1
    let checkGeneration = generation
    let configurationProvider = self.configurationProvider
    let selectionReader = self.selectionReader
    let languageDetector = self.languageDetector
    let languageCheckConsent = self.languageCheckConsent

    let task = Task {
      try Task.checkCancellation()
      let configuration = await configurationProvider.currentConfiguration()
      try Task.checkCancellation()
      if let origin = configuration.endpoint.languageCheckConsentOrigin,
        !(await languageCheckConsent.hasConsent(for: origin))
      {
        throw LanguageCheckBlock.languageCheckConsentRequired(origin)
      }
      try Task.checkCancellation()
      let selectedText = try await selectionReader.readSelectedText()
      try Task.checkCancellation()
      return try await languageDetector.detectLanguage(
        of: selectedText,
        configuration: configuration
      )
    }
    activeCheck = task

    do {
      let verdict = try await withTaskCancellationHandler {
        try await task.value
      } onCancel: {
        task.cancel()
      }
      guard checkGeneration == generation else {
        throw CancellationError()
      }
      activeCheck = nil
      return verdict
    } catch {
      if checkGeneration == generation {
        activeCheck = nil
      }
      throw error
    }
  }

  public func cancel() {
    generation += 1
    activeCheck?.cancel()
    activeCheck = nil
  }
}
