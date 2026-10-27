import AppKit
import SwiftUI

struct APISettingsView<Shortcut: GlobalShortcutControlling>: View {
  @ObservedObject var settings: APISettingsStore
  @ObservedObject var shortcut: Shortcut

  var body: some View {
    Form {
      VStack(alignment: .leading, spacing: 6) {
        TextField(
          "Keele-API aadress",
          text: Binding(
            get: { settings.draftBaseURL },
            set: { settings.updateBaseURL($0) }
          )
        )
        .textFieldStyle(.roundedBorder)

        if let message = settings.validationMessage {
          Text(message)
            .font(.caption)
            .foregroundStyle(.red)
        }
      }
      VStack(alignment: .leading, spacing: 6) {
        GlobalShortcutRecorder(controller: shortcut)

        if let message = shortcut.registrationMessage {
          Text(message)
            .font(.caption)
            .foregroundStyle(.red)
        }
      }
    }
    .formStyle(.grouped)
    .padding(16)
    .frame(width: 430, height: 210)
    .preferredColorScheme(.dark)
  }
}

@MainActor
final class SettingsWindowController {
  private let window: NSWindow

  init<Shortcut: GlobalShortcutControlling>(settings: APISettingsStore, shortcut: Shortcut) {
    let hostingController = NSHostingController(
      rootView: APISettingsView(settings: settings, shortcut: shortcut)
    )
    window = NSWindow(contentViewController: hostingController)
    window.title = "Automaatkorrektori seaded"
    window.styleMask = [.titled, .closable]
    window.isReleasedWhenClosed = false
    window.setContentSize(NSSize(width: 430, height: 210))
    window.center()
  }

  func show() {
    window.makeKeyAndOrderFront(nil)
    NSApplication.shared.activate(ignoringOtherApps: true)
  }
}
