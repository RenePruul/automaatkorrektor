import AutomaatkorrektorCore
import Testing

@testable import AutomaatkorrektorMacOS

@MainActor
@Suite("Menu bar application lifecycle")
struct ApplicationLifecycleControllerTests {
  @Test("launch is quiet and reopening reveals the existing menu")
  func quietLaunchAndReopen() async {
    let reader = CountingSelectionReader()
    let detector = CountingDetector()
    let terminator = TerminationSpy()
    let model = LanguageCheckViewModel(
      useCase: LanguageCheckUseCase(
        selectionReader: reader,
        languageDetector: detector
      ),
      accessibilityPermission: LifecyclePermissionController()
    )
    let lifecycle = ApplicationLifecycleController(
      model: model,
      terminator: terminator
    )

    lifecycle.launch()

    #expect(!lifecycle.isPopoverPresented)
    #expect(await reader.readCount == 0)
    #expect(await detector.requestCount == 0)

    lifecycle.reopen()

    #expect(lifecycle.isPopoverPresented)
    #expect(await reader.readCount == 0)
    #expect(await detector.requestCount == 0)
  }

  @Test("closing the popover keeps the utility running and quit terminates it")
  func dismissAndQuit() async {
    let terminator = TerminationSpy()
    let model = LanguageCheckViewModel(
      useCase: LanguageCheckUseCase(
        selectionReader: CountingSelectionReader(),
        languageDetector: CountingDetector()
      ),
      accessibilityPermission: LifecyclePermissionController()
    )
    let lifecycle = ApplicationLifecycleController(
      model: model,
      terminator: terminator
    )
    lifecycle.reopen()

    await lifecycle.dismissPopover()

    #expect(!lifecycle.isPopoverPresented)
    #expect(model.state == .waiting)
    #expect(terminator.terminationCount == 0)

    await lifecycle.quit()

    #expect(terminator.terminationCount == 1)
  }

  @Test("popover opening and application activation refresh permission without reading text")
  func lifecycleRefreshesPermission() async {
    let permission = LifecyclePermissionController()
    let reader = CountingSelectionReader()
    let detector = CountingDetector()
    let model = LanguageCheckViewModel(
      useCase: LanguageCheckUseCase(
        selectionReader: reader,
        languageDetector: detector
      ),
      accessibilityPermission: permission
    )
    let lifecycle = ApplicationLifecycleController(
      model: model,
      terminator: TerminationSpy()
    )

    await lifecycle.popoverDidOpen()
    await lifecycle.applicationDidBecomeActive()

    #expect(permission.checkCount == 2)
    #expect(await reader.readCount == 0)
    #expect(await detector.requestCount == 0)
  }
}

private actor CountingSelectionReader: SelectionReading {
  private(set) var readCount = 0

  func readSelectedText() async throws -> SelectedText {
    readCount += 1
    return SelectedText("Tere")
  }
}

private actor CountingDetector: LanguageDetecting {
  private(set) var requestCount = 0

  func detectLanguage(
    of selectedText: SelectedText,
    configuration: LanguageCheckConfiguration
  ) async throws -> LanguageVerdict {
    requestCount += 1
    return .estonian
  }
}

@MainActor
private final class TerminationSpy: ApplicationTerminating {
  private(set) var terminationCount = 0

  func terminate() {
    terminationCount += 1
  }
}

@MainActor
private final class LifecyclePermissionController: AccessibilityPermissionControlling {
  private(set) var checkCount = 0

  func checkPermission() -> Bool {
    checkCount += 1
    return true
  }

  func openSettings() {}
}
