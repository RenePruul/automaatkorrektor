import AppKit
import SwiftUI

private enum PermissionVariant: String, CaseIterable, Identifiable {
    case inline = "A"
    case guided = "B"
    case justInTime = "C"

    var id: String { rawValue }

    var name: String {
        switch self {
        case .inline: "Kohe nähtav"
        case .guided: "Juhendatud"
        case .justInTime: "Vajaduse hetkel"
        }
    }
}

private enum PermissionState: String, CaseIterable, Identifiable {
    case denied = "Luba puudub"
    case settingsOpen = "Seaded avatud"
    case granted = "Luba olemas"
    case revoked = "Luba eemaldati töötamise ajal"

    var id: String { rawValue }

    var hasAccess: Bool { self == .granted }
}

@MainActor
private final class PrototypeModel: ObservableObject {
    @Published var variant: PermissionVariant = .inline
    @Published var permission: PermissionState = .denied {
        didSet {
            if permission.hasAccess { attemptedCheck = false }
        }
    }
    @Published var attemptedCheck = false

    func checkSelection() {
        attemptedCheck = !permission.hasAccess
    }

    func openSettings() {
        permission = .settingsOpen
    }

    func recheckPermission() {
        if permission == .settingsOpen {
            permission = .denied
        }
    }
}

private final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
}

@main
private struct PermissionOnboardingPrototype: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = PrototypeModel()

    var body: some Scene {
        MenuBarExtra {
            PrototypeRoot(model: model)
        } label: {
            Text("ET")
                .help("Automaatkorrektor — permission prototype")
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
                case .inline:
                    InlinePermissionView(model: model)
                case .guided:
                    GuidedPermissionView(model: model)
                case .justInTime:
                    JustInTimePermissionView(model: model)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()
            prototypeControls
        }
        .frame(width: 360, height: 430)
    }

    private var prototypeControls: some View {
        VStack(spacing: 8) {
            Picker("Loa katseolek", selection: $model.permission) {
                ForEach(PermissionState.allCases) { state in
                    Text(state.rawValue).tag(state)
                }
            }
            .labelsHidden()

            Picker("Variant", selection: $model.variant) {
                ForEach(PermissionVariant.allCases) { variant in
                    Text(variant.rawValue).tag(variant)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            Text("\(model.variant.rawValue) · \(model.variant.name) — PROTOTÜÜP")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .background(.bar)
    }
}

private struct InlinePermissionView: View {
    @ObservedObject var model: PrototypeModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if model.permission.hasAccess {
                ReadyForWorkHeader()
            } else if model.permission == .settingsOpen {
                SettingsInstructions()
            } else {
                PermissionHeader(state: model.permission, compact: true)
            }
            Divider()

            if model.permission.hasAccess {
                CheckRow(action: model.checkSelection)
            } else if model.permission == .settingsOpen {
                ActionRow("Ava seaded uuesti", symbol: "gearshape", action: model.openSettings)
                ActionRow("Kontrolli luba uuesti", symbol: "arrow.clockwise", action: model.recheckPermission)
            } else {
                ActionRow("Ava Accessibility seaded", symbol: "gearshape", action: model.openSettings)
                ActionRow("Kontrolli luba uuesti", symbol: "arrow.clockwise", action: model.recheckPermission)
            }

            SecondaryRows()
            Spacer()
        }
    }
}

private struct GuidedPermissionView: View {
    @ObservedObject var model: PrototypeModel

    var body: some View {
        if model.permission.hasAccess {
            VStack(alignment: .leading, spacing: 0) {
                WaitingHeader()
                Divider()
                CheckRow(action: model.checkSelection)
                SecondaryRows()
                Spacer()
            }
        } else {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 12) {
                    Image(systemName: "hand.raised.fill")
                        .font(.system(size: 27))
                        .foregroundStyle(.blue)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Luba valitud teksti lugemine").font(.headline)
                        Text(permissionSubtitle(model.permission))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                VStack(alignment: .leading, spacing: 10) {
                    PrivacyPoint(symbol: "cursorarrow.click.2", text: "Ainult siis, kui käivitad kontrolli")
                    PrivacyPoint(symbol: "selection.pin.in.out", text: "Ainult sinu selgelt valitud tekst")
                    PrivacyPoint(symbol: "lock.shield", text: "Kaitstud ja tundmatud väljad blokeeritakse")
                }

                Button("Ava Accessibility seaded", action: model.openSettings)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .frame(maxWidth: .infinity)

                Button("Kontrolli luba uuesti", action: model.recheckPermission)
                    .frame(maxWidth: .infinity)

                Spacer()
                Button("Sulge prototüüp") { NSApp.terminate(nil) }
                    .buttonStyle(.link)
            }
            .padding(18)
        }
    }
}

