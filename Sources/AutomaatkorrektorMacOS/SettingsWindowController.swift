import AppKit
import SwiftUI

struct APISettingsView: View {
  @ObservedObject var settings: APISettingsStore

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
    }
    .formStyle(.grouped)
    .padding(16)
    .frame(width: 430, height: 150)
    .preferredColorScheme(.dark)
  }
}

@MainActor
final class SettingsWindowController {
  private let window: NSWindow

  init(settings: APISettingsStore) {
    let hostingController = NSHostingController(rootView: APISettingsView(settings: settings))
    window = NSWindow(contentViewController: hostingController)
    window.title = "Automaatkorrektori seaded"
    window.styleMask = [.titled, .closable]
    window.isReleasedWhenClosed = false
    window.setContentSize(NSSize(width: 430, height: 150))
    window.center()
  }

  func show() {
    window.makeKeyAndOrderFront(nil)
    NSApplication.shared.activate(ignoringOtherApps: true)
  }
}
