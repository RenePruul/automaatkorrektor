import AppKit
import SwiftUI

struct APISettingsView<Shortcut: GlobalShortcutControlling>: View {
  @ObservedObject var settings: APISettingsStore
  @ObservedObject var shortcut: Shortcut
  @ObservedObject var languageCheckConsent: LanguageCheckConsentStore

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      GroupBox("Keeleteenus") {
        VStack(alignment: .leading, spacing: 10) {
          Text("API-aadress")
            .font(.subheadline.weight(.semibold))

          TextField(
            "",
            text: Binding(
              get: { settings.draftBaseURL },
              set: { updateBaseURL($0) }
            ),
            prompt: Text("https://keel.example.ee")
          )
          .labelsHidden()
          .frame(maxWidth: .infinity)
          .textFieldStyle(.roundedBorder)
          .multilineTextAlignment(.leading)
          .environment(\.layoutDirection, .leftToRight)
          .disableAutocorrection(true)

          Text(
            "Kaugteenus kasutab HTTPS-i. Kohalik vaikimisi aadress on http://127.0.0.1:8000."
          )
          .font(.caption)
          .foregroundStyle(.secondary)

          serviceStatus
        }
        .padding(.vertical, 4)
      }

      GroupBox("Kiirklahv") {
        VStack(alignment: .leading, spacing: 8) {
          GlobalShortcutRecorder(controller: shortcut)

          if let message = shortcut.registrationMessage {
            Text(message)
              .font(.caption)
              .foregroundStyle(.red)
          }
        }
        .padding(.vertical, 4)
      }
    }
    .padding(20)
    .frame(width: 500, height: 360, alignment: .top)
    .preferredColorScheme(.dark)
  }

  @ViewBuilder
  private var serviceStatus: some View {
    if let draftEndpoint = settings.draftEndpoint {
      switch languageCheckConsent.status(for: draftEndpoint) {
      case .local:
        Label("Kohalik teenus — tekst jääb sellesse Maci", systemImage: "laptopcomputer")
          .font(.caption)
          .foregroundStyle(.secondary)
      case .origin(let origin, let hasConsent):
        VStack(alignment: .leading, spacing: 6) {
          Label("Kaugteenus: \(origin.displayValue)", systemImage: "network")
            .font(.caption)
          Text(
            hasConsent
              ? "Teksti saatmine sellele teenusele on lubatud."
              : "Luba küsitakse enne esimest teksti saatmist."
          )
          .font(.caption)
          .foregroundStyle(.secondary)

          HStack(spacing: 12) {
            if hasConsent {
              Button("Tühista luba") {
                languageCheckConsent.revokeConsent()
              }
              .buttonStyle(.link)
            }

            Button("Kasuta kohalikku teenust") {
              useLocalService()
            }
            .buttonStyle(.link)
          }
        }
      }
    } else {
      VStack(alignment: .leading, spacing: 6) {
        Label(
          settings.validationMessage ?? "Sisesta täielik API-aadress.",
          systemImage: "info.circle"
        )
        .font(.caption)
        .foregroundStyle(.secondary)

        Button("Kasuta kohalikku teenust") {
          useLocalService()
        }
        .buttonStyle(.link)
      }
    }
  }

  private func updateBaseURL(_ value: String) {
    settings.updateBaseURL(value)
    if settings.draftEndpoint?.languageCheckConsentOrigin == nil {
      languageCheckConsent.revokeConsent()
    }
  }

  private func useLocalService() {
    settings.useLocalService()
    languageCheckConsent.revokeConsent()
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
    window.setContentSize(NSSize(width: 500, height: 360))
    window.center()
  }

  func show() {
    window.makeKeyAndOrderFront(nil)
    NSApplication.shared.activate(ignoringOtherApps: true)
  }
}
