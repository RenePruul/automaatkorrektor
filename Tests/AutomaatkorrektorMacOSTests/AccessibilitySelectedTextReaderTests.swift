import AutomaatkorrektorCore
import Foundation
import Testing

@testable import AutomaatkorrektorMacOS

@Suite("Selected text Accessibility adapter")
struct AccessibilitySelectedTextReaderTests {
  @Test("an eligible TextEdit selection reaches the language detector once")
  func textEditSelectionEndToEnd() async throws {
    let accessibility = AXReaderSpy(
      snapshots: [.textEditTextArea, .textEditTextArea],
      selectedRange: AXTextRange(location: 4, length: 13),
      selectedText: "Tere maailm!"
    )
    let detector = SelectionRecordingDetector()
    let useCase = LanguageCheckUseCase(
      selectionReader: AccessibilitySelectedTextReader(accessibility: accessibility),
      languageDetector: detector
    )

    let verdict = try await useCase.check()

    #expect(verdict == .estonian)
    #expect(await detector.receivedTexts == ["Tere maailm!"])
    #expect(accessibility.selectedRangeReadCount == 1)
    #expect(accessibility.selectedTextReadCount == 1)
    #expect(accessibility.valueReadCount == 0)
    #expect(accessibility.retainedElementCount == 0)
  }

  @Test(
    "only the exact v0.1 application allowlist may return selected text",
    arguments: [
      "com.apple.TextEdit",
      "com.apple.Safari",
      "com.google.Chrome",
    ]
  )
  func exactSupportedApplicationAllowlist(bundleIdentifier: String) async throws {
    let accessibility = AXReaderSpy(
      snapshots: [.textEditTextArea, .textEditTextArea],
      applicationIdentities: [
        AXApplicationIdentity(processIdentifier: 42, bundleIdentifier: bundleIdentifier),
        AXApplicationIdentity(processIdentifier: 42, bundleIdentifier: bundleIdentifier),
      ]
    )

    let selectedText = try await AccessibilitySelectedTextReader(
      accessibility: accessibility
    ).readSelectedText()

    #expect(selectedText == SelectedText("Tere"))
    #expect(accessibility.applicationIdentityLookupCount == 2)
    #expect(accessibility.selectedRangeReadCount == 1)
    #expect(accessibility.selectedTextReadCount == 1)
  }

  @Test(
    "unsupported, missing, and malformed application identities fail before content access",
    arguments: UnsupportedApplicationFixture.cases
  )
  fileprivate func unsupportedApplicationIdentityFailsClosed(
    fixture: UnsupportedApplicationFixture
  ) async {
    let accessibility = AXReaderSpy(
      snapshots: [.textEditTextArea],
      applicationIdentities: [fixture.identity]
    )
    let detector = SelectionRecordingDetector()
    let useCase = LanguageCheckUseCase(
      selectionReader: AccessibilitySelectedTextReader(accessibility: accessibility),
      languageDetector: detector
    )

    await #expect(throws: AccessibilitySelectionError.unsupportedApplication) {
      try await useCase.check()
    }

