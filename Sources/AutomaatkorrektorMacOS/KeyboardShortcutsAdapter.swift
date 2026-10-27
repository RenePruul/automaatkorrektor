import AppKit
import Carbon.HIToolbox
import KeyboardShortcuts
import SwiftUI

extension KeyboardShortcuts.Name {
  static let checkSelectedText = Self(
    "checkSelectedText",
    initial: .init(.e, modifiers: [.command, .option])
  )
}

@MainActor
enum KeyboardShortcutConflictPolicy {
  static let required = KeyboardShortcuts.ConflictPolicy(
    menuItem: .block,
    systemShortcut: .block
  )
}

@MainActor
final class KeyboardShortcutsBackend: GlobalShortcutBackend {
  private let name: KeyboardShortcuts.Name

  init(name: KeyboardShortcuts.Name = .checkSelectedText) {
    self.name = name
  }

  func loadShortcut(default defaultShortcut: GlobalShortcut) -> GlobalShortcut? {
    KeyboardShortcuts.getShortcut(for: name).map(Self.globalShortcut)
  }

  func registerKeyUp(
    _ shortcut: GlobalShortcut,
    handler: @escaping () -> Void
  ) -> Bool {
    KeyboardShortcuts.removeHandler(for: name)
    KeyboardShortcuts.setShortcut(Self.packageShortcut(shortcut), for: name)
    KeyboardShortcuts.onKeyUp(for: name, action: handler)
    return KeyboardShortcuts.isEnabled(for: name)
  }

  func unregister() {
    KeyboardShortcuts.removeHandler(for: name)
  }

  func persist(_ shortcut: GlobalShortcut?) {
    KeyboardShortcuts.setShortcut(shortcut.map(Self.packageShortcut), for: name)
  }

  func isKnownConflict(_ shortcut: GlobalShortcut) -> Bool {
    // The package recorder checks enabled system and main-menu conflicts before
    // it calls the adapter. There is only one app shortcut in v0.1.
    false
  }

  func stop() {
    KeyboardShortcuts.removeHandler(for: name)
  }

  static func globalShortcut(_ shortcut: KeyboardShortcuts.Shortcut) -> GlobalShortcut {
    let key = shortcut.description.drop { "⌃⌥⇧⌘".contains($0) }
    return GlobalShortcut(
      key: key.isEmpty ? "�" : String(key),
      keyCode: shortcut.carbonKeyCode,
      modifiers: GlobalShortcut.Modifiers(shortcut.modifiers)
    )
  }

  private static func packageShortcut(_ shortcut: GlobalShortcut) -> KeyboardShortcuts.Shortcut {
    KeyboardShortcuts.Shortcut(
      carbonKeyCode: shortcut.keyCode,
      carbonModifiers: shortcut.modifiers.appKit.carbonValue
    )
  }
}

struct GlobalShortcutRecorder<Controller: GlobalShortcutControlling>: View {
  @ObservedObject var controller: Controller

  var body: some View {
    KeyboardShortcuts.Recorder(
      "Globaalne kiirklahv",
      name: .checkSelectedText
    ) { shortcut in
      guard let shortcut else {
        controller.clear()
        return
      }
      _ = controller.replace(with: KeyboardShortcutsBackend.globalShortcut(shortcut))
    }
    .shortcutValidation { candidate in
      let otherNames = KeyboardShortcuts.storedNames.subtracting([.checkSelectedText])
      let isDuplicate = otherNames.contains {
        KeyboardShortcuts.getShortcut(for: $0) == candidate
      }
      return isDuplicate
        ? .disallow(reason: "See kiirklahv on Automaatkorrektoris juba kasutusel.")
        : .allow
    }
    .requiredKeyboardShortcutConflictPolicy()
  }
}

extension View {
  @MainActor
  fileprivate func requiredKeyboardShortcutConflictPolicy() -> some View {
    keyboardShortcutsConflictPolicy(KeyboardShortcutConflictPolicy.required)
  }
}

extension GlobalShortcut.Modifiers {
  fileprivate init(_ flags: NSEvent.ModifierFlags) {
    self = []
    if flags.contains(.command) { insert(.command) }
    if flags.contains(.option) { insert(.option) }
    if flags.contains(.control) { insert(.control) }
    if flags.contains(.shift) { insert(.shift) }
  }

  fileprivate var appKit: NSEvent.ModifierFlags {
    var flags: NSEvent.ModifierFlags = []
    if contains(.command) { flags.insert(.command) }
    if contains(.option) { flags.insert(.option) }
    if contains(.control) { flags.insert(.control) }
    if contains(.shift) { flags.insert(.shift) }
    return flags
  }
}

extension NSEvent.ModifierFlags {
  fileprivate var carbonValue: Int {
    var result = 0
    if contains(.command) { result |= cmdKey }
    if contains(.option) { result |= optionKey }
    if contains(.control) { result |= controlKey }
    if contains(.shift) { result |= shiftKey }
    return result
  }
}
