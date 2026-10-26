import ApplicationServices
import AutomaatkorrektorCore
import Foundation

enum AccessibilitySelectionError: Error, Sendable, Equatable {
  case permissionRequired
  case noFocusedControl
  case protectedContent
  case unsupportedTextField
  case readOnly
  case noSelection
  case invalidSelection
  case selectionTooLarge
  case focusChanged
  case targetUnavailable
  case unsupportedApplication
  case unknown
}

struct AXElementID: Sendable, Equatable {
  let processIdentifier: pid_t
  let identity: UInt64
}

struct AXTextRange: Sendable, Equatable {
  let location: Int
  let length: Int
}

enum AXOptionalMetadata<Value: Sendable & Equatable>: Sendable, Equatable {
  case absent
  case value(Value)
  case malformed
}

struct AXSnapshot: Sendable, Equatable {
  let role: String
  let subrole: AXOptionalMetadata<String>
  let containsProtectedContent: AXOptionalMetadata<Bool>
  var enabled: AXOptionalMetadata<Bool>
  var focused: AXOptionalMetadata<Bool>
  let attributeNames: Set<String>
  let isValueSettable: Bool
}

protocol AXReading: Sendable {
  func isTrusted() async -> Bool
  func focusedElement() async throws -> AXElementID
  func snapshot(of element: AXElementID) async throws -> AXSnapshot
  func selectedRange(of element: AXElementID) async throws -> AXTextRange
  func selectedText(of element: AXElementID) async throws -> String
  func sameElement(_ lhs: AXElementID, _ rhs: AXElementID) async -> Bool
  func release(_ element: AXElementID) async
}

actor AccessibilitySelectedTextReader: SelectionReading {
  static let maximumSelectionLength = 10_000

  private let accessibility: any AXReading

  init(accessibility: any AXReading = SystemAXReader()) {
    self.accessibility = accessibility
  }

  func readSelectedText() async throws -> SelectedText {
    try Task.checkCancellation()
    guard await accessibility.isTrusted() else {
      throw AccessibilitySelectionError.permissionRequired
    }

    let initialElement = try await accessibility.focusedElement()
    do {
      let initialSnapshot = try await accessibility.snapshot(of: initialElement)
      try Self.requireEligible(initialSnapshot)

      let range = try await accessibility.selectedRange(of: initialElement)
      guard range.location >= 0, range.length >= 0 else {
        throw AccessibilitySelectionError.invalidSelection
      }
      guard range.length > 0 else {
        throw AccessibilitySelectionError.noSelection
      }
      guard range.length <= Self.maximumSelectionLength else {
        throw AccessibilitySelectionError.selectionTooLarge
      }

      try Task.checkCancellation()
      let value = try await accessibility.selectedText(of: initialElement)
      try Task.checkCancellation()

      let currentElement = try await accessibility.focusedElement()
      do {
        guard await accessibility.sameElement(initialElement, currentElement) else {
          throw AccessibilitySelectionError.focusChanged
        }

        let currentSnapshot = try await accessibility.snapshot(of: currentElement)
        do {
          try Self.requireEligible(currentSnapshot)
        } catch {
          throw AccessibilitySelectionError.focusChanged
        }
        guard currentSnapshot == initialSnapshot else {
          throw AccessibilitySelectionError.focusChanged
        }

        try Task.checkCancellation()
        await accessibility.release(currentElement)
        await accessibility.release(initialElement)
        return SelectedText(value)
      } catch {
        await accessibility.release(currentElement)
        throw error
      }
    } catch {
      await accessibility.release(initialElement)
      throw error
    }
  }

  private static func requireEligible(_ snapshot: AXSnapshot) throws {
    if snapshot.role == kAXSecureTextFieldSubrole as String
      || snapshot.subrole == .value(kAXSecureTextFieldSubrole as String)
    {
      throw AccessibilitySelectionError.protectedContent
    }

    switch snapshot.containsProtectedContent {
    case .value(true):
      throw AccessibilitySelectionError.protectedContent
    case .malformed:
      throw AccessibilitySelectionError.unknown
    case .absent, .value(false):
      break
    }

    if snapshot.role == kAXTextFieldRole {
      guard
        snapshot.subrole == .absent
          || snapshot.subrole == .value(kAXSearchFieldSubrole)
      else {
        throw AccessibilitySelectionError.unsupportedTextField
      }
    } else if snapshot.role == kAXTextAreaRole {
      guard snapshot.subrole == .absent else {
        throw AccessibilitySelectionError.unsupportedTextField
      }
    } else {
      throw AccessibilitySelectionError.unsupportedTextField
    }

    switch snapshot.enabled {
    case .value(false):
      throw AccessibilitySelectionError.unsupportedTextField
    case .malformed:
      throw AccessibilitySelectionError.unknown
    case .absent, .value(true):
      break
    }

    switch snapshot.focused {
    case .value(false):
      throw AccessibilitySelectionError.focusChanged
    case .malformed:
      throw AccessibilitySelectionError.unknown
    case .absent, .value(true):
      break
    }

    guard snapshot.attributeNames.contains(kAXSelectedTextAttribute as String),
      snapshot.attributeNames.contains(kAXSelectedTextRangeAttribute as String)
    else {
      throw AccessibilitySelectionError.unsupportedTextField
    }
    guard snapshot.isValueSettable else {
      throw AccessibilitySelectionError.readOnly
    }
  }
}

