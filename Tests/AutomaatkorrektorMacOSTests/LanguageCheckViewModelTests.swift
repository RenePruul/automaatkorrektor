import AutomaatkorrektorCore
import Testing

@testable import AutomaatkorrektorMacOS

@MainActor
@Suite("Language check presentation")
struct LanguageCheckViewModelTests {
  @Test("the presentation model exposes every approved state")
  func exhaustiveStates() async {
    let waiting = makeViewModel()
    #expect(waiting.state == .waiting)

    let checking = makeViewModel(
      reader: SuspendedSelectionReader()
    )
    let checkingTask = Task { await checking.check() }
    await Task.yield()
    #expect(checking.state == .checking)
    await checking.dismiss()
    await checkingTask.value

    let verdict = makeViewModel(
      detector: DetectorStub(result: .success(.notEstonian))
    )
    await verdict.check()
    #expect(verdict.state == .verdict(.notEstonian))

    let blocked = makeViewModel(
      reader: SelectionReaderStub(
        result: .failure(LanguageCheckBlock.accessibilityPermissionRequired))
    )
    await blocked.check()
    #expect(blocked.state == .blocked(.accessibilityPermissionRequired))

    let failed = makeViewModel(
      detector: DetectorStub(result: .failure(LanguageCheckFailure.unavailableService))
    )
    await failed.check()
    #expect(failed.state == .failed(.unavailableService))
  }

  @Test("a complete check publishes only its language verdict")
  func completeCheck() async {
    let canary = "SALAJANE-VALITUD-TEKST"
    let model = makeViewModel(
      reader: SelectionReaderStub(result: .success(SelectedText(canary))),
      detector: DetectorStub(result: .success(.estonian))
    )

    await model.check()

    #expect(model.state == .verdict(.estonian))
    #expect(!String(reflecting: model.state).contains(canary))
  }

  @Test("every state has stable user-facing Estonian copy")
  func visibleStateCopy() {
    let expectedTitles: [(LanguageCheckPresentationState, String)] = [
      (.waiting, "Ootan valikut"),
      (.checking, "Kontrollin keelt"),
      (.verdict(.estonian), "Eesti keel"),
      (.verdict(.notEstonian), "Muu keel"),
      (.verdict(.uncertain), "Ebakindel"),
      (.blocked(.accessibilityPermissionRequired), "Accessibility-luba puudub"),
      (.blocked(.unsupportedTextField), "Tekstivälja ei toetata"),
      (.blocked(.noSelection), "Teksti pole valitud"),
      (.failed(.unavailableService), "Kontroll ebaõnnestus"),
    ]

    for (state, expectedTitle) in expectedTitles {
      #expect(state.presentation.title == expectedTitle)
      #expect(!state.presentation.detail.isEmpty)
      #expect(!state.presentation.symbol.isEmpty)
    }
  }

  @Test("unavailable service offers one explicit fresh retry")
  func unavailableServiceRetry() async {
    let reader = CountingSelectionReader()
    let detector = SequencedDetector(results: [
      .failure(LanguageCheckFailure.unavailableService),
      .success(.estonian),
    ])
    let model = makeViewModel(reader: reader, detector: detector)

    await model.check()
    #expect(model.state == .failed(.unavailableService))
    #expect(model.showsRetryAction)
    #expect(await reader.readCount == 1)
    #expect(await detector.callCount == 1)

    await model.retryUnavailableService()

    #expect(model.state == .verdict(.estonian))
    #expect(!model.showsRetryAction)
    #expect(await reader.readCount == 2)
    #expect(await detector.callCount == 2)
  }

  @Test("retry is unavailable for unrelated states and performs no work")
  func retryIsContextual() async {
    let reader = CountingSelectionReader()
    let detector = SequencedDetector(results: [
      .failure(LanguageCheckFailure.timeout)
    ])
    let model = makeViewModel(reader: reader, detector: detector)

    #expect(!model.showsRetryAction)
    await model.retryUnavailableService()
    #expect(await reader.readCount == 0)

    await model.check()
    #expect(model.state == .failed(.timeout))
    #expect(!model.showsRetryAction)
    await model.retryUnavailableService()
    #expect(await reader.readCount == 1)
    #expect(await detector.callCount == 1)
  }
}

@MainActor
private func makeViewModel(
  reader: any SelectionReading = SelectionReaderStub(result: .success(SelectedText("Tere"))),
  detector: any LanguageDetecting = DetectorStub(result: .success(.estonian))
) -> LanguageCheckViewModel {
  LanguageCheckViewModel(
    useCase: LanguageCheckUseCase(
      selectionReader: reader,
      languageDetector: detector
    ),
    accessibilityPermission: ViewModelGrantedPermissionController()
  )
}

@MainActor
private final class ViewModelGrantedPermissionController: AccessibilityPermissionControlling {
  func checkPermission() -> Bool { true }
  func openSettings() {}
}

private struct SelectionReaderStub: SelectionReading {
  let result: Result<SelectedText, any Error>

  func readSelectedText() async throws -> SelectedText {
    try result.get()
  }
}

private struct DetectorStub: LanguageDetecting {
  let result: Result<LanguageVerdict, any Error>

  func detectLanguage(
    of selectedText: SelectedText,
    configuration: LanguageCheckConfiguration
  ) async throws -> LanguageVerdict {
    try result.get()
  }
}

private actor SuspendedSelectionReader: SelectionReading {
  func readSelectedText() async throws -> SelectedText {
    try await Task.sleep(for: .seconds(60))
    return SelectedText("Tere")
  }
}

private actor CountingSelectionReader: SelectionReading {
  private(set) var readCount = 0

  func readSelectedText() async throws -> SelectedText {
    readCount += 1
    return SelectedText("Tere")
  }
}

private actor SequencedDetector: LanguageDetecting {
  private var results: [Result<LanguageVerdict, any Error>]
  private(set) var callCount = 0

  init(results: [Result<LanguageVerdict, any Error>]) {
    self.results = results
  }

  func detectLanguage(
    of selectedText: SelectedText,
    configuration: LanguageCheckConfiguration
  ) async throws -> LanguageVerdict {
    let result = results[callCount]
    callCount += 1
    return try result.get()
  }
}
