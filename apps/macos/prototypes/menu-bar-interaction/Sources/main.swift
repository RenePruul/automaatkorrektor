import AppKit
import SwiftUI

private enum Variant: String, CaseIterable, Identifiable {
    case action = "A"
    case status = "B"
    case compact = "C"
    case refinedCompact = "D"

    var id: String { rawValue }

    var name: String {
        switch self {
        case .action: "Tegevus ees"
        case .status: "Olek ees"
        case .compact: "Minimaalne"
        case .refinedCompact: "Minimaalne 2"
        }
    }
}

private enum DemoState: String, CaseIterable, Identifiable {
    case ready = "Valmis"
    case checking = "Kontrollib"
    case estonian = "Eesti keel"
    case other = "Muu keel"
    case uncertain = "Ebaselge"
    case permission = "Luba puudub"
    case apiError = "API viga"

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .ready: "text.cursor"
        case .checking: "hourglass"
        case .estonian: "checkmark.circle.fill"
        case .other: "xmark.circle.fill"
        case .uncertain: "questionmark.circle.fill"
        case .permission: "lock.trianglebadge.exclamationmark"
        case .apiError: "wifi.exclamationmark"
        }
    }

    var color: Color {
        switch self {
        case .ready: .secondary
        case .checking: .blue
        case .estonian: .green
        case .other: .orange
        case .uncertain: .yellow
        case .permission, .apiError: .red
        }
    }

    var explanation: String {
        switch self {
        case .ready: "Vali toetatud tekstiväljal tekst ja käivita kontroll."
        case .checking: "Valitud 37 märki kontrollitakse…"
        case .estonian: "Valitud tekst on eesti keeles."
        case .other: "Valitud tekst ei ole eesti keeles."
        case .uncertain: "Keele tuvastamiseks ei ole piisavalt kindlust."
        case .permission: "Valiku lugemiseks anna Accessibility-luba."
        case .apiError: "Keeletuvastuse API-ga ei saadud ühendust."
        }
    }
}

@MainActor
private final class PrototypeModel: ObservableObject {
    @Published var variant: Variant = .action
    @Published var state: DemoState = .ready
    @Published var shortcut = "⌥⌘E"

    private var checkTask: Task<Void, Never>?

    func checkSelection() {
        checkTask?.cancel()
        state = .checking
        checkTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.2))
            guard !Task.isCancelled else { return }
            state = .estonian
        }
    }

    func cycleShortcut() {
        shortcut = shortcut == "⌥⌘E" ? "⇧⌘E" : "⌥⌘E"
    }
}

private final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
}

@main
private struct MenuBarInteractionPrototype: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = PrototypeModel()

    var body: some Scene {
        MenuBarExtra {
            PrototypeRoot(model: model)
        } label: {
            Text("ET")
                .help("Automaatkorrektor — \(model.state.rawValue)")
        }
        .menuBarExtraStyle(.window)
    }
}

private struct PrototypeRoot: View {
    @ObservedObject var model: PrototypeModel

    var body: some View {
        VStack(spacing: 0) {
            Group {
                switch model.variant {
                case .action: ActionFirstView(model: model)
                case .status: StatusFirstView(model: model)
                case .compact: CompactView(model: model)
                case .refinedCompact: RefinedCompactView(model: model)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()

            VStack(spacing: 8) {
                Picker("Katseolek", selection: $model.state) {
                    ForEach(DemoState.allCases) { state in
                        Text(state.rawValue).tag(state)
                    }
                }
                .labelsHidden()

                HStack(spacing: 8) {
                    Button { previousVariant() } label: {
                        Image(systemName: "chevron.left")
                    }
                    .buttonStyle(.borderless)

                    Picker("Variant", selection: $model.variant) {
                        ForEach(Variant.allCases) { variant in
                            Text(variant.rawValue).tag(variant)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()

                    Button { nextVariant() } label: {
                        Image(systemName: "chevron.right")
                    }
                    .buttonStyle(.borderless)
                }

                Text("\(model.variant.rawValue) · \(model.variant.name) — PROTOTÜÜP")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(12)
            .background(.bar)
        }
        .frame(width: 340, height: 390)
    }

    private func previousVariant() {
        let variants = Variant.allCases
        let current = variants.firstIndex(of: model.variant) ?? 0
        model.variant = variants[(current - 1 + variants.count) % variants.count]
    }

    private func nextVariant() {
        let variants = Variant.allCases
        let current = variants.firstIndex(of: model.variant) ?? 0
        model.variant = variants[(current + 1) % variants.count]
    }
}

private struct ActionFirstView: View {
    @ObservedObject var model: PrototypeModel

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Automaatkorrektor").font(.headline)
                    Text("Ainult sinu selge käsu peale").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Circle().fill(model.state.color).frame(width: 9, height: 9)
            }

            Button(action: model.checkSelection) {
                Label("Kontrolli valitud teksti", systemImage: "text.magnifyingglass")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 7)
            }
            .buttonStyle(.borderedProminent)
            .disabled(model.state == .checking || model.state == .permission)

            StatePanel(state: model.state)

            Spacer()
            ShortcutRow(model: model)
            UtilityRow()
        }
        .padding(18)
    }
}

private struct StatusFirstView: View {
    @ObservedObject var model: PrototypeModel

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: model.state.symbol)
                .font(.system(size: 38, weight: .medium))
                .foregroundStyle(model.state.color)
                .symbolEffect(.pulse, isActive: model.state == .checking)
            VStack(spacing: 5) {
                Text(model.state.rawValue).font(.title3.bold())
                Text(model.state.explanation)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            if model.state == .permission {
                Button("Ava Accessibility seaded") {}
                    .buttonStyle(.borderedProminent)
            } else {
                Button("Kontrolli uuesti", action: model.checkSelection)
                    .disabled(model.state == .checking)
            }

            Spacer()
            Divider()
            ShortcutRow(model: model)
            UtilityRow()
        }
        .padding(20)
    }
}

