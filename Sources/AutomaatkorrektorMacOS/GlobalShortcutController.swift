import Combine
import Foundation

struct GlobalShortcut: Hashable, Sendable {
  struct Modifiers: OptionSet, Hashable, Sendable {
    let rawValue: UInt

    static let command = Self(rawValue: 1 << 0)
    static let option = Self(rawValue: 1 << 1)
    static let control = Self(rawValue: 1 << 2)
    static let shift = Self(rawValue: 1 << 3)
  }

  static let `default` = Self(key: "E", keyCode: 14, modifiers: [.command, .option])

  let key: String
  let keyCode: Int
  let modifiers: Modifiers

  init(key: String, keyCode: Int? = nil, modifiers: Modifiers) {
    self.key = key
    self.keyCode = keyCode ?? Self.commonKeyCodes[key] ?? -1
    self.modifiers = modifiers
  }

  var displayName: String {
    let symbols = [
      modifiers.contains(.control) ? "⌃" : "",
      modifiers.contains(.option) ? "⌥" : "",
      modifiers.contains(.shift) ? "⇧" : "",
      modifiers.contains(.command) ? "⌘" : "",
    ].joined()
    return symbols + key.uppercased()
  }

  private static let commonKeyCodes = [
    "E": 14,
    "K": 40,
    "U": 32,
    "Space": 49,
  ]
}

enum GlobalShortcutPhase: Sendable {
  case keyUp
}

@MainActor
protocol GlobalShortcutBackend: AnyObject {
  func loadShortcut(default defaultShortcut: GlobalShortcut) -> GlobalShortcut?
  func register(
    _ shortcut: GlobalShortcut,
    phase: GlobalShortcutPhase,
    handler: @escaping () -> Void
  ) -> Bool
  func unregister()
  func persist(_ shortcut: GlobalShortcut?)
  func isKnownConflict(_ shortcut: GlobalShortcut) -> Bool
  func stop()
}

@MainActor
protocol GlobalShortcutControlling: AnyObject {
  var shortcut: GlobalShortcut? { get }
  var registrationMessage: String? { get }
  func start(handler: @escaping () -> Void)
  func replace(with shortcut: GlobalShortcut) -> Bool
  func clear()
  func stop()
}

@MainActor
final class GlobalShortcutController: ObservableObject, GlobalShortcutControlling {
  static let failureMessage = "Kiirklahvi ei saanud aktiveerida. Vali teine kiirklahv."

  @Published private(set) var shortcut: GlobalShortcut?
  @Published private(set) var registrationMessage: String?

  private let backend: any GlobalShortcutBackend
  private var handler: (() -> Void)?

  init(backend: any GlobalShortcutBackend) {
    self.backend = backend
  }

  func start(handler: @escaping () -> Void) {
    self.handler = handler
    let storedShortcut = backend.loadShortcut(default: .default)
    shortcut = storedShortcut
    guard let storedShortcut else { return }

    if !register(storedShortcut) {
      registrationMessage = Self.failureMessage
    }
  }

  @discardableResult
  func replace(with candidate: GlobalShortcut) -> Bool {
    guard !backend.isKnownConflict(candidate) else {
      registrationMessage = Self.failureMessage
      return false
    }

    let previous = shortcut
    backend.unregister()
    guard register(candidate) else {
      if let previous {
        _ = register(previous)
      }
      registrationMessage = Self.failureMessage
      return false
    }

    shortcut = candidate
    backend.persist(candidate)
    registrationMessage = nil
    return true
  }

  func clear() {
    backend.unregister()
    backend.persist(nil)
    shortcut = nil
    registrationMessage = nil
  }

  func stop() {
    handler = nil
    backend.stop()
  }

  private func register(_ shortcut: GlobalShortcut) -> Bool {
    guard let handler else { return false }
    return backend.register(shortcut, phase: .keyUp, handler: handler)
  }
}
