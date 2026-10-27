import AppKit
import SwiftUI

@MainActor
final class MenuBarController<Shortcut: GlobalShortcutControlling>: NSObject, NSPopoverDelegate {
  private let model: LanguageCheckViewModel
  private let lifecycle: ApplicationLifecycleController
  private let shortcut: Shortcut
  private let settingsWindowController: SettingsWindowController
  private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
  private let popover = NSPopover()

  init(
    model: LanguageCheckViewModel,
    lifecycle: ApplicationLifecycleController,
    settings: APISettingsStore,
    shortcut: Shortcut
  ) {
    self.model = model
    self.lifecycle = lifecycle
    self.shortcut = shortcut
    settingsWindowController = SettingsWindowController(
      settings: settings,
      shortcut: shortcut
    )
    super.init()
  }

  func install() {
    guard let button = statusItem.button else { return }
    button.image = NSImage(
      systemSymbolName: "text.magnifyingglass",
      accessibilityDescription: "Automaatkorrektor"
    )
    button.target = self
    button.action = #selector(togglePopover)

    shortcut.start { [weak self] in
      self?.invokeShortcut()
    }

    popover.behavior = .transient
    popover.delegate = self
    popover.contentSize = NSSize(width: 330, height: 250)
    popover.contentViewController = NSHostingController(
      rootView: LanguageCheckPopover(
        model: model,
        shortcut: shortcut,
        showSettings: { [weak self] in
          self?.settingsWindowController.show()
        },
        quit: { [weak lifecycle, weak shortcut] in
          shortcut?.stop()
          guard let lifecycle else { return }
          await lifecycle.quit()
        }
      )
    )
  }

  @objc private func togglePopover() {
    popover.isShown ? closePopover() : showPopover()
  }

  func showPopover() {
    showPopover(refreshPermission: true)
  }

  private func showPopover(refreshPermission: Bool) {
    guard let button = statusItem.button else { return }
    popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
    popover.contentViewController?.view.window?.makeKey()
    if refreshPermission {
      Task { await lifecycle.popoverDidOpen() }
    }
  }

  private func closePopover() {
    popover.performClose(nil)
  }

  private func invokeShortcut() {
    showPopover(refreshPermission: false)
    Task { await lifecycle.handleShortcut() }
  }

  func popoverDidClose(_ notification: Notification) {
    Task { await lifecycle.dismissPopover() }
  }
}
