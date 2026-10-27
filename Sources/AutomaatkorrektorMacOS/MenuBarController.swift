import AppKit
import SwiftUI

@MainActor
protocol LanguageCheckFeedbackPresenting: AnyObject {
  var isPresented: Bool { get }

  /// Presents status without making this app active or its popover key.
  func presentWithoutActivation()
  func dismiss()
}

@MainActor
final class LanguageCheckInvocationController {
  private let lifecycle: ApplicationLifecycleController
  private let presentation: any LanguageCheckFeedbackPresenting

  init(
    lifecycle: ApplicationLifecycleController,
    presentation: any LanguageCheckFeedbackPresenting
  ) {
    self.lifecycle = lifecycle
    self.presentation = presentation
  }

  var isFeedbackPresented: Bool {
    presentation.isPresented
  }

  @discardableResult
  func openMenu() -> Task<Void, Never> {
    presentation.presentWithoutActivation()
    return Task { await lifecycle.popoverDidOpen() }
  }

  @discardableResult
  func checkFromMenu() -> Task<Void, Never> {
    Task { await lifecycle.handleMenuCheck() }
  }

  @discardableResult
  func checkFromShortcut() -> Task<Void, Never> {
    presentation.presentWithoutActivation()
    return Task { await lifecycle.handleShortcut() }
  }

  func dismissFeedback() {
    presentation.dismiss()
  }
}

@MainActor
private final class NonactivatingPopoverPresenter: LanguageCheckFeedbackPresenting {
  private let popover: NSPopover
  private let anchor: () -> NSStatusBarButton?

  init(popover: NSPopover, anchor: @escaping () -> NSStatusBarButton?) {
    self.popover = popover
    self.anchor = anchor
  }

  var isPresented: Bool {
    popover.isShown
  }

  func presentWithoutActivation() {
    guard let button = anchor() else { return }
    popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
  }

  func dismiss() {
    popover.performClose(nil)
  }
}

@MainActor
final class MenuBarController<Shortcut: GlobalShortcutControlling>: NSObject, NSPopoverDelegate {
  private let model: LanguageCheckViewModel
  private let lifecycle: ApplicationLifecycleController
  private let shortcut: Shortcut
  private let settingsWindowController: SettingsWindowController
  private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
  private let popover = NSPopover()
  private lazy var presentation = NonactivatingPopoverPresenter(
    popover: popover,
    anchor: { [weak self] in self?.statusItem.button }
  )
  private lazy var invocation = LanguageCheckInvocationController(
    lifecycle: lifecycle,
    presentation: presentation
  )

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
        checkSelectedText: { [weak self] in
          self?.invocation.checkFromMenu()
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
    invocation.isFeedbackPresented ? closePopover() : showPopover()
  }

  func showPopover() {
    invocation.openMenu()
  }

  private func closePopover() {
    invocation.dismissFeedback()
  }

  private func invokeShortcut() {
    invocation.checkFromShortcut()
  }

  func popoverDidClose(_ notification: Notification) {
    Task { await lifecycle.dismissPopover() }
  }
}
