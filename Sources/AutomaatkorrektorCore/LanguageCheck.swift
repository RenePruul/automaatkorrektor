public struct SelectedText: Sendable, Equatable {
  public let value: String

  public init(_ value: String) {
    self.value = value
  }
}

/// An immutable, already-validated snapshot for one explicit check.
///
/// Platform adapters own URL validation. Core deliberately keeps the value as
/// a string so it stays independent of Foundation networking types.
public struct LanguageCheckConfiguration: Sendable, Equatable {
  public let serviceBaseURL: String

  public init(validatedServiceBaseURL: String) {
    precondition(!validatedServiceBaseURL.isEmpty)
    self.serviceBaseURL = validatedServiceBaseURL
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

public actor LanguageCheckUseCase {
  private let configurationProvider: any LanguageCheckConfiguring
  private let selectionReader: any SelectionReading
  private let languageDetector: any LanguageDetecting
  private var generation = 0
  private var activeCheck: Task<LanguageVerdict, any Error>?

  public init(
    configurationProvider: any LanguageCheckConfiguring,
    selectionReader: any SelectionReading,
    languageDetector: any LanguageDetecting
  ) {
    self.configurationProvider = configurationProvider
    self.selectionReader = selectionReader
    self.languageDetector = languageDetector
  }

  public func check() async throws -> LanguageVerdict {
    activeCheck?.cancel()
    generation += 1
    let checkGeneration = generation
    let configurationProvider = self.configurationProvider
    let selectionReader = self.selectionReader
    let languageDetector = self.languageDetector

    let task = Task {
      try Task.checkCancellation()
      let configuration = await configurationProvider.currentConfiguration()
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
