import AppKit
import SwiftUI

@MainActor
final class MenuBarController: NSObject, NSPopoverDelegate {
  private let model: LanguageCheckViewModel
  private let lifecycle: ApplicationLifecycleController
  private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
  private let popover = NSPopover()

  init(
    model: LanguageCheckViewModel,
    lifecycle: ApplicationLifecycleController
  ) {
    self.model = model
    self.lifecycle = lifecycle
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

    popover.behavior = .transient
    popover.delegate = self
    popover.contentSize = NSSize(width: 330, height: 250)
    popover.contentViewController = NSHostingController(
      rootView: LanguageCheckPopover(
        model: model,
        quit: { [weak lifecycle] in
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
    guard let button = statusItem.button else { return }
    popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
    popover.contentViewController?.view.window?.makeKey()
    Task { await lifecycle.popoverDidOpen() }
  }

  func applicationDidBecomeActive() async {
    await lifecycle.applicationDidBecomeActive()
  }

  private func closePopover() {
    popover.performClose(nil)
  }

  func popoverDidClose(_ notification: Notification) {
    Task { await lifecycle.dismissPopover() }
  }
}