    #expect(accessibility.selectedRangeReadCount == 0)
    #expect(accessibility.selectedTextReadCount == 0)
    #expect(accessibility.activationCount == 0)
    #expect(accessibility.applicationIdentityLookupCount == 1)
    #expect(await detector.receivedTexts.isEmpty)
  }

  @Test(
    "on-demand activation runs only for frontmost stable Google Chrome",
    arguments: ActivationFixture.cases
  )
  fileprivate func activationIsChromeOnly(fixture: ActivationFixture) async throws {
    let accessibility = AXReaderSpy(
      snapshots: [.textEditTextArea, .textEditTextArea],
      focusedElementErrors: [.noFocusedControl, nil, nil],
      frontmostApplicationIdentity: fixture.identity,
      applicationIdentities: fixture.allowsRead
        ? [
          AXApplicationIdentity(
            processIdentifier: 42,
            bundleIdentifier: "com.google.Chrome"
          ),
          AXApplicationIdentity(
            processIdentifier: 42,
            bundleIdentifier: "com.google.Chrome"
          ),
        ] : []
    )

    if fixture.allowsRead {
      _ = try await AccessibilitySelectedTextReader(
        accessibility: accessibility
      ).readSelectedText()
    } else {
      await #expect(throws: (any Error).self) {
        try await AccessibilitySelectedTextReader(
          accessibility: accessibility
        ).readSelectedText()
      }
    }

    #expect(accessibility.activationCount == (fixture.allowsRead ? 1 : 0))
    #expect(accessibility.selectedRangeReadCount == (fixture.allowsRead ? 1 : 0))
    #expect(accessibility.selectedTextReadCount == (fixture.allowsRead ? 1 : 0))
  }

  @Test("application identity is revalidated after capture before networking")
  func applicationIdentityRaceFailsClosed() async {
    let accessibility = AXReaderSpy(
      snapshots: [.textEditTextArea, .textEditTextArea],
      selectedText: "KANAARILIND-APP-RACE",
      applicationIdentities: [
        AXApplicationIdentity(processIdentifier: 42, bundleIdentifier: "com.apple.TextEdit"),
        AXApplicationIdentity(processIdentifier: 42, bundleIdentifier: "com.example.Unknown"),
      ]
    )
    let detector = SelectionRecordingDetector()
    let useCase = LanguageCheckUseCase(
      selectionReader: AccessibilitySelectedTextReader(accessibility: accessibility),
      languageDetector: detector
    )

    await #expect(throws: AccessibilitySelectionError.focusChanged) {
      try await useCase.check()
    }

    #expect(accessibility.selectedTextReadCount == 1)
    #expect(await detector.receivedTexts.isEmpty)
    #expect(accessibility.retainedElementCount == 0)
  }

  @Test("a Chrome field is reacquired from system focus after on-demand activation")
  func chromeSelectionAfterActivation() async throws {
    let accessibility = AXReaderSpy(
      snapshots: [.textEditTextArea, .textEditTextArea],
      selectedRange: AXTextRange(location: 0, length: 16),
      selectedText: "BROWSER-FIXTURE",
      focusedElementErrors: [.noFocusedControl, nil, nil],
      applicationIdentities: [
        AXApplicationIdentity(processIdentifier: 42, bundleIdentifier: "com.google.Chrome"),
        AXApplicationIdentity(processIdentifier: 42, bundleIdentifier: "com.google.Chrome"),
      ]
    )

    let selectedText = try await AccessibilitySelectedTextReader(
      accessibility: accessibility
    ).readSelectedText()

    #expect(selectedText == SelectedText("BROWSER-FIXTURE"))
    #expect(accessibility.activationCount == 1)
    #expect(accessibility.focusedElementRequestCount == 3)
    #expect(accessibility.selectedTextReadCount == 1)
    #expect(accessibility.valueReadCount == 0)
  }

  @Test(
    "standard Safari and Chrome fields complete the language check",
    arguments: BrowserFixture.supportedCases
  )
  fileprivate func supportedBrowserFields(fixture: BrowserFixture) async throws {
    let identity = AXApplicationIdentity(
      processIdentifier: 42,
      bundleIdentifier: fixture.bundleIdentifier
    )
    let accessibility = AXReaderSpy(
      snapshots: [fixture.snapshot, fixture.snapshot],
      selectedRange: AXTextRange(location: 0, length: fixture.selection.utf16.count),
      selectedText: fixture.selection,
      focusedElementErrors: fixture.needsActivation ? [.noFocusedControl, nil, nil] : [],
      frontmostApplicationIdentity: identity,
      applicationIdentities: [identity, identity]
    )
    let detector = SelectionRecordingDetector()
    let useCase = LanguageCheckUseCase(
      selectionReader: AccessibilitySelectedTextReader(accessibility: accessibility),
      languageDetector: detector
    )

    let verdict = try await useCase.check()

    #expect(verdict == .estonian)
    #expect(await detector.receivedTexts == [fixture.selection])
    #expect(accessibility.activationCount == (fixture.needsActivation ? 1 : 0))
    #expect(accessibility.selectedRangeReadCount == 1)
    #expect(accessibility.selectedTextReadCount == 1)
    #expect(accessibility.valueReadCount == 0)
  }

  @Test(
    "unsupported browser surfaces fail before content access or language detection",
    arguments: BrowserRejectionFixture.cases
  )
  fileprivate func unsupportedBrowserSurfacesFailClosed(fixture: BrowserRejectionFixture) async {
    let accessibility = AXReaderSpy(snapshots: [fixture.snapshot])
    let detector = SelectionRecordingDetector()
    let useCase = LanguageCheckUseCase(
      selectionReader: AccessibilitySelectedTextReader(accessibility: accessibility),
      languageDetector: detector
    )

    await #expect(throws: fixture.expectedError) {
      try await useCase.check()
    }

    #expect(accessibility.selectedRangeReadCount == 0)
    #expect(accessibility.selectedTextReadCount == 0)
    #expect(accessibility.valueReadCount == 0)
    #expect(await detector.receivedTexts.isEmpty)
  }

  @Test("the offline browser fixture is synthetic and contains the supported matrix")
  func offlineBrowserFixture() throws {
    let fixtureURL = try #require(
      Bundle.module.url(
        forResource: "browser-fields",
        withExtension: "html",
        subdirectory: "Fixtures"
      )
    )
    let html = try String(contentsOf: fixtureURL, encoding: .utf8)

    for identifier in [
      "safari-chrome-text",
      "safari-chrome-search",
      "safari-chrome-textarea",
      "reject-password",
      "reject-readonly",
      "reject-disabled",
      "reject-contenteditable",
    ] {
      #expect(html.contains("id=\"\(identifier)\""))
    }
    #expect(html.contains("SYNTHETIC-BROWSER-FIXTURE"))
    #expect(!html.contains("http://"))
    #expect(!html.contains("https://"))
  }

  @Test(
    "ineligible controls fail closed before selected text is read",
    arguments: AXFixture.ineligibleCases
  )
  private func ineligibleControlsFailClosed(fixture: AXFixture) async {
    let accessibility = AXReaderSpy(snapshots: [fixture.snapshot])
    let detector = SelectionRecordingDetector()
    let useCase = LanguageCheckUseCase(
      selectionReader: AccessibilitySelectedTextReader(accessibility: accessibility),
      languageDetector: detector
    )

    await #expect(throws: fixture.expectedError) {
      try await useCase.check()
    }

    #expect(accessibility.selectedRangeReadCount == 0)
    #expect(accessibility.selectedTextReadCount == 0)
    #expect(accessibility.valueReadCount == 0)
    #expect(await detector.receivedTexts.isEmpty)
    #expect(accessibility.retainedElementCount == 0)
  }

  @Test(
    "empty and oversized ranges stop before selected text access",
    arguments: [
      (AXTextRange(location: 0, length: 0), AccessibilitySelectionError.noSelection),
      (AXTextRange(location: 0, length: 10_001), AccessibilitySelectionError.selectionTooLarge),
      (AXTextRange(location: -1, length: 4), AccessibilitySelectionError.invalidSelection),
    ])
  func invalidRanges(range: AXTextRange, expected: AccessibilitySelectionError) async {
    let accessibility = AXReaderSpy(
      snapshots: [.textEditTextArea],
      selectedRange: range
    )
    let detector = SelectionRecordingDetector()
    let useCase = LanguageCheckUseCase(
      selectionReader: AccessibilitySelectedTextReader(accessibility: accessibility),
      languageDetector: detector
    )

    await #expect(throws: expected) {
      try await useCase.check()
    }

    #expect(accessibility.selectedTextReadCount == 0)
    #expect(accessibility.valueReadCount == 0)
    #expect(await detector.receivedTexts.isEmpty)
    #expect(accessibility.retainedElementCount == 0)
  }

  @Test("a changed focused element discards the selection before networking")
  func focusRaceFailsClosed() async {
    let accessibility = AXReaderSpy(
      snapshots: [.textEditTextArea, .textEditTextArea],
      identities: [
        AXElementID(processIdentifier: 42, identity: 1),
        AXElementID(processIdentifier: 42, identity: 2),
      ],
      selectedRange: AXTextRange(location: 0, length: 15),
      selectedText: "KANAARILIND-123"
    )
    let detector = SelectionRecordingDetector()
    let useCase = LanguageCheckUseCase(
      selectionReader: AccessibilitySelectedTextReader(accessibility: accessibility),
      languageDetector: detector
    )

    await #expect(throws: AccessibilitySelectionError.focusChanged) {
      try await useCase.check()
    }

    #expect(accessibility.selectedTextReadCount == 1)
    #expect(accessibility.valueReadCount == 0)
    #expect(await detector.receivedTexts.isEmpty)
    #expect(accessibility.retainedElementCount == 0)
  }

  @Test("metadata changes after capture discard the selection before networking")
  func metadataRaceFailsClosed() async {
    let accessibility = AXReaderSpy(
      snapshots: [.textEditTextArea, .protectedTextArea],
      selectedRange: AXTextRange(location: 0, length: 15),
      selectedText: "KANAARILIND-456"
    )
    let detector = SelectionRecordingDetector()
    let useCase = LanguageCheckUseCase(
      selectionReader: AccessibilitySelectedTextReader(accessibility: accessibility),
      languageDetector: detector
    )

    await #expect(throws: AccessibilitySelectionError.focusChanged) {
      try await useCase.check()
    }

    #expect(accessibility.selectedTextReadCount == 1)
    #expect(accessibility.valueReadCount == 0)
    #expect(await detector.receivedTexts.isEmpty)
    #expect(accessibility.retainedElementCount == 0)
  }

  @Test("missing optional TextEdit metadata remains eligible")
  func omittedOptionalMetadataIsEligible() async throws {
    var snapshot = AXSnapshot.textEditTextArea
    snapshot.enabled = .absent
    snapshot.focused = .absent
    let accessibility = AXReaderSpy(
      snapshots: [snapshot, snapshot],
      selectedRange: AXTextRange(location: 0, length: 4),
      selectedText: "Tere"
    )

    let selectedText = try await AccessibilitySelectedTextReader(
      accessibility: accessibility
    ).readSelectedText()

    #expect(selectedText == SelectedText("Tere"))
    #expect(accessibility.valueReadCount == 0)
  }

  @Test("missing trust and operational AX errors stop before reading or sending text")
  func accessFailuresFailClosed() async {
    for accessibility in [
      AXReaderSpy(snapshots: [.textEditTextArea], isTrusted: false),
      AXReaderSpy(snapshots: [.textEditTextArea], focusedElementError: .targetUnavailable),
      AXReaderSpy(snapshots: [.textEditTextArea], snapshotError: .unknown),
    ] {
      let detector = SelectionRecordingDetector()
      let useCase = LanguageCheckUseCase(
        selectionReader: AccessibilitySelectedTextReader(accessibility: accessibility),
        languageDetector: detector
      )

      do {
        _ = try await useCase.check()
        Issue.record("An inaccessible control reached the language detector")
      } catch {
        // Every coarse Accessibility failure is expected to fail closed.
      }

      #expect(accessibility.selectedRangeReadCount == 0)
      #expect(accessibility.selectedTextReadCount == 0)
      #expect(accessibility.valueReadCount == 0)
      #expect(await detector.receivedTexts.isEmpty)
      #expect(accessibility.retainedElementCount == 0)
    }
  }

  @Test("repeated language checks release every Accessibility element handle")
  func repeatedChecksReleaseHandles() async throws {
    let accessibility = AXReaderSpy(
      snapshots: [.textEditTextArea],
      selectedRange: AXTextRange(location: 0, length: 4),
      selectedText: "Tere"
    )
    let reader = AccessibilitySelectedTextReader(accessibility: accessibility)

    for _ in 0..<100 {
      _ = try await reader.readSelectedText()
      #expect(accessibility.retainedElementCount == 0)
    }

    #expect(accessibility.acquiredElementCount == 200)
    #expect(accessibility.releasedElementCount == 200)
  }

  @Test("cancellation after selection capture never reaches the detector")
  func cancellationDiscardsSelection() async {
    let accessibility = SuspendingAXReader()
    let detector = SelectionRecordingDetector()
    let useCase = LanguageCheckUseCase(
      selectionReader: AccessibilitySelectedTextReader(accessibility: accessibility),
      languageDetector: detector
    )

    let check = Task { try await useCase.check() }
    await accessibility.waitUntilSelectionReadStarts()
    await useCase.cancel()
    accessibility.finishSelectionRead()

    await #expect(throws: CancellationError.self) {
      try await check.value
    }
    #expect(await detector.receivedTexts.isEmpty)
    #expect(accessibility.retainedElementCount == 0)
  }
}

