import AppKit
import Combine

@MainActor
protocol ApplicationTerminating: AnyObject {
  func terminate()
}

@MainActor
final class NSApplicationTerminator: ApplicationTerminating {
  func terminate() {
    NSApplication.shared.terminate(nil)
  }
}

@MainActor
final class ApplicationLifecycleController: ObservableObject {
  @Published var isPopoverPresented = false

  let model: LanguageCheckViewModel
  private let terminator: any ApplicationTerminating

  init(
    model: LanguageCheckViewModel,
    terminator: any ApplicationTerminating
  ) {
    self.model = model
    self.terminator = terminator
  }

  func launch() {
    isPopoverPresented = false
  }

  func reopen() {
    isPopoverPresented = true
  }

  func popoverDidOpen() async {
    isPopoverPresented = true
    await model.refreshAccessibilityPermission()
  }

  func handleShortcut() async {
    isPopoverPresented = true
    await model.check()
  }

  func handleMenuCheck() async {
    isPopoverPresented = true
    await model.check()
  }

  func dismissPopover() async {
    isPopoverPresented = false
    await model.dismiss()
  }

  func quit() async {
    await model.dismiss()
    terminator.terminate()
  }
}
