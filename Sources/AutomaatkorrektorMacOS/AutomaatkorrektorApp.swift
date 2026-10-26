import AppKit
import AutomaatkorrektorCore

@main
@MainActor
final class AutomaatkorrektorApp: NSObject, NSApplicationDelegate {
  private var menuBarController: MenuBarController?

  static func main() {
    let application = NSApplication.shared
    let delegate = AutomaatkorrektorApp()
    application.delegate = delegate
    application.run()
  }

  func applicationDidFinishLaunching(_ notification: Notification) {
    NSApplication.shared.setActivationPolicy(.accessory)

    let settings = APISettingsStore()
    let useCase = LanguageCheckUseCase(
      selectionReader: DemoSelectionReader(),
      languageDetector: LanguageAPIClient(
        baseURL: { await settings.currentBaseURL() }
      )
    )
    let model = LanguageCheckViewModel(useCase: useCase)
    let lifecycle = ApplicationLifecycleController(
      model: model,
      terminator: NSApplicationTerminator()
    )
    let controller = MenuBarController(
      model: model,
      lifecycle: lifecycle,
      settings: settings
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
}

private actor DemoSelectionReader: SelectionReading {
  func readSelectedText() async throws -> SelectedText {
    SelectedText("Tere maailm")
  }
}