private struct AXFixture: Sendable, CustomTestStringConvertible {
  let name: String
  let snapshot: AXSnapshot
  let expectedError: AccessibilitySelectionError

  var testDescription: String { name }

  static let ineligibleCases: [AXFixture] = [
    AXFixture(name: "secure role", snapshot: .secureRole, expectedError: .protectedContent),
    AXFixture(name: "secure subrole", snapshot: .secureTextField, expectedError: .protectedContent),
    AXFixture(
      name: "protected content", snapshot: .protectedTextArea, expectedError: .protectedContent),
    AXFixture(name: "web area", snapshot: .webArea, expectedError: .unsupportedTextField),
    AXFixture(name: "custom role", snapshot: .customRole, expectedError: .unsupportedTextField),
    AXFixture(
      name: "custom subrole", snapshot: .customSubrole, expectedError: .unsupportedTextField),
    AXFixture(name: "read-only field", snapshot: .readOnlyTextField, expectedError: .readOnly),
    AXFixture(
      name: "disabled field", snapshot: .disabledTextField, expectedError: .unsupportedTextField),
    AXFixture(name: "unfocused field", snapshot: .unfocusedTextField, expectedError: .focusChanged),
    AXFixture(
      name: "malformed protection metadata", snapshot: .malformedProtection, expectedError: .unknown
    ),
    AXFixture(
      name: "malformed enabled metadata", snapshot: .malformedEnabled, expectedError: .unknown),
    AXFixture(
      name: "missing selected-text capability", snapshot: .missingSelectionCapability,
      expectedError: .unsupportedTextField),
  ]
}

