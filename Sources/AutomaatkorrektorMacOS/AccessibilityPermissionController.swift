import AppKit
import ApplicationServices

@MainActor
protocol AccessibilityPermissionControlling: AnyObject {
  func checkPermission() -> Bool
  func openSettings()
}

@MainActor
final class MacOSAccessibilityPermissionController: AccessibilityPermissionControlling {
  func checkPermission() -> Bool {
    AXIsProcessTrusted()
  }

  func openSettings() {
    guard
      let url = URL(
        string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
      )
    else {
      return
    }
    NSWorkspace.shared.open(url)
  }
}
