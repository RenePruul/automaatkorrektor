import AppKit

private enum HarnessExpectation: String {
  case readable = "readable selection"
  case readOnly = "read-only rejection"
  case disabled = "disabled rejection"
  case secure = "secure rejection"
}

@main
@MainActor
final class AXIntegrationHarnessApp: NSObject, NSApplicationDelegate {
  private let reader = AccessibilitySelectedTextReader.nativeTextControlTestHarness()
  private var window: NSWindow?
  private var resultLabel: NSTextField?
  private var activeTask: Task<Void, Never>?

  static func main() {
    let application = NSApplication.shared
    let delegate = AXIntegrationHarnessApp()
    application.delegate = delegate
    application.run()
  }

  func applicationDidFinishLaunching(_ notification: Notification) {
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 620, height: 480),
      styleMask: [.titled, .closable],
      backing: .buffered,
      defer: false
    )
    window.title = "AX-integratsiooni testirakendus"
    window.contentView = makeContentView()
    window.center()
    window.makeKeyAndOrderFront(nil)
    NSApplication.shared.activate(ignoringOtherApps: true)
    self.window = window
  }

  func applicationWillTerminate(_ notification: Notification) {
    activeTask?.cancel()
  }

  private func makeContentView() -> NSView {
    let stack = NSStackView()
    stack.orientation = .vertical
    stack.alignment = .leading
    stack.spacing = 12
    stack.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)

    let title = NSTextField(labelWithString: "Päris Accessibility-integratsioon")
    title.font = .boldSystemFont(ofSize: 18)
    stack.addArrangedSubview(title)

    let instructions = NSTextField(
      wrappingLabelWithString: """
        Anna sellele testirakendusele Accessibility-luba. Vajuta iga kontrolli jaoks nuppu „Käivita kontroll“ ja seejärel viie sekundi jooksul rakenduse NativeTextControlHost vastavat nuppu „Valmista ette“. Testirakendus kasutab päris SystemAXReaderit, ei võta kunagi ühendust võrguteenusega ning kuvab ainult metaandmetega PASS/FAIL-tulemuse.
        """)
    instructions.maximumNumberOfLines = 0
    instructions.preferredMaxLayoutWidth = 570
    stack.addArrangedSubview(instructions)

    addButton("Muudetav NSTextField", expectation: .readable, to: stack)
    addButton("NSSearchField", expectation: .readable, to: stack)
    addButton("Muudetav NSTextView", expectation: .readable, to: stack)
    addButton("Kirjutuskaitstud NSTextField", expectation: .readOnly, to: stack)
    addButton("Keelatud NSTextField", expectation: .disabled, to: stack)
    addButton("NSSecureTextField", expectation: .secure, to: stack)

    let resultLabel = NSTextField(wrappingLabelWithString: "Metaandmetega tulemus: käivitamata")
    resultLabel.maximumNumberOfLines = 0
    resultLabel.preferredMaxLayoutWidth = 570
    stack.addArrangedSubview(resultLabel)
    self.resultLabel = resultLabel
    return stack
  }

  private func addButton(
    _ title: String,
    expectation: HarnessExpectation,
    to stack: NSStackView
  ) {
    let button = NSButton(
      title: "Käivita kontroll: \(title)",
      target: self,
      action: #selector(runCheck(_:))
    )
    button.identifier = NSUserInterfaceItemIdentifier(expectation.rawValue)
    stack.addArrangedSubview(button)
  }

  @objc private func runCheck(_ sender: NSButton) {
    guard
      let rawExpectation = sender.identifier?.rawValue,
      let expectation = HarnessExpectation(rawValue: rawExpectation)
    else { return }

    activeTask?.cancel()
    resultLabel?.stringValue =
      "Metaandmetega tulemus: kontroll käivitatud; fokuseeri vastav testvälja juhtelement"
    activeTask = Task { [weak self] in
      do {
        try await Task.sleep(for: .seconds(5))
        try Task.checkCancellation()
        _ = try await self?.reader.readSelectedText()
        self?.showResult(expectation == .readable, detail: "valik vastu võetud")
      } catch is CancellationError {
        return
      } catch let error as AccessibilitySelectionError {
        self?.showResult(
          Self.matches(error, expectation: expectation),
          detail: Self.metadataName(for: error)
        )
      } catch {
        self?.showResult(false, detail: "ootamatu veakategooria")
      }
      NSApplication.shared.activate(ignoringOtherApps: true)
    }
  }

  private func showResult(_ passed: Bool, detail: String) {
    resultLabel?.stringValue =
      "Metaandmetega tulemus: \(passed ? "PASS" : "FAIL") — \(detail)"
  }

  private static func matches(
    _ error: AccessibilitySelectionError,
    expectation: HarnessExpectation
  ) -> Bool {
    switch (expectation, error) {
    case (.readOnly, .readOnly), (.disabled, .unsupportedTextField),
      (.secure, .protectedContent):
      true
    default:
      false
    }
  }

  private static func metadataName(for error: AccessibilitySelectionError) -> String {
    switch error {
    case .permissionRequired: "luba on vajalik"
    case .noFocusedControl: "fokuseeritud juhtelement puudub"
    case .protectedContent: "kaitstud sisu lükati tagasi"
    case .unsupportedTextField: "toetamata või keelatud juhtelement lükati tagasi"
    case .readOnly: "kirjutuskaitstud juhtelement lükati tagasi"
    case .noSelection: "valik puudub"
    case .invalidSelection: "vigane valik"
    case .selectionTooLarge: "valik on liiga suur"
    case .focusChanged: "fookus muutus"
    case .targetUnavailable: "sihtkoht pole saadaval"
    case .unsupportedApplication: "rakendus lükati tagasi"
    case .unknown: "tundmatu metaandmete viga"
    }
  }
}