private struct UnsupportedApplicationFixture: Sendable, CustomTestStringConvertible {
  let name: String
  let identity: AXApplicationIdentity?

  var testDescription: String { name }

  static let cases: [UnsupportedApplicationFixture] = [
    UnsupportedApplicationFixture(name: "missing", identity: nil),
    UnsupportedApplicationFixture(
      name: "empty bundle identifier",
      identity: AXApplicationIdentity(processIdentifier: 42, bundleIdentifier: "")
    ),
    UnsupportedApplicationFixture(
      name: "lookalike Chrome identifier",
      identity: AXApplicationIdentity(
        processIdentifier: 42,
        bundleIdentifier: "com.google.Chrome.beta"
      )
    ),
    UnsupportedApplicationFixture(
      name: "unsupported application",
      identity: AXApplicationIdentity(
        processIdentifier: 42,
        bundleIdentifier: "com.microsoft.Word"
      )
    ),
    UnsupportedApplicationFixture(
      name: "mismatched process",
      identity: AXApplicationIdentity(
        processIdentifier: 99,
        bundleIdentifier: "com.apple.TextEdit"
      )
    ),
  ]
}

private struct ActivationFixture: Sendable, CustomTestStringConvertible {
  let name: String
  let identity: AXApplicationIdentity?
  let allowsRead: Bool

