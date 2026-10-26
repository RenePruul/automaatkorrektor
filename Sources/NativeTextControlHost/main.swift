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
      contentRect: NSRect(x: 0, y: 0, width: 620, height: 520),
      styleMask: [.titled, .closable],
      backing: .buffered,
      defer: false
    )
    window.title = "Automaatkorrektor native text-control harness"
    window.contentView = makeFixtureView()
    window.center()
    window.makeKeyAndOrderFront(nil)
    NSApplication.shared.activate(ignoringOtherApps: true)
    self.window = window
  }

  private func makeFixtureView() -> NSView {
    let stack = NSStackView()
    stack.orientation = .vertical
    stack.alignment = .leading
    stack.spacing = 12
    stack.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)

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

    for (title, control) in [
      ("Editable NSTextField", editableField as NSView),
      ("NSSearchField", searchField),
      ("Editable NSTextView", textArea),
      ("Read-only NSTextField", readOnlyField),
      ("Disabled NSTextField", disabledField),
      ("NSSecureTextField — must never be read", secureField),
    ] {
      stack.addArrangedSubview(NSTextField(labelWithString: title))
      stack.addArrangedSubview(control)
      control.widthAnchor.constraint(equalToConstant: 540).isActive = true
    }

    return stack
  }
}