private struct JustInTimePermissionView: View {
    @ObservedObject var model: PrototypeModel

    private var mustShowRecovery: Bool {
        model.permission == .revoked || model.permission == .settingsOpen || model.attemptedCheck
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if mustShowRecovery && !model.permission.hasAccess {
                PermissionHeader(state: model.permission, compact: true)
            } else {
                WaitingHeader()
            }
            Divider()

            if mustShowRecovery && !model.permission.hasAccess {
                ActionRow("Ava Accessibility seaded", symbol: "gearshape", action: model.openSettings)
                ActionRow("Kontrolli luba uuesti", symbol: "arrow.clockwise", action: model.recheckPermission)
            } else {
                CheckRow(action: model.checkSelection)
            }

            SecondaryRows()
            Spacer()
        }
    }
}

private struct WaitingHeader: View {
    var body: some View {
        HStack(spacing: 11) {
            Image(systemName: "text.magnifyingglass")
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(.blue)
                .frame(width: 30, height: 30)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 7))
            VStack(alignment: .leading, spacing: 2) {
                Text("Ootan valikut").fontWeight(.semibold)
                Text("Vali toetatud tekstiväljal tekst ja käivita kontroll.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
    }
}

private struct ReadyForWorkHeader: View {
    var body: some View {
        HStack(spacing: 11) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 19, weight: .medium))
                .foregroundStyle(.green)
                .frame(width: 30, height: 30)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 7))
            VStack(alignment: .leading, spacing: 2) {
                Text("Programm on tööks valmis").fontWeight(.semibold)
                Text("Vali tekst ja käivita eesti keele kontroll.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
    }
}

private struct SettingsInstructions: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(spacing: 11) {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(.blue)
                    .frame(width: 30, height: 30)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 7))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Anna Accessibility-luba").fontWeight(.semibold)
                    Text("Jätka avatud System Settingsi aknas.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("1. Ava Privacy & Security → Accessibility")
                Text("2. Leia nimekirjast Automaatkorrektor")
                Text("3. Lülita Automaatkorrektori juurdepääs sisse")
                Text("4. Tule siia tagasi ja kontrolli luba uuesti")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.leading, 41)
        }
        .padding(14)
    }
}

private struct PermissionHeader: View {
    let state: PermissionState
    let compact: Bool

    var body: some View {
        HStack(spacing: 11) {
            Image(systemName: state == .settingsOpen ? "hourglass" : "lock.trianglebadge.exclamationmark")
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(state == .settingsOpen ? .blue : .orange)
                .frame(width: 30, height: 30)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 7))
            VStack(alignment: .leading, spacing: 2) {
                Text(state == .settingsOpen ? "Ootan luba" : "Accessibility-luba puudub")
                    .fontWeight(.semibold)
                Text(permissionSubtitle(state))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(compact ? 14 : 18)
    }
}

private struct CheckRow: View {
    let action: () -> Void

    var body: some View {
        ActionRow("Kontrolli valitud teksti", trailing: "⌥⌘E", symbol: "play.fill", action: action)
    }
}

private struct SecondaryRows: View {
    var body: some View {
        Group {
            ActionRow("Muuda otseteed", symbol: "command") {}
            Divider()
            ActionRow("Sulge prototüüp", trailing: "⌘Q", symbol: "power") {
                NSApp.terminate(nil)
            }
        }
    }
}

private struct ActionRow: View {
    let title: String
    let trailing: String
    let symbol: String
    let action: () -> Void

    init(_ title: String, trailing: String = "", symbol: String, action: @escaping () -> Void) {
        self.title = title
        self.trailing = trailing
        self.symbol = symbol
        self.action = action
    }

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

private struct PrivacyPoint: View {
    let symbol: String
    let text: String

    var body: some View {
        Label(text, systemImage: symbol)
            .font(.callout)
    }
}

private func permissionSubtitle(_ state: PermissionState) -> String {
    switch state {
    case .denied:
        "Luba pole antud. Teksti ei loetud ega saadetud."
    case .settingsOpen:
        "Anna luba System Settingsis ja tule tagasi."
    case .granted:
        "Programm on tööks valmis."
    case .revoked:
        "Valitud teksti ei saa ilma loata lugeda."
    }
}