  var testDescription: String { name }

  static let cases: [ActivationFixture] = [
    ActivationFixture(
      name: "Google Chrome",
      identity: AXApplicationIdentity(
        processIdentifier: 42,
        bundleIdentifier: "com.google.Chrome"
      ),
      allowsRead: true
    ),
    ActivationFixture(
      name: "TextEdit",
      identity: AXApplicationIdentity(
        processIdentifier: 42,
        bundleIdentifier: "com.apple.TextEdit"
      ),
      allowsRead: false
    ),
    ActivationFixture(
      name: "Safari",
      identity: AXApplicationIdentity(
        processIdentifier: 42,
        bundleIdentifier: "com.apple.Safari"
      ),
      allowsRead: false
    ),
    ActivationFixture(
      name: "unsupported",
      identity: AXApplicationIdentity(
        processIdentifier: 42,
        bundleIdentifier: "com.example.Unknown"
      ),
      allowsRead: false
    ),
    ActivationFixture(name: "missing", identity: nil, allowsRead: false),
  ]
}

private struct BrowserFixture: Sendable, CustomTestStringConvertible {
  let name: String
  let snapshot: AXSnapshot
  let selection: String
  let bundleIdentifier: String
  let needsActivation: Bool

  var testDescription: String { name }

  static let supportedCases: [BrowserFixture] = [
    BrowserFixture(
      name: "Safari text input",
      snapshot: .browserTextField,
      selection: "SYNTHETIC-BROWSER-FIXTURE-SAFARI-INPUT",
      bundleIdentifier: "com.apple.Safari",
      needsActivation: false
    ),
    BrowserFixture(
      name: "Safari textarea",
      snapshot: .browserTextArea,
      selection: "SYNTHETIC-BROWSER-FIXTURE-SAFARI-TEXTAREA",
      bundleIdentifier: "com.apple.Safari",
      needsActivation: false
    ),
    BrowserFixture(
      name: "Chrome text input",
      snapshot: .browserTextField,
      selection: "SYNTHETIC-BROWSER-FIXTURE-CHROME-INPUT",
      bundleIdentifier: "com.google.Chrome",
      needsActivation: true
    ),
    BrowserFixture(
      name: "Chrome search input",
      snapshot: .browserSearchField,
      selection: "SYNTHETIC-BROWSER-FIXTURE-CHROME-SEARCH",
      bundleIdentifier: "com.google.Chrome",
      needsActivation: true
    ),
  ]
}

