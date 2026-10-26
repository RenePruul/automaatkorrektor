import AutomaatkorrektorCore
import Testing

@testable import AutomaatkorrektorMacOS

@MainActor
@Suite("Global shortcut")
struct GlobalShortcutControllerTests {
  @Test("startup registers option-command-E on key up and one release invokes once")
  func defaultShortcutInvokesOnKeyUp() {
    let backend = ShortcutBackendSpy()
    let controller = GlobalShortcutController(backend: backend)
    var invocationCount = 0

    controller.start { invocationCount += 1 }

    #expect(backend.registeredShortcut == .default)
    #expect(backend.registeredPhase == .keyUp)
    backend.sendKeyDown()
    backend.sendKeyUp()
    #expect(invocationCount == 1)
  }

  @Test("replacement, clearing, and shutdown leave only the intended registration")
  func lifecycle() {
    let backend = ShortcutBackendSpy()
    let controller = GlobalShortcutController(backend: backend)
    controller.start {}

    let replacement = GlobalShortcut(key: "K", modifiers: [.command, .shift])
    #expect(controller.replace(with: replacement))
    #expect(backend.registeredShortcut == replacement)
    #expect(controller.shortcut == replacement)

    controller.clear()
    #expect(backend.registeredShortcut == nil)
    #expect(controller.shortcut == nil)

    controller.stop()
    #expect(backend.stopCount == 1)
  }

  @Test("known conflict or registration failure keeps the prior working shortcut")
  func failedReplacement() {
    let backend = ShortcutBackendSpy()
    let controller = GlobalShortcutController(backend: backend)
    controller.start {}

    let knownConflict = GlobalShortcut(key: "Space", modifiers: [.command])
    backend.rejectedShortcuts = [knownConflict]
    #expect(!controller.replace(with: knownConflict))
    #expect(controller.shortcut == .default)
    #expect(backend.registeredShortcut == .default)
    #expect(controller.registrationMessage == GlobalShortcutController.failureMessage)

    let unavailable = GlobalShortcut(key: "U", modifiers: [.command, .option])
    backend.failingShortcuts = [unavailable]
    #expect(!controller.replace(with: unavailable))
    #expect(controller.shortcut == .default)
    #expect(backend.registeredShortcut == .default)
  }

  @Test("a cleared shortcut remains cleared when the controller starts again")
  func intentionalClearingPersists() {
    let backend = ShortcutBackendSpy(storedShortcut: .default)
    let first = GlobalShortcutController(backend: backend)
    first.start {}
    first.clear()
    first.stop()

    let second = GlobalShortcutController(backend: backend)
    second.start {}

    #expect(second.shortcut == nil)
    #expect(backend.registeredShortcut == nil)
  }

  @Test("shortcut activation is independent of Accessibility permission state")
  func permissionIndependent() async {
    let backend = ShortcutBackendSpy()
    let permission = DeniedPermissionController()
    let model = LanguageCheckViewModel(
      useCase: LanguageCheckUseCase(
        selectionReader: ShortcutSelectionReader(),
        languageDetector: ShortcutDetector()
      ),
      accessibilityPermission: permission
    )
    let lifecycle = ApplicationLifecycleController(
      model: model,
      terminator: ShortcutTerminator()
    )
    let controller = GlobalShortcutController(backend: backend)
    controller.start {
      Task { await lifecycle.handleShortcut() }
    }

    backend.sendKeyUp()
    await Task.yield()

    #expect(permission.promptCount == 0)
    #expect(lifecycle.isPopoverPresented)
  }

  @Test("shortcut opens checking feedback and keeps the final verdict visible")
  func opensCheckingFeedback() async {
    let reader = ControllableShortcutSelectionReader()
    let model = LanguageCheckViewModel(
      useCase: LanguageCheckUseCase(
        selectionReader: reader,
        languageDetector: ShortcutDetector()
      ),
      accessibilityPermission: GrantedShortcutPermissionController()
    )
    let lifecycle = ApplicationLifecycleController(
      model: model,
      terminator: ShortcutTerminator()
    )

    let task = Task { await lifecycle.handleShortcut() }
    await Task.yield()

    #expect(lifecycle.isPopoverPresented)
    #expect(model.state == .checking)

    await reader.resume(with: SelectedText("Tere"))
    await task.value

    #expect(lifecycle.isPopoverPresented)
    #expect(model.state == .verdict(.estonian))
  }

