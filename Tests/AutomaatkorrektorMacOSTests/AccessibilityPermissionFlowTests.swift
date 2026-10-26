import AutomaatkorrektorCore
import Testing

@testable import AutomaatkorrektorMacOS

@MainActor
@Suite("Accessibility permission recovery")
struct AccessibilityPermissionFlowTests {
  @Test("denied and removed permission share the approved blocked presentation")
  func deniedAndRemovedPermission() async {
    let permission = PermissionControllerStub(isGranted: false)
    let reader = PermissionCountingSelectionReader()
    let detector = PermissionCountingDetector()
    let model = makePermissionModel(
      permission: permission,
      reader: reader,
      detector: detector
    )

    await model.refreshAccessibilityPermission()

    #expect(model.state == .blocked(.accessibilityPermissionRequired))
    #expect(model.visiblePresentation.title == "Accessibility-luba puudub")
    #expect(await reader.readCount == 0)
    #expect(await detector.requestCount == 0)

    permission.isGranted = true
    await model.refreshAccessibilityPermission()
    #expect(model.visiblePresentation.title == "Programm on tööks valmis")
    #expect(model.visiblePresentation.detail == "Vali tekst ja käivita eesti keele kontroll.")
    #expect(model.visiblePresentation.symbol == "checkmark.circle.fill")
    #expect(model.visiblePresentation.tone == .success)

    permission.isGranted = false
    await model.refreshAccessibilityPermission()

    #expect(model.state == .blocked(.accessibilityPermissionRequired))
    #expect(model.visiblePresentation.title == "Accessibility-luba puudub")
    #expect(await reader.readCount == 0)
    #expect(await detector.requestCount == 0)
  }

  @Test("a language check rechecks permission before selection capture")
  func permissionBeforeSelectionCapture() async {
    let permission = PermissionControllerStub(isGranted: false)
    let reader = PermissionCountingSelectionReader()
    let detector = PermissionCountingDetector()
    let model = makePermissionModel(
      permission: permission,
      reader: reader,
      detector: detector
    )

    await model.check()

    #expect(permission.checkCount == 1)
    #expect(model.state == .blocked(.accessibilityPermissionRequired))
    #expect(await reader.readCount == 0)
    #expect(await detector.requestCount == 0)
  }

  @Test("permission loss cancels active work without retrying")
  func permissionLossCancelsActiveWork() async {
    let permission = PermissionControllerStub(isGranted: true)
    let reader = PermissionCountingSelectionReader()
    let detector = SuspendedPermissionDetector()
    let model = makePermissionModel(
      permission: permission,
      reader: reader,
      detector: detector
    )

    let check = Task { await model.check() }
    await detector.waitUntilRequestStarts()
    permission.isGranted = false

    await model.refreshAccessibilityPermission()
    await check.value

    #expect(model.state == .blocked(.accessibilityPermissionRequired))
    #expect(await reader.readCount == 1)
    #expect(await detector.requestCount == 1)
    #expect(await detector.wasCancelled)
  }

  @Test("opening Accessibility settings shows guidance without reading or sending text")
  func openSettingsIsMetadataOnly() async {
    let permission = PermissionControllerStub(isGranted: false)
    let reader = PermissionCountingSelectionReader()
    let detector = PermissionCountingDetector()
    let model = makePermissionModel(
      permission: permission,
      reader: reader,
      detector: detector
    )

    model.openAccessibilitySettings()

    #expect(permission.openSettingsCount == 1)
    #expect(model.showsAccessibilityInstructions)
    #expect(await reader.readCount == 0)
    #expect(await detector.requestCount == 0)
  }
}

@MainActor
private func makePermissionModel(
  permission: any AccessibilityPermissionControlling,
  reader: any SelectionReading,
  detector: any LanguageDetecting
) -> LanguageCheckViewModel {
  LanguageCheckViewModel(
    useCase: LanguageCheckUseCase(
      selectionReader: reader,
      languageDetector: detector
    ),
    accessibilityPermission: permission
  )
}

@MainActor
private final class PermissionControllerStub: AccessibilityPermissionControlling {
  var isGranted: Bool
  private(set) var checkCount = 0
  private(set) var openSettingsCount = 0

  init(isGranted: Bool) {
    self.isGranted = isGranted
  }

  func checkPermission() -> Bool {
    checkCount += 1
    return isGranted
  }

  func openSettings() {
    openSettingsCount += 1
  }
}

private actor PermissionCountingSelectionReader: SelectionReading {
  private(set) var readCount = 0

  func readSelectedText() async throws -> SelectedText {
    readCount += 1
    return SelectedText("SÜNTEETILINE-TEKST")
  }
}

private actor PermissionCountingDetector: LanguageDetecting {
  private(set) var requestCount = 0

  func detectLanguage(
    of selectedText: SelectedText,
    configuration: LanguageCheckConfiguration
  ) async throws -> LanguageVerdict {
    requestCount += 1
    return .estonian
  }
}

private actor SuspendedPermissionDetector: LanguageDetecting {
  private(set) var requestCount = 0
  private(set) var wasCancelled = false

  func detectLanguage(
    of selectedText: SelectedText,
    configuration: LanguageCheckConfiguration
  ) async throws -> LanguageVerdict {
    requestCount += 1
    do {
      try await Task.sleep(for: .seconds(60))
      return .estonian
    } catch is CancellationError {
      wasCancelled = true
      throw CancellationError()
    }
  }

  func waitUntilRequestStarts() async {
    while requestCount == 0 {
      await Task.yield()
    }
  }
}