private struct BrowserRejectionFixture: Sendable, CustomTestStringConvertible {
  let name: String
  let snapshot: AXSnapshot
  let expectedError: AccessibilitySelectionError

  var testDescription: String { name }

  static let cases: [BrowserRejectionFixture] = [
    BrowserRejectionFixture(
      name: "password field",
      snapshot: .secureTextField,
      expectedError: .protectedContent
    ),
    BrowserRejectionFixture(
      name: "web-area document selection",
      snapshot: .webArea,
      expectedError: .unsupportedTextField
    ),
    BrowserRejectionFixture(
      name: "contenteditable group",
      snapshot: .contentEditableGroup,
      expectedError: .unsupportedTextField
    ),
    BrowserRejectionFixture(
      name: "custom editor role",
      snapshot: .customRole,
      expectedError: .unsupportedTextField
    ),
  ]
}

extension AXSnapshot {
  fileprivate static let textEditTextArea = AXSnapshot(
    role: "AXTextArea",
    subrole: .absent,
    containsProtectedContent: .absent,
    enabled: .value(true),
    focused: .value(true),
    attributeNames: ["AXSelectedText", "AXSelectedTextRange"],
    isValueSettable: true
  )

  fileprivate static let browserTextField = replacing(textEditTextArea, role: "AXTextField")
  fileprivate static let browserTextArea = textEditTextArea
  fileprivate static let browserSearchField = AXSnapshot(
    role: "AXTextField",
    subrole: .value("AXSearchField"),
    containsProtectedContent: .absent,
    enabled: .value(true),
    focused: .value(true),
    attributeNames: ["AXSelectedText", "AXSelectedTextRange"],
    isValueSettable: true
  )

  fileprivate static let secureTextField = AXSnapshot(
    role: "AXTextField",
    subrole: .value("AXSecureTextField"),
    containsProtectedContent: .absent,
    enabled: .value(true),
    focused: .value(true),
    attributeNames: ["AXSelectedText", "AXSelectedTextRange"],
    isValueSettable: true
  )

  fileprivate static let secureRole = replacing(textEditTextArea, role: "AXSecureTextField")

  fileprivate static let protectedTextArea = AXSnapshot(
    role: "AXTextArea",
    subrole: .absent,
    containsProtectedContent: .value(true),
    enabled: .value(true),
    focused: .value(true),
    attributeNames: ["AXSelectedText", "AXSelectedTextRange"],
    isValueSettable: true
  )

