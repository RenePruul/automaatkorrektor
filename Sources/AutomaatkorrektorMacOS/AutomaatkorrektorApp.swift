import AppKit
import AutomaatkorrektorCore

@main
@MainActor
final class AutomaatkorrektorApp: NSObject, NSApplicationDelegate {
  private var menuBarController: MenuBarController<GlobalShortcutController>?
  private var activationModel: LanguageCheckViewModel?

  init(activationModel: LanguageCheckViewModel? = nil) {
    self.activationModel = activationModel
  }

  static func main() {
    let application = NSApplication.shared
    let delegate = AutomaatkorrektorApp()
    application.delegate = delegate
    application.run()
  }

  func applicationDidFinishLaunching(_ notification: Notification) {
    NSApplication.shared.setActivationPolicy(.accessory)

    let settings = APISettingsStore()
    let languageCheckConsent = LanguageCheckConsentStore()
    let useCase = LanguageCheckUseCase(
      configurationProvider: settings,
      selectionReader: AccessibilitySelectedTextReader(),
      languageDetector: LanguageAPIClient(),
      languageCheckConsent: languageCheckConsent
    )
    let model = LanguageCheckViewModel(
      useCase: useCase,
      accessibilityPermission: MacOSAccessibilityPermissionController(),
      languageCheckConsent: languageCheckConsent
    )
    activationModel = model
    let lifecycle = ApplicationLifecycleController(
      model: model,
      terminator: NSApplicationTerminator()
    )
    let shortcut = GlobalShortcutController(backend: KeyboardShortcutsBackend())
    let controller = MenuBarController(
      model: model,
      lifecycle: lifecycle,
      settings: settings,
      shortcut: shortcut,
      languageCheckConsent: languageCheckConsent
    )

    lifecycle.launch()
    controller.install()
    menuBarController = controller
  }

  func applicationShouldHandleReopen(
    _ sender: NSApplication,
    hasVisibleWindows flag: Bool
  ) -> Bool {
    menuBarController?.showPopover()
    return true
  }

  func applicationDidBecomeActive(_ notification: Notification) {
    Task { await refreshAccessibilityPermissionAfterActivation() }
  }

  func refreshAccessibilityPermissionAfterActivation() async {
    await activationModel?.refreshAccessibilityPermission()
  }
}