actor SystemAXReader: AXReading {
  private var nextIdentity: UInt64 = 0
  private var elements: [UInt64: AXUIElement] = [:]

  func isTrusted() -> Bool {
    AXIsProcessTrusted()
  }

  func focusedElement() throws -> AXElementID {
    let systemWide = AXUIElementCreateSystemWide()
    let element = try copyElementAttribute(kAXFocusedUIElementAttribute, from: systemWide)
    var processIdentifier: pid_t = 0
    try map(AXUIElementGetPid(element, &processIdentifier))

    nextIdentity &+= 1
    elements[nextIdentity] = element
    return AXElementID(processIdentifier: processIdentifier, identity: nextIdentity)
  }

  func snapshot(of elementID: AXElementID) throws -> AXSnapshot {
    let element = try resolve(elementID)
    let role = try requiredStringAttribute(kAXRoleAttribute, from: element)
    let subrole = try optionalStringAttribute(kAXSubroleAttribute, from: element)
    let protected = try optionalBooleanAttribute(
      "AXContainsProtectedContent",
      from: element
    )
    let enabled = try optionalBooleanAttribute(kAXEnabledAttribute, from: element)
    let focused = try optionalBooleanAttribute(kAXFocusedAttribute, from: element)

    var copiedNames: CFArray?
    try map(AXUIElementCopyAttributeNames(element, &copiedNames))
    guard let names = copiedNames as? [String] else {
      throw AccessibilitySelectionError.unknown
    }

    var settable = DarwinBoolean(false)
    try map(AXUIElementIsAttributeSettable(element, kAXValueAttribute as CFString, &settable))

    return AXSnapshot(
      role: role,
      subrole: subrole,
      containsProtectedContent: protected,
      enabled: enabled,
      focused: focused,
      attributeNames: Set(names),
      isValueSettable: settable.boolValue
    )
  }

  func selectedRange(of elementID: AXElementID) throws -> AXTextRange {
    let element = try resolve(elementID)
    var copiedValue: CFTypeRef?
    try map(
      AXUIElementCopyAttributeValue(
        element, kAXSelectedTextRangeAttribute as CFString, &copiedValue))
    guard let value = copiedValue, CFGetTypeID(value) == AXValueGetTypeID() else {
      throw AccessibilitySelectionError.invalidSelection
    }
    let axValue = unsafeDowncast(value, to: AXValue.self)
    guard AXValueGetType(axValue) == .cfRange else {
      throw AccessibilitySelectionError.invalidSelection
    }
    var range = CFRange()
    guard AXValueGetValue(axValue, .cfRange, &range) else {
      throw AccessibilitySelectionError.invalidSelection
    }
    return AXTextRange(location: range.location, length: range.length)
  }

  func selectedText(of elementID: AXElementID) throws -> String {
    let element = try resolve(elementID)
    var copiedValue: CFTypeRef?
    try map(
      AXUIElementCopyAttributeValue(element, kAXSelectedTextAttribute as CFString, &copiedValue))
    guard let value = copiedValue, CFGetTypeID(value) == CFStringGetTypeID() else {
      throw AccessibilitySelectionError.unknown
    }
    return value as! String
  }

  func sameElement(_ lhs: AXElementID, _ rhs: AXElementID) -> Bool {
    guard lhs.processIdentifier == rhs.processIdentifier,
      let left = elements[lhs.identity],
      let right = elements[rhs.identity]
    else { return false }
    return CFEqual(left, right)
  }

  func release(_ element: AXElementID) {
    elements.removeValue(forKey: element.identity)
  }

  private func resolve(_ id: AXElementID) throws -> AXUIElement {
    guard let element = elements[id.identity] else {
      throw AccessibilitySelectionError.focusChanged
    }
    return element
  }

  private func copyElementAttribute(
    _ attribute: String,
    from element: AXUIElement
  ) throws -> AXUIElement {
    var copiedValue: CFTypeRef?
    let error = AXUIElementCopyAttributeValue(element, attribute as CFString, &copiedValue)
    if error == .noValue { throw AccessibilitySelectionError.noFocusedControl }
    try map(error)
    guard let value = copiedValue, CFGetTypeID(value) == AXUIElementGetTypeID() else {
      throw AccessibilitySelectionError.unknown
    }
    return unsafeDowncast(value, to: AXUIElement.self)
  }

  private func requiredStringAttribute(
    _ attribute: String,
    from element: AXUIElement
  ) throws -> String {
    var copiedValue: CFTypeRef?
    try map(AXUIElementCopyAttributeValue(element, attribute as CFString, &copiedValue))
    guard let value = copiedValue, CFGetTypeID(value) == CFStringGetTypeID() else {
      throw AccessibilitySelectionError.unknown
    }
    return value as! String
  }

  private func optionalStringAttribute(
    _ attribute: String,
    from element: AXUIElement
  ) throws -> AXOptionalMetadata<String> {
    var copiedValue: CFTypeRef?
    let error = AXUIElementCopyAttributeValue(element, attribute as CFString, &copiedValue)
    if error == .noValue || error == .attributeUnsupported { return .absent }
    try map(error)
    guard let value = copiedValue, CFGetTypeID(value) == CFStringGetTypeID() else {
      return .malformed
    }
    return .value(value as! String)
  }

  private func optionalBooleanAttribute(
    _ attribute: String,
    from element: AXUIElement
  ) throws -> AXOptionalMetadata<Bool> {
    var copiedValue: CFTypeRef?
    let error = AXUIElementCopyAttributeValue(element, attribute as CFString, &copiedValue)
    if error == .noValue || error == .attributeUnsupported { return .absent }
    try map(error)
    guard let value = copiedValue, CFGetTypeID(value) == CFBooleanGetTypeID() else {
      return .malformed
    }
    return .value(CFBooleanGetValue(unsafeDowncast(value, to: CFBoolean.self)))
  }

  private func map(_ error: AXError) throws {
    switch error {
    case .success:
      return
    case .apiDisabled:
      throw AccessibilitySelectionError.permissionRequired
    case .noValue:
      throw AccessibilitySelectionError.unknown
    case .attributeUnsupported, .parameterizedAttributeUnsupported:
      throw AccessibilitySelectionError.unsupportedTextField
    case .invalidUIElement:
      throw AccessibilitySelectionError.focusChanged
    case .cannotComplete:
      throw AccessibilitySelectionError.targetUnavailable
    case .notImplemented:
      throw AccessibilitySelectionError.unsupportedApplication
    default:
      throw AccessibilitySelectionError.unknown
    }
  }
}