  fileprivate static let webArea = replacing(textEditTextArea, role: "AXWebArea")
  fileprivate static let contentEditableGroup = replacing(textEditTextArea, role: "AXGroup")
  fileprivate static let customRole = replacing(textEditTextArea, role: "CustomEditor")
  fileprivate static let customSubrole = AXSnapshot(
    role: "AXTextField",
    subrole: .value("CustomEditorSubrole"),
    containsProtectedContent: .absent,
    enabled: .value(true),
    focused: .value(true),
    attributeNames: ["AXSelectedText", "AXSelectedTextRange"],
    isValueSettable: true
  )
  fileprivate static let readOnlyTextField = replacing(
    textEditTextArea, role: "AXTextField", settable: false)
  fileprivate static let disabledTextField = replacing(
    textEditTextArea, role: "AXTextField", enabled: .value(false))
  fileprivate static let unfocusedTextField = replacing(
    textEditTextArea, role: "AXTextField", focused: .value(false))
  fileprivate static let malformedProtection = replacing(
    textEditTextArea,
    protected: .malformed
  )
  fileprivate static let malformedEnabled = replacing(textEditTextArea, enabled: .malformed)
  fileprivate static let missingSelectionCapability = AXSnapshot(
    role: "AXTextArea",
    subrole: .absent,
    containsProtectedContent: .absent,
    enabled: .value(true),
    focused: .value(true),
    attributeNames: ["AXSelectedTextRange"],
    isValueSettable: true
  )

  fileprivate static func replacing(
    _ source: AXSnapshot,
    role: String? = nil,
    protected: AXOptionalMetadata<Bool>? = nil,
    enabled: AXOptionalMetadata<Bool>? = nil,
    focused: AXOptionalMetadata<Bool>? = nil,
    settable: Bool? = nil
  ) -> AXSnapshot {
    AXSnapshot(
      role: role ?? source.role,
      subrole: source.subrole,
      containsProtectedContent: protected ?? source.containsProtectedContent,
      enabled: enabled ?? source.enabled,
      focused: focused ?? source.focused,
      attributeNames: source.attributeNames,
      isValueSettable: settable ?? source.isValueSettable
    )
  }
}

private final class AXReaderSpy: AXReading, @unchecked Sendable {
  private let lock = NSLock()
  private var snapshots: [AXSnapshot]
  private var identities: [AXElementID]
  private let range: AXTextRange
  private let text: String
  private let trusted: Bool
  private let focusedElementError: AccessibilitySelectionError?
  private var focusedElementErrors: [AccessibilitySelectionError?]
  private let snapshotError: AccessibilitySelectionError?
  private let frontmostIdentity: AXApplicationIdentity?
  private var applicationIdentities: [AXApplicationIdentity?]
  private var retainedElementReferences = 0
  private(set) var acquiredElementCount = 0
  private(set) var activationCount = 0
  private(set) var applicationIdentityLookupCount = 0
  private(set) var focusedElementRequestCount = 0
  private(set) var releasedElementCount = 0
  private(set) var selectedRangeReadCount = 0
  private(set) var selectedTextReadCount = 0
  private(set) var valueReadCount = 0

  init(
    snapshots: [AXSnapshot],
    identities: [AXElementID] = [AXElementID(processIdentifier: 42, identity: 1)],
    selectedRange: AXTextRange = AXTextRange(location: 0, length: 4),
    selectedText: String = "Tere",
    isTrusted: Bool = true,
    focusedElementError: AccessibilitySelectionError? = nil,
    focusedElementErrors: [AccessibilitySelectionError?] = [],
    snapshotError: AccessibilitySelectionError? = nil,
    frontmostApplicationIdentity: AXApplicationIdentity? = AXApplicationIdentity(
      processIdentifier: 42,
      bundleIdentifier: "com.google.Chrome"
    ),
    applicationIdentities: [AXApplicationIdentity?] = []
  ) {
    self.snapshots = snapshots
    self.identities = identities
    range = selectedRange
    text = selectedText
    trusted = isTrusted
    self.focusedElementError = focusedElementError
    self.focusedElementErrors = focusedElementErrors
    self.snapshotError = snapshotError
    frontmostIdentity = frontmostApplicationIdentity
    self.applicationIdentities = applicationIdentities
  }

  func isTrusted() -> Bool { trusted }

  func frontmostApplicationIdentity() -> AXApplicationIdentity? { frontmostIdentity }

