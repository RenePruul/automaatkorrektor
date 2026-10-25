import AppKit
import ApplicationServices
import Foundation

private let maximumSelectionLength = 10_000

private enum ProbeFailure: Error, CustomStringConvertible {
    case permissionRequired
    case noFocusedControl
    case protected
    case unsupported(String)
    case readOnly
    case noSelection
    case invalidSelection
    case focusChanged
    case targetUnavailable(String)
    case unknown(String)

    var description: String {
        switch self {
        case .permissionRequired: "permissionRequired"
        case .noFocusedControl: "noFocusedControl"
        case .protected: "protected"
        case let .unsupported(reason): "unsupported: \(reason)"
        case .readOnly: "readOnly"
        case .noSelection: "noSelection"
        case .invalidSelection: "invalidSelection"
        case .focusChanged: "focusChanged"
        case let .targetUnavailable(context): "targetUnavailable: \(context)"
        case let .unknown(reason): "unknown: \(reason)"
        }
    }
}

private struct Metadata {
    let pid: pid_t
    let bundleIdentifier: String?
    let role: String
    let subrole: String?
}

private func mapAXError(_ error: AXError, context: String) -> ProbeFailure {
    switch error {
    case .apiDisabled:
        return .permissionRequired
    case .invalidUIElement:
        return .focusChanged
    case .cannotComplete:
        return .targetUnavailable(context)
    case .notImplemented:
        return .unsupported("Accessibility API is not implemented")
    default:
        return .unknown("\(context) failed with AXError \(error.rawValue)")
    }
}

private func copyAttribute(
    _ element: AXUIElement,
    _ attribute: CFString,
    optional: Bool = false
) throws -> CFTypeRef? {
    var value: CFTypeRef?
    let error = AXUIElementCopyAttributeValue(element, attribute, &value)
    if error == .success {
        return value
    }
    if optional && (error == .noValue || error == .attributeUnsupported) {
        return nil
    }
    if error == .noValue {
        throw ProbeFailure.noFocusedControl
    }
    if error == .attributeUnsupported {
        throw ProbeFailure.unsupported("missing \(attribute)")
    }
    throw mapAXError(error, context: "reading \(attribute)")
}

private func stringAttribute(
    _ element: AXUIElement,
    _ attribute: CFString,
    optional: Bool = false
) throws -> String? {
    guard let value = try copyAttribute(element, attribute, optional: optional) else {
        return nil
    }
    guard CFGetTypeID(value) == CFStringGetTypeID() else {
        throw ProbeFailure.unknown("\(attribute) has the wrong type")
    }
    return value as? String
}

private func boolAttribute(
    _ element: AXUIElement,
    _ attribute: CFString,
    optional: Bool = false
) throws -> Bool? {
    guard let value = try copyAttribute(element, attribute, optional: optional) else {
        return nil
    }
    guard CFGetTypeID(value) == CFBooleanGetTypeID() else {
        throw ProbeFailure.unknown("\(attribute) has the wrong type")
    }
    return CFBooleanGetValue((value as! CFBoolean))
}

private func elementAttribute(
    _ element: AXUIElement,
    _ attribute: CFString
) throws -> AXUIElement {
    guard let value = try copyAttribute(element, attribute) else {
        throw ProbeFailure.noFocusedControl
    }
    guard CFGetTypeID(value) == AXUIElementGetTypeID() else {
        throw ProbeFailure.unknown("\(attribute) has the wrong type")
    }
    return (value as! AXUIElement)
}

private func pid(of element: AXUIElement) throws -> pid_t {
    var value: pid_t = 0
    let error = AXUIElementGetPid(element, &value)
    guard error == .success else {
        throw mapAXError(error, context: "reading PID")
    }
    return value
}

private func focusedPair() throws -> (application: AXUIElement, element: AXUIElement) {
    // Chromium creates its native accessibility tree on demand. Touching the
    // frontmost application's role is metadata-only and activates that tree
    // before asking macOS for the focused control.
    if let frontmost = NSWorkspace.shared.frontmostApplication {
        let candidate = AXUIElementCreateApplication(frontmost.processIdentifier)
        _ = try? copyAttribute(candidate, kAXRoleAttribute as CFString)
        Thread.sleep(forTimeInterval: 0.1)
    }

    let system = AXUIElementCreateSystemWide()
    let element = try elementAttribute(system, kAXFocusedUIElementAttribute as CFString)
    let application = AXUIElementCreateApplication(try pid(of: element))
    return (application, element)
}

