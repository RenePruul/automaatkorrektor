import AutomaatkorrektorCore
import KeyboardShortcuts
import Testing

@testable import AutomaatkorrektorMacOS

@MainActor
@Suite("Global shortcut")
struct GlobalShortcutControllerTests {
  @Test("repeated held-key downs and one release produce exactly one language check")
  func defaultShortcutInvokesOnKeyUp() async {
    let backend = ShortcutBackendSpy()
    let reader = CountingShortcutSelectionReader()
    let detector = CountingShortcutDetector()
    let completion = AsyncSignal()
    let model = LanguageCheckViewModel(
      useCase: LanguageCheckUseCase(
        selectionReader: reader,
        languageDetector: detector
      ),
      accessibilityPermission: GrantedShortcutPermissionController()
    )
    let lifecycle = ApplicationLifecycleController(
      model: model,
      terminator: ShortcutTerminator()
    )
    let controller = GlobalShortcutController(backend: backend)
    controller.start {
      Task {
        await lifecycle.handleShortcut()
        await completion.signal()
      }
    }

    #expect(backend.registeredShortcut == .default)
    #expect(backend.keyUpRegistrationCount == 1)
    for _ in 0..<20 {
      backend.sendKeyDown()
    }
    #expect(await reader.readCount == 0)
    #expect(await detector.requestCount == 0)

    backend.sendKeyUp()
    await completion.wait()

    #expect(await reader.readCount == 1)
    #expect(await detector.requestCount == 1)
    #expect(model.state == .verdict(.estonian))
  }

  @Test("recorder blocks known system and application menu conflicts")
  func strictRecorderConflictPolicy() {
    #expect(
      KeyboardShortcutConflictPolicy.required
        == KeyboardShortcuts.ConflictPolicy(
          menuItem: .block,
          systemShortcut: .block
        )
    )
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
    let completion = AsyncSignal()
    controller.start {
      Task {
        await lifecycle.handleShortcut()
        await completion.signal()
      }
    }

    backend.sendKeyUp()
    await completion.wait()

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
    await reader.waitUntilReadStarted()

    #expect(lifecycle.isPopoverPresented)
    #expect(model.state == .checking)

    await reader.resume(with: SelectedText("Tere"))
    await task.value

    #expect(lifecycle.isPopoverPresented)
    #expect(model.state == .verdict(.estonian))
  }

  @Test("dismissing shortcut feedback cancels the active check")
  func cancellation() async {
    let reader = CancellableShortcutSelectionReader()
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
    await reader.waitUntilReadStarted()
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
  var keyUpRegistrationCount = 0
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

  func registerKeyUp(
    _ shortcut: GlobalShortcut,
    handler: @escaping () -> Void
  ) -> Bool {
    guard !rejectedShortcuts.contains(shortcut), !failingShortcuts.contains(shortcut) else {
      return false
    }
    registeredShortcut = shortcut
    keyUpRegistrationCount += 1
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

private actor CountingShortcutSelectionReader: SelectionReading {
  private(set) var readCount = 0

  func readSelectedText() async throws -> SelectedText {
    readCount += 1
    return SelectedText("Tere")
  }
}

private actor CountingShortcutDetector: LanguageDetecting {
  private(set) var requestCount = 0

  func detectLanguage(
    of selectedText: SelectedText,
    configuration: LanguageCheckConfiguration
  ) async throws -> LanguageVerdict {
    requestCount += 1
    return .estonian
  }
}

private actor ControllableShortcutSelectionReader: SelectionReading {
  private var continuation: CheckedContinuation<SelectedText, Never>?
  private var didStartReading = false
  private var startWaiters: [CheckedContinuation<Void, Never>] = []

  func readSelectedText() async throws -> SelectedText {
    didStartReading = true
    let waiters = startWaiters
    startWaiters.removeAll()
    for waiter in waiters {
      waiter.resume()
    }
    return await withCheckedContinuation { continuation = $0 }
  }

  func waitUntilReadStarted() async {
    guard !didStartReading else { return }
    await withCheckedContinuation { startWaiters.append($0) }
  }

  func resume(with text: SelectedText) {
    continuation?.resume(returning: text)
    continuation = nil
  }
}

private actor CancellableShortcutSelectionReader: SelectionReading {
  private var didStartReading = false
  private var startWaiters: [CheckedContinuation<Void, Never>] = []

  func readSelectedText() async throws -> SelectedText {
    didStartReading = true
    let waiters = startWaiters
    startWaiters.removeAll()
    for waiter in waiters {
      waiter.resume()
    }
    try await Task.sleep(for: .seconds(60))
    return SelectedText("Tere")
  }

  func waitUntilReadStarted() async {
    guard !didStartReading else { return }
    await withCheckedContinuation { startWaiters.append($0) }
  }
}

private actor AsyncSignal {
  private var isSignaled = false
  private var waiters: [CheckedContinuation<Void, Never>] = []

  func signal() {
    isSignaled = true
    let pending = waiters
    waiters.removeAll()
    for waiter in pending {
      waiter.resume()
    }
  }

  func wait() async {
    guard !isSignaled else { return }
    await withCheckedContinuation { waiters.append($0) }
  }
}

@MainActor
private final class ShortcutTerminator: ApplicationTerminating {
  func terminate() {}
}
