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
    window.title = "AX integration harness — test only"
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

    let title = NSTextField(labelWithString: "Real Accessibility integration")
    title.font = .boldSystemFont(ofSize: 18)
    stack.addArrangedSubview(title)

    let instructions = NSTextField(
      wrappingLabelWithString: """
        Grant Accessibility access to this harness. For each check, press Arm, then within five seconds click the matching Prepare button in NativeTextControlHost. The harness uses the real SystemAXReader, never contacts a network service, and displays only metadata-only PASS/FAIL.
        """)
    instructions.maximumNumberOfLines = 0
    instructions.preferredMaxLayoutWidth = 570
    stack.addArrangedSubview(instructions)

    addButton("Editable NSTextField", expectation: .readable, to: stack)
    addButton("NSSearchField", expectation: .readable, to: stack)
    addButton("Editable NSTextView", expectation: .readable, to: stack)
    addButton("Read-only NSTextField", expectation: .readOnly, to: stack)
    addButton("Disabled NSTextField", expectation: .disabled, to: stack)
    addButton("NSSecureTextField", expectation: .secure, to: stack)

    let resultLabel = NSTextField(wrappingLabelWithString: "Metadata-only result: not run")
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
      title: "Arm: \(title)",
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
    resultLabel?.stringValue = "Metadata-only result: armed; focus the matching host control"
    activeTask = Task { [weak self] in
      do {
        try await Task.sleep(for: .seconds(5))
        try Task.checkCancellation()
        _ = try await self?.reader.readSelectedText()
        self?.showResult(expectation == .readable, detail: "selection accepted")
      } catch is CancellationError {
        return
      } catch let error as AccessibilitySelectionError {
        self?.showResult(
          Self.matches(error, expectation: expectation),
          detail: Self.metadataName(for: error)
        )
      } catch {
        self?.showResult(false, detail: "unexpected error category")
      }
      NSApplication.shared.activate(ignoringOtherApps: true)
    }
  }

  private func showResult(_ passed: Bool, detail: String) {
    resultLabel?.stringValue =
      "Metadata-only result: \(passed ? "PASS" : "FAIL") — \(detail)"
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
    case .permissionRequired: "permission required"
    case .noFocusedControl: "no focused control"
    case .protectedContent: "protected content rejected"
    case .unsupportedTextField: "unsupported or disabled control rejected"
    case .readOnly: "read-only control rejected"
    case .noSelection: "no selection"
    case .invalidSelection: "invalid selection"
    case .selectionTooLarge: "selection too large"
    case .focusChanged: "focus changed"
    case .targetUnavailable: "target unavailable"
    case .unsupportedApplication: "application rejected"
    case .unknown: "unknown metadata error"
    }
  }
}