private func metadataGate(
    application: AXUIElement,
    element: AXUIElement
) throws -> Metadata {
    let applicationPID = try pid(of: application)
    let elementPID = try pid(of: element)
    guard applicationPID == elementPID else {
        throw ProbeFailure.focusChanged
    }

    guard let role = try stringAttribute(element, kAXRoleAttribute as CFString) else {
        throw ProbeFailure.unsupported("missing role")
    }
    let subrole = try stringAttribute(element, kAXSubroleAttribute as CFString, optional: true)

    let secure = kAXSecureTextFieldSubrole as String
    if role == secure || subrole == secure {
        throw ProbeFailure.protected
    }
    if try boolAttribute(
        element,
        "AXContainsProtectedContent" as CFString,
        optional: true
    ) == true {
        throw ProbeFailure.protected
    }

    let textField = kAXTextFieldRole as String
    let textArea = kAXTextAreaRole as String
    let searchField = kAXSearchFieldSubrole as String
    switch (role, subrole) {
    case (textField, nil), (textField, searchField), (textArea, nil):
        break
    default:
        throw ProbeFailure.unsupported("role=\(role), subrole=\(subrole ?? "none")")
    }

    let enabled = try boolAttribute(
        element,
        kAXEnabledAttribute as CFString,
        optional: true
    )
    if enabled == false {
        throw ProbeFailure.unsupported(
            "role=\(role), subrole=\(subrole ?? "none"), AXEnabled=false"
        )
    }
    let focused = try boolAttribute(
        element,
        kAXFocusedAttribute as CFString,
        optional: true
    )
    if focused == false {
        throw ProbeFailure.focusChanged
    }

    var names: CFArray?
    let namesError = AXUIElementCopyAttributeNames(element, &names)
    guard namesError == .success else {
        throw mapAXError(namesError, context: "reading attribute names")
    }
    guard let attributeNames = names as? [String] else {
        throw ProbeFailure.unknown("attribute names have the wrong type")
    }
    let supported = Set(attributeNames)
    guard supported.contains(kAXSelectedTextAttribute as String),
          supported.contains(kAXSelectedTextRangeAttribute as String)
    else {
        throw ProbeFailure.unsupported("selected-text capabilities are missing")
    }

    var settable = DarwinBoolean(false)
    let settableError = AXUIElementIsAttributeSettable(
        element,
        kAXValueAttribute as CFString,
        &settable
    )
    guard settableError == .success else {
        throw mapAXError(settableError, context: "checking editability")
    }
    guard settable.boolValue else {
        throw ProbeFailure.readOnly
    }

    let app = NSRunningApplication(processIdentifier: applicationPID)
    return Metadata(
        pid: applicationPID,
        bundleIdentifier: app?.bundleIdentifier,
        role: role,
        subrole: subrole
    )
}

private func selectedRange(of element: AXUIElement) throws -> CFRange {
    guard let value = try copyAttribute(element, kAXSelectedTextRangeAttribute as CFString),
          CFGetTypeID(value) == AXValueGetTypeID(),
          AXValueGetType(value as! AXValue) == .cfRange
    else {
        throw ProbeFailure.invalidSelection
    }
    var range = CFRange()
    guard AXValueGetValue(value as! AXValue, .cfRange, &range), range.location >= 0 else {
        throw ProbeFailure.invalidSelection
    }
    guard range.length > 0 else {
        throw ProbeFailure.noSelection
    }
    guard range.length <= maximumSelectionLength else {
        throw ProbeFailure.invalidSelection
    }
    return range
}

private func selectedText(of element: AXUIElement) throws -> String {
    guard let text = try stringAttribute(element, kAXSelectedTextAttribute as CFString) else {
        throw ProbeFailure.invalidSelection
    }
    return text
}

private func promptForTrust() -> Bool {
    let key = "AXTrustedCheckOptionPrompt"
    return AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
}

private func delayFromArguments() -> Int {
    guard let index = CommandLine.arguments.firstIndex(of: "--delay"),
          CommandLine.arguments.indices.contains(index + 1),
          let delay = Int(CommandLine.arguments[index + 1]),
          delay > 0
    else {
        return 8
    }
    return delay
}

private func emit(_ object: [String: Any]) {
    guard let data = try? JSONSerialization.data(
        withJSONObject: object,
        options: [.prettyPrinted, .sortedKeys]
    ), let output = String(data: data, encoding: .utf8) else {
        print("{\"result\":\"unknown\"}")
        return
    }
    print(output)
}

_ = NSApplication.shared

guard promptForTrust() else {
    emit(["result": ProbeFailure.permissionRequired.description])
    exit(2)
}

let delay = delayFromArguments()
print("Select known text in the target application. Capturing in \(delay) seconds…")
for remaining in stride(from: delay, through: 1, by: -1) {
    print("\(remaining)…")
    fflush(stdout)
    Thread.sleep(forTimeInterval: 1)
}

do {
    let first = try focusedPair()
    let metadata = try metadataGate(application: first.application, element: first.element)
    let range = try selectedRange(of: first.element)
    let text = try selectedText(of: first.element)

    let second = try focusedPair()
    _ = try metadataGate(application: second.application, element: second.element)
    guard metadata.pid == (try pid(of: second.element)),
          CFEqual(first.element, second.element)
    else {
        throw ProbeFailure.focusChanged
    }

    emit([
        "application": metadata.bundleIdentifier ?? "unknown",
        "rangeLength": range.length,
        "result": "selected",
        "role": metadata.role,
        "subrole": metadata.subrole ?? "none",
        "textCharacterCount": text.count,
    ])
} catch let failure as ProbeFailure {
    emit(["result": failure.description])
    exit(1)
} catch {
    emit(["result": "unknown: \(type(of: error))"])
    exit(1)
}
