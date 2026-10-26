import Testing

@testable import AutomaatkorrektorCore

@Suite("Language check")
struct LanguageCheckUseCaseTests {
  @Test("an explicit language check returns a verdict without exposing selected text")
  func completeLanguageCheck() async throws {
    let selection = SelectionReaderStub(text: "PRIVAATSUS-KANAARILIND")
    let detector = LanguageDetectorStub(verdict: .estonian)
    let useCase = LanguageCheckUseCase(
      configurationProvider: fixedConfiguration,
      selectionReader: selection,
      languageDetector: detector
    )

    let verdict = try await useCase.check()

    #expect(verdict == .estonian)
    #expect(await selection.readCount == 1)
    #expect(await detector.receivedTextCount == 1)
    #expect(await detector.received("PRIVAATSUS-KANAARILIND"))
    #expect(!String(reflecting: verdict).contains("PRIVAATSUS-KANAARILIND"))
  }

  @Test("only the latest overlapping language check can return a verdict")
  func latestCheckWins() async throws {
    let detector = ControllableDetector()
    let useCase = LanguageCheckUseCase(
      configurationProvider: fixedConfiguration,
      selectionReader: SelectionReaderStub(text: "Tere"),
      languageDetector: detector
    )

    let obsoleteCheck = Task { try await useCase.check() }
    await detector.waitUntilFirstCheckStarts()
    let latestVerdict = try await useCase.check()
    await detector.finishObsoleteCheck()

    #expect(latestVerdict == .estonian)
    do {
      _ = try await obsoleteCheck.value
      Issue.record("The obsolete check returned a verdict")
    } catch is CancellationError {
      // Expected: a late obsolete result is discarded.
    } catch {
      Issue.record("Unexpected obsolete-check error: \(error)")
    }
  }

  @Test("cancelling a language check discards its late result")
  func cancellationDiscardsLateResult() async {
    let detector = ControllableDetector()
    let useCase = LanguageCheckUseCase(
      configurationProvider: fixedConfiguration,
      selectionReader: SelectionReaderStub(text: "Tere"),
      languageDetector: detector
    )

    let check = Task { try await useCase.check() }
    await detector.waitUntilFirstCheckStarts()
    await useCase.cancel()
    await detector.finishObsoleteCheck()

    do {
      _ = try await check.value
      Issue.record("The cancelled check returned a verdict")
    } catch is CancellationError {
      // Expected: cancellation is silent at presentation level.
    } catch {
      Issue.record("Unexpected cancellation error: \(error)")
    }
  }

  @Test("each check keeps the validated configuration captured before selection")
  func configurationSnapshotIsImmutablePerCheck() async throws {
    let original = LanguageCheckConfiguration(
      validatedServiceBaseURL: "https://original.example.test"
    )
    let replacement = LanguageCheckConfiguration(
      validatedServiceBaseURL: "https://replacement.example.test"
    )
    let configuration = MutableConfigurationProvider(original)
    let selection = GatedSelectionReader(text: "Tere")
    let detector = ConfigurationRecordingDetector()
    let useCase = LanguageCheckUseCase(
      configurationProvider: configuration,
      selectionReader: selection,
      languageDetector: detector
    )

    let firstCheck = Task { try await useCase.check() }
    await selection.waitUntilReadStarts()
    await configuration.replace(with: replacement)
    await selection.release()
    _ = try await firstCheck.value

    _ = try await useCase.check()

    #expect(await detector.configurations == [original, replacement])
  }
}

private let fixedConfiguration = FixedConfigurationProvider()

private struct FixedConfigurationProvider: LanguageCheckConfiguring {
  func currentConfiguration() -> LanguageCheckConfiguration {
    LanguageCheckConfiguration(validatedServiceBaseURL: "https://language.example.test")
  }
}

private actor MutableConfigurationProvider: LanguageCheckConfiguring {
  private var configuration: LanguageCheckConfiguration

  init(_ configuration: LanguageCheckConfiguration) {
    self.configuration = configuration
  }

  func currentConfiguration() -> LanguageCheckConfiguration {
    configuration
  }

  func replace(with configuration: LanguageCheckConfiguration) {
    self.configuration = configuration
  }
}

private actor GatedSelectionReader: SelectionReading {
  private let text: String
  private var started = false
  private var continuation: CheckedContinuation<Void, Never>?

  init(text: String) {
    self.text = text
  }

  func readSelectedText() async throws -> SelectedText {
    guard !started else { return SelectedText(text) }
    started = true
    await withCheckedContinuation { continuation = $0 }
    return SelectedText(text)
  }

  func waitUntilReadStarts() async {
    while !started { await Task.yield() }
  }

  func release() {
    continuation?.resume()
    continuation = nil
  }
}

private actor ConfigurationRecordingDetector: LanguageDetecting {
  private(set) var configurations: [LanguageCheckConfiguration] = []

  func detectLanguage(
    of selectedText: SelectedText,
    configuration: LanguageCheckConfiguration
  ) async throws -> LanguageVerdict {
    configurations.append(configuration)
    return .estonian
  }
}

private actor SelectionReaderStub: SelectionReading {
  private let text: String
  private(set) var readCount = 0

  init(text: String) {
    self.text = text
  }

  func readSelectedText() async throws -> SelectedText {
    readCount += 1
    return SelectedText(text)
  }
}

private actor LanguageDetectorStub: LanguageDetecting {
  private let verdict: LanguageVerdict
  private var receivedTexts: [String] = []

  init(verdict: LanguageVerdict) {
    self.verdict = verdict
  }

  var receivedTextCount: Int { receivedTexts.count }

  func received(_ text: String) -> Bool {
    receivedTexts.contains(text)
  }

  func detectLanguage(
    of selectedText: SelectedText,
    configuration: LanguageCheckConfiguration
  ) async throws -> LanguageVerdict {
    receivedTexts.append(selectedText.value)
    return verdict
  }
}

private actor ControllableDetector: LanguageDetecting {
  private var callCount = 0
  private var obsoleteContinuation: CheckedContinuation<Void, Never>?

  func detectLanguage(
    of selectedText: SelectedText,
    configuration: LanguageCheckConfiguration
  ) async throws -> LanguageVerdict {
    callCount += 1
    guard callCount == 1 else { return .estonian }

    await withCheckedContinuation { continuation in
      obsoleteContinuation = continuation
    }
    return .notEstonian
  }

  func waitUntilFirstCheckStarts() async {
    while callCount == 0 {
      await Task.yield()
    }
  }

  func finishObsoleteCheck() {
    obsoleteContinuation?.resume()
    obsoleteContinuation = nil
  }
}
