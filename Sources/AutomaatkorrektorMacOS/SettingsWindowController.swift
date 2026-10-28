import AppKit
import SwiftUI

struct APISettingsView<Shortcut: GlobalShortcutControlling>: View {
  @ObservedObject var settings: APISettingsStore
  @ObservedObject var shortcut: Shortcut
  @ObservedObject var languageCheckConsent: LanguageCheckConsentStore

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

        servicePrivacyStatus
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
    .frame(width: 460, height: 300)
    .preferredColorScheme(.dark)
  }

  @ViewBuilder
  private var servicePrivacyStatus: some View {
    switch languageCheckConsent.status(for: settings.endpoint) {
    case .local:
      Label("Kohalik teenus — tekst ei lahku sellest Macist", systemImage: "laptopcomputer")
        .font(.caption)
        .foregroundStyle(.secondary)
    case .origin(let origin, let hasConsent):
      VStack(alignment: .leading, spacing: 5) {
        Label("Kaugteenus: \(origin.displayValue)", systemImage: "network")
          .font(.caption)
        Text(
          hasConsent
            ? "Sellele teenusele on teksti saatmine lubatud."
            : "Sellele teenusele ei ole teksti saatmine lubatud. Luba küsitakse kontrollimisel."
        )
        .font(.caption)
        .foregroundStyle(.secondary)

        if hasConsent {
          Button("Tühista kaugteenuse luba") {
            languageCheckConsent.revokeConsent()
          }
          .buttonStyle(.link)
        }
      }
    }
  }
}

@MainActor
final class SettingsWindowController {
  private let window: NSWindow

  init<Shortcut: GlobalShortcutControlling>(
    settings: APISettingsStore,
    shortcut: Shortcut,
    languageCheckConsent: LanguageCheckConsentStore
  ) {
    let hostingController = NSHostingController(
      rootView: APISettingsView(
        settings: settings,
        shortcut: shortcut,
        languageCheckConsent: languageCheckConsent
      )
    )
    window = NSWindow(contentViewController: hostingController)
    window.title = "Automaatkorrektori seaded"
    window.styleMask = [.titled, .closable]
    window.isReleasedWhenClosed = false
    window.setContentSize(NSSize(width: 460, height: 300))
    window.center()
  }

  func show() {
    window.makeKeyAndOrderFront(nil)
    NSApplication.shared.activate(ignoringOtherApps: true)
  }
}