  @Test("dismissing shortcut feedback cancels the active check")
  func cancellation() async {
    let model = LanguageCheckViewModel(
      useCase: LanguageCheckUseCase(
        selectionReader: CancellableShortcutSelectionReader(),
        languageDetector: ShortcutDetector()
      ),
      accessibilityPermission: GrantedShortcutPermissionController()
    )
    let lifecycle = ApplicationLifecycleController(
      model: model,
      terminator: ShortcutTerminator()
    )
    let task = Task { await lifecycle.handleShortcut() }
    await Task.yield()
    #expect(model.state == .checking)

    await lifecycle.dismissPopover()
    await task.value

    #expect(!lifecycle.isPopoverPresented)
    #expect(model.state == .waiting)
  }

  @Test("registration failure does not disable the menu language check")
  func registrationFailureLeavesCheckUsable() async {
    let backend = ShortcutBackendSpy()
    backend.failingShortcuts = [.default]
    let controller = GlobalShortcutController(backend: backend)
    controller.start {}

    let model = LanguageCheckViewModel(
      useCase: LanguageCheckUseCase(
        selectionReader: ShortcutSelectionReader(),
        languageDetector: ShortcutDetector()
      ),
      accessibilityPermission: GrantedShortcutPermissionController()
    )
    await model.check()

    #expect(controller.registrationMessage == GlobalShortcutController.failureMessage)
    #expect(model.state == .verdict(.estonian))
  }
}

@MainActor
private final class ShortcutBackendSpy: GlobalShortcutBackend {
  var storedShortcut: GlobalShortcut?
  var isIntentionallyCleared = false
  var registeredShortcut: GlobalShortcut?
  var registeredPhase: GlobalShortcutPhase?
  var rejectedShortcuts: Set<GlobalShortcut> = []
  var failingShortcuts: Set<GlobalShortcut> = []
  var stopCount = 0
  private var handler: (() -> Void)?

  init(storedShortcut: GlobalShortcut? = nil) {
    self.storedShortcut = storedShortcut
  }

  func loadShortcut(default defaultShortcut: GlobalShortcut) -> GlobalShortcut? {
    isIntentionallyCleared ? nil : (storedShortcut ?? defaultShortcut)
  }

  func register(
    _ shortcut: GlobalShortcut,
    phase: GlobalShortcutPhase,
    handler: @escaping () -> Void
  ) -> Bool {
    guard !rejectedShortcuts.contains(shortcut), !failingShortcuts.contains(shortcut) else {
      return false
    }
    registeredShortcut = shortcut
    registeredPhase = phase
    self.handler = handler
    return true
  }

  func unregister() {
    registeredShortcut = nil
    handler = nil
  }

  func persist(_ shortcut: GlobalShortcut?) {
    storedShortcut = shortcut
    isIntentionallyCleared = shortcut == nil
  }

  func isKnownConflict(_ shortcut: GlobalShortcut) -> Bool {
    rejectedShortcuts.contains(shortcut)
  }

  func stop() {
    stopCount += 1
    unregister()
  }

  func sendKeyDown() {}
  func sendKeyUp() { handler?() }
}

@MainActor
private final class DeniedPermissionController: AccessibilityPermissionControlling {
  private(set) var promptCount = 0
  func checkPermission() -> Bool { false }
  func openSettings() { promptCount += 1 }
}

@MainActor
private final class GrantedShortcutPermissionController: AccessibilityPermissionControlling {
  func checkPermission() -> Bool { true }
  func openSettings() {}
}

private struct ShortcutSelectionReader: SelectionReading {
  func readSelectedText() async throws -> SelectedText { SelectedText("Tere") }
}

private struct ShortcutDetector: LanguageDetecting {
  func detectLanguage(
    of selectedText: SelectedText,
    configuration: LanguageCheckConfiguration
  ) async throws -> LanguageVerdict { .estonian }
}

private actor ControllableShortcutSelectionReader: SelectionReading {
  private var continuation: CheckedContinuation<SelectedText, Never>?

  func readSelectedText() async throws -> SelectedText {
    await withCheckedContinuation { continuation = $0 }
  }

  func resume(with text: SelectedText) {
    continuation?.resume(returning: text)
    continuation = nil
  }
}

private actor CancellableShortcutSelectionReader: SelectionReading {
  func readSelectedText() async throws -> SelectedText {
    try await Task.sleep(for: .seconds(60))
    return SelectedText("Tere")
  }
}

@MainActor
private final class ShortcutTerminator: ApplicationTerminating {
  func terminate() {}
}
