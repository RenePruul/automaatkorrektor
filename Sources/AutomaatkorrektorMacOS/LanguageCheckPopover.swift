import AutomaatkorrektorCore
import SwiftUI

struct LanguageCheckPopover: View {
  @ObservedObject var model: LanguageCheckViewModel
  let quit: @MainActor () async -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      statusHeader
        .padding(14)

      Divider()

      row(
        title: "Kontrolli valitud teksti",
        trailing: "⌥⌘E",
        symbol: "play.fill"
      ) {
        Task { await model.check() }
      }
      .disabled(model.state == .checking)

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
    let content = model.state.presentation

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
