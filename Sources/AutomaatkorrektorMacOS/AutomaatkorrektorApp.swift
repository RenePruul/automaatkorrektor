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
    installMainMenu(on: application)
    application.run()
  }

  private static func installMainMenu(on application: NSApplication) {
    let mainMenu = NSMenu()

    let applicationMenuItem = NSMenuItem(title: "Automaatkorrektor", action: nil, keyEquivalent: "")
    let applicationMenu = NSMenu(title: "Automaatkorrektor")
    applicationMenu.addItem(
      withTitle: "Välju Automaatkorrektorist",
      action: #selector(NSApplication.terminate(_:)),
      keyEquivalent: "q"
    )
    applicationMenuItem.submenu = applicationMenu
    mainMenu.addItem(applicationMenuItem)

    let editMenuItem = NSMenuItem(title: "Redigeerimine", action: nil, keyEquivalent: "")
    let editMenu = NSMenu(title: "Redigeerimine")
    editMenu.addItem(withTitle: "Võta tagasi", action: Selector(("undo:")), keyEquivalent: "z")
    editMenu.addItem(withTitle: "Tee uuesti", action: Selector(("redo:")), keyEquivalent: "Z")
    editMenu.addItem(.separator())
    editMenu.addItem(withTitle: "Lõika", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
    editMenu.addItem(withTitle: "Kopeeri", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
    editMenu.addItem(withTitle: "Kleebi", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
    editMenu.addItem(
      withTitle: "Vali kõik",
      action: #selector(NSText.selectAll(_:)),
      keyEquivalent: "a"
    )
    editMenuItem.submenu = editMenu
    mainMenu.addItem(editMenuItem)

    application.mainMenu = mainMenu
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