  func applicationIdentity(processIdentifier: pid_t) -> AXApplicationIdentity? {
    lock.withLock {
      applicationIdentityLookupCount += 1
      if applicationIdentities.isEmpty {
        return AXApplicationIdentity(
          processIdentifier: processIdentifier,
          bundleIdentifier: "com.apple.TextEdit"
        )
      }
      if applicationIdentities.count > 1 { return applicationIdentities.removeFirst() }
      return applicationIdentities[0]
    }
  }

  func activateFrontmostApplicationAccessibility() {
    lock.withLock { activationCount += 1 }
  }

  func focusedElement() throws -> AXElementID {
    focusedElementRequestCount += 1
    if !focusedElementErrors.isEmpty,
      let error = focusedElementErrors.removeFirst()
    {
      throw error
    }
    if let focusedElementError { throw focusedElementError }
    return lock.withLock {
      acquiredElementCount += 1
      retainedElementReferences += 1
      if identities.count > 1 { return identities.removeFirst() }
      return identities[0]
    }
  }

  func snapshot(of element: AXElementID) throws -> AXSnapshot {
    if let snapshotError { throw snapshotError }
    return lock.withLock {
      if snapshots.count > 1 { return snapshots.removeFirst() }
      return snapshots[0]
    }
  }

  func selectedRange(of element: AXElementID) throws -> AXTextRange {
    lock.withLock { selectedRangeReadCount += 1 }
    return range
  }

  func selectedText(of element: AXElementID) throws -> String {
    lock.withLock { selectedTextReadCount += 1 }
    return text
  }

  func value(of element: AXElementID) throws -> String {
    lock.withLock { valueReadCount += 1 }
    return "THIS MUST NEVER BE READ"
  }

  func sameElement(_ lhs: AXElementID, _ rhs: AXElementID) -> Bool {
    lhs == rhs
  }

  func release(_ element: AXElementID) {
    lock.withLock {
      releasedElementCount += 1
      retainedElementReferences -= 1
    }
  }

  var retainedElementCount: Int {
    lock.withLock { retainedElementReferences }
  }
}

private final class SuspendingAXReader: AXReading, @unchecked Sendable {
  private let lock = NSLock()
  private var didStart = false
  private var continuation: CheckedContinuation<Void, Never>?
  private var retainedElementReferences = 0

  func isTrusted() -> Bool { true }
  func frontmostApplicationIdentity() -> AXApplicationIdentity? {
    AXApplicationIdentity(processIdentifier: 42, bundleIdentifier: "com.apple.TextEdit")
  }
  func applicationIdentity(processIdentifier: pid_t) -> AXApplicationIdentity? {
    AXApplicationIdentity(
      processIdentifier: processIdentifier,
      bundleIdentifier: "com.apple.TextEdit"
    )
  }
  func activateFrontmostApplicationAccessibility() {}
  func focusedElement() throws -> AXElementID {
    lock.withLock { retainedElementReferences += 1 }
    return AXElementID(processIdentifier: 42, identity: 1)
  }
  func snapshot(of element: AXElementID) throws -> AXSnapshot { .textEditTextArea }
  func selectedRange(of element: AXElementID) throws -> AXTextRange {
    AXTextRange(location: 0, length: 4)
  }

  func selectedText(of element: AXElementID) async throws -> String {
    await withCheckedContinuation { continuation in
      lock.withLock {
        didStart = true
        self.continuation = continuation
      }
    }
    return "Tere"
  }

  func value(of element: AXElementID) throws -> String { "THIS MUST NEVER BE READ" }
  func sameElement(_ lhs: AXElementID, _ rhs: AXElementID) -> Bool { lhs == rhs }

  func release(_ element: AXElementID) {
    lock.withLock { retainedElementReferences -= 1 }
  }

  var retainedElementCount: Int {
    lock.withLock { retainedElementReferences }
  }

  func waitUntilSelectionReadStarts() async {
    while !lock.withLock({ didStart }) { await Task.yield() }
  }

  func finishSelectionRead() {
    lock.withLock {
      continuation?.resume()
      continuation = nil
    }
  }
}

private actor SelectionRecordingDetector: LanguageDetecting {
  private(set) var receivedTexts: [String] = []

  func detectLanguage(of selectedText: SelectedText) async throws -> LanguageVerdict {
    receivedTexts.append(selectedText.value)
    return .estonian
  }
}