private struct CompactView: View {
    @ObservedObject var model: PrototypeModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: model.state.symbol).foregroundStyle(model.state.color)
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.state.rawValue).fontWeight(.semibold)
                    Text(model.state.explanation).font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(14)

            Divider()
            CompactButton(title: "Kontrolli valikut", trailing: model.shortcut, symbol: "text.magnifyingglass") {
                model.checkSelection()
            }
            CompactButton(title: "Muuda otseteed", trailing: "", symbol: "command") {
                model.cycleShortcut()
            }
            if model.state == .permission {
                CompactButton(title: "Ava Accessibility seaded", trailing: "", symbol: "gearshape") {}
            }
            Divider()
            CompactButton(title: "Sulge prototüüp", trailing: "⌘Q", symbol: "power") {
                NSApplication.shared.terminate(nil)
            }
            Spacer()
        }
    }
}

private struct RefinedCompactView: View {
    @ObservedObject var model: PrototypeModel

    private var title: String {
        model.state == .ready ? "Ootan valikut" : model.state.rawValue
    }

    private var symbol: String {
        model.state == .ready ? "text.magnifyingglass" : model.state.symbol
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 11) {
                Image(systemName: symbol)
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(model.state == .ready ? Color.accentColor : model.state.color)
                    .frame(width: 30, height: 30)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 7))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).fontWeight(.semibold)
                    Text(model.state.explanation).font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(14)

            Divider()
            CompactButton(title: "Kontrolli valitud teksti", trailing: model.shortcut, symbol: "play.fill") {
                model.checkSelection()
            }
            .disabled(model.state == .checking || model.state == .permission)

            if model.state == .permission {
                CompactButton(title: "Ava Accessibility seaded", trailing: "", symbol: "gearshape") {}
            } else if model.state == .apiError {
                CompactButton(title: "Proovi uuesti", trailing: "", symbol: "arrow.clockwise") {
                    model.checkSelection()
                }
            }

            CompactButton(title: "Muuda otseteed", trailing: "", symbol: "command") {
                model.cycleShortcut()
            }
            Divider()
            CompactButton(title: "Sulge prototüüp", trailing: "⌘Q", symbol: "power") {
                NSApplication.shared.terminate(nil)
            }
            Spacer()
        }
    }
}

private struct StatePanel: View {
    let state: DemoState

    var body: some View {
        HStack(alignment: .top, spacing: 11) {
            Image(systemName: state.symbol).foregroundStyle(state.color)
            VStack(alignment: .leading, spacing: 3) {
                Text(state.rawValue).fontWeight(.semibold)
                Text(state.explanation).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(12)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 10))
    }
}

private struct ShortcutRow: View {
    @ObservedObject var model: PrototypeModel

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Globaalne otsetee").font(.caption).foregroundStyle(.secondary)
                Text(model.shortcut).font(.system(.body, design: .monospaced).weight(.medium))
            }
            Spacer()
            Button("Muuda") { model.cycleShortcut() }
        }
    }
}

private struct UtilityRow: View {
    var body: some View {
        HStack {
            Button("Seaded") {}
            Spacer()
            Button("Sulge prototüüp") { NSApplication.shared.terminate(nil) }
        }
        .buttonStyle(.link)
    }
}

private struct CompactButton: View {
    let title: String
    let trailing: String
    let symbol: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Image(systemName: symbol).frame(width: 18)
                Text(title)
                Spacer()
                Text(trailing).foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
        .buttonStyle(.plain)
    }
}
