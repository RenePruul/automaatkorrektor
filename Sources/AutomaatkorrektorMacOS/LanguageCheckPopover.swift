import AutomaatkorrektorCore
import SwiftUI

struct LanguageCheckPopover: View {
  @ObservedObject var model: LanguageCheckViewModel
  @ObservedObject var shortcut: GlobalShortcutController
  let showSettings: () -> Void
  let quit: @MainActor () async -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      statusHeader
        .padding(14)

      Divider()

      if model.state == .blocked(.accessibilityPermissionRequired) {
        permissionRecovery
        Divider()
      }

      if model.showsRetryAction {
        Button("Proovi uuesti") {
          Task { await model.retryUnavailableService() }
        }
        .buttonStyle(.borderedProminent)
        .padding(.horizontal, 14)
        .padding(.bottom, 12)

        Divider()
      }

      row(
        title: "Kontrolli valitud teksti",
        trailing: shortcut.shortcut?.displayName ?? "—",
        symbol: "play.fill"
      ) {
        Task { await model.check() }
      }
      .disabled(model.state == .checking)

      Divider()

      row(title: "Seaded…", trailing: "⌘,", symbol: "gearshape") {
        showSettings()
      }

      Divider()

      row(title: "Välju", trailing: "⌘Q", symbol: "power") {
        Task { await quit() }
      }
    }
    .frame(width: 330)
    .fixedSize(horizontal: false, vertical: true)
    .preferredColorScheme(.dark)
  }

  private var statusHeader: some View {
    let content = model.visiblePresentation

    return HStack(alignment: .top, spacing: 11) {
      Image(systemName: content.symbol)
        .font(.system(size: 17, weight: .medium))
        .foregroundStyle(content.tone.color)
        .frame(width: 30, height: 30)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 7))

      VStack(alignment: .leading, spacing: 3) {
        Text(content.title)
          .fontWeight(.semibold)
        Text(content.detail)
          .font(.caption)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }
    }
  }

  private var permissionRecovery: some View {
    VStack(alignment: .leading, spacing: 10) {
      Button("Ava Accessibility seaded") {
        model.openAccessibilitySettings()
      }
      .buttonStyle(.borderedProminent)

      if model.showsAccessibilityInstructions {
        VStack(alignment: .leading, spacing: 4) {
          Text("1. Ava Privacy & Security → Accessibility.")
          Text("2. Lülita Automaatkorrektor sisse.")
          Text("3. Naase rakendusse ja kontrolli luba uuesti.")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
      }

      Button("Kontrolli luba uuesti") {
        Task { await model.refreshAccessibilityPermission() }
      }
      .buttonStyle(.link)
    }
    .padding(.horizontal, 14)
    .padding(.bottom, 12)
  }

  private func row(
    title: String,
    trailing: String,
    symbol: String,
    action: @escaping () -> Void
  ) -> some View {
    Button(action: action) {
      HStack {
        Image(systemName: symbol)
          .frame(width: 18)
        Text(title)
        Spacer()
        Text(trailing)
          .foregroundStyle(.secondary)
      }
      .contentShape(Rectangle())
      .padding(.horizontal, 14)
      .padding(.vertical, 10)
    }
    .buttonStyle(.plain)
  }
}

extension LanguageCheckPresentation.Tone {
  fileprivate var color: Color {
    switch self {
    case .accent: .accentColor
    case .progress: .blue
    case .success: .green
    case .caution: .orange
    case .failure: .red
    }
  }
}
