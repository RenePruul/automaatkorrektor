import AppKit

@main
@MainActor
final class NativeTextControlHost: NSObject, NSApplicationDelegate {
  private var window: NSWindow?

  static func main() {
    let application = NSApplication.shared
    let delegate = NativeTextControlHost()
    application.delegate = delegate
    application.run()
  }

  func applicationDidFinishLaunching(_ notification: Notification) {
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 620, height: 780),
      styleMask: [.titled, .closable],
      backing: .buffered,
      defer: false
    )
    window.title = "Automaatkorrektori tekstijuhtelementide testirakendus"
    window.contentView = makeFixtureView(in: window)
    window.center()
    window.makeKeyAndOrderFront(nil)
    NSApplication.shared.activate(ignoringOtherApps: true)
    self.window = window
  }

  private func makeFixtureView(in window: NSWindow) -> NSView {
    let stack = NSStackView()
    stack.orientation = .vertical
    stack.alignment = .leading
    stack.spacing = 12
    stack.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)

    let instructions = NSTextField(
      wrappingLabelWithString: """
        Ainult testimiseks mõeldud sünteetilised juhtelemendid. Pärast AX-integratsiooni testirakenduses kontrolli käivitamist vajuta vastavat nuppu „Valmista ette“. See fokuseerib juhtelemendi ja valib sünteetilise teksti lõikelauda kasutamata.
        """)
    instructions.maximumNumberOfLines = 0
    instructions.preferredMaxLayoutWidth = 570
    stack.addArrangedSubview(instructions)

    let editableField = NSTextField(string: "HARNESS-EDITABLE-TEXT-FIELD")
    editableField.isEditable = true
    editableField.isSelectable = true
    editableField.identifier = NSUserInterfaceItemIdentifier("editable-text-field")

    let searchField = NSSearchField(string: "HARNESS-SEARCH-FIELD")
    searchField.identifier = NSUserInterfaceItemIdentifier("search-field")

    let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 540, height: 100))
    textView.string = "HARNESS-EDITABLE-TEXT-AREA"
    textView.isEditable = true
    textView.isSelectable = true
    textView.identifier = NSUserInterfaceItemIdentifier("editable-text-area")
    let textArea = NSScrollView(frame: NSRect(x: 0, y: 0, width: 540, height: 100))
    textArea.documentView = textView
    textArea.hasVerticalScroller = true

    let readOnlyField = NSTextField(string: "HARNESS-READ-ONLY")
    readOnlyField.isEditable = false
    readOnlyField.isSelectable = true
    readOnlyField.identifier = NSUserInterfaceItemIdentifier("read-only-text-field")

    let disabledField = NSTextField(string: "HARNESS-DISABLED")
    disabledField.isEditable = true
    disabledField.isSelectable = true
    disabledField.isEnabled = false
    disabledField.identifier = NSUserInterfaceItemIdentifier("disabled-text-field")

    let secureField = NSSecureTextField(string: "HARNESS-SECRET-CANARY")
    secureField.identifier = NSUserInterfaceItemIdentifier("secure-text-field")

    let fixtures: [(String, NSView, () -> Void)] = [
      (
        "Muudetav NSTextField", editableField,
        {
          window.makeFirstResponder(editableField)
          editableField.selectText(nil)
        }
      ),
      (
        "NSSearchField", searchField,
        {
          window.makeFirstResponder(searchField)
          searchField.selectText(nil)
        }
      ),
      (
        "Muudetav NSTextView", textArea,
        {
          window.makeFirstResponder(textView)
          textView.setSelectedRange(NSRange(location: 0, length: textView.string.count))
        }
      ),
      (
        "Kirjutuskaitstud NSTextField", readOnlyField,
        {
          window.makeFirstResponder(readOnlyField)
          readOnlyField.selectText(nil)
        }
      ),
      (
        "Keelatud NSTextField", disabledField,
        {
          disabledField.isEnabled = true
          window.makeFirstResponder(disabledField)
          disabledField.selectText(nil)
          DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            disabledField.isEnabled = false
          }
        }
      ),
      (
        "NSSecureTextField — sisu ei tohi kunagi lugeda", secureField,
        {
          window.makeFirstResponder(secureField)
          secureField.selectText(nil)
        }
      ),
    ]

    for (title, control, prepare) in fixtures {
      stack.addArrangedSubview(NSTextField(labelWithString: title))
      stack.addArrangedSubview(control)
      control.widthAnchor.constraint(equalToConstant: 540).isActive = true
      stack.addArrangedSubview(
        FixtureActionButton(title: "Valmista ette: \(title)", action: prepare)
      )
    }

    return stack
  }
}

@MainActor
private final class FixtureActionButton: NSButton {
  private let fixtureAction: () -> Void

  init(title: String, action: @escaping () -> Void) {
    fixtureAction = action
    super.init(frame: .zero)
    self.title = title
    bezelStyle = .rounded
    target = self
    self.action = #selector(runFixtureAction)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) is unavailable")
  }

  @objc private func runFixtureAction() {
    fixtureAction()
  }
}
