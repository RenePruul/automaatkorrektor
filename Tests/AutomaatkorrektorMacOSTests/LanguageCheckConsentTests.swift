import AutomaatkorrektorCore
import Testing

@testable import AutomaatkorrektorMacOS

@MainActor
@Suite("Language-check consent")
struct LanguageCheckConsentTests {
  private let endpoint = try! LanguageServiceEndpoint(
    validating: "https://language.example.ee"
  )

  @Test("consent survives relaunch only for its normalized origin")
  func consentIsOriginSpecificAndPersistent() {
    let persistence = MemoryLanguageCheckConsentPersistence()
    let origin = endpoint.languageCheckConsentOrigin!
    let firstLaunch = LanguageCheckConsentStore(persistence: persistence)

    firstLaunch.grantConsent(for: origin)

    let relaunched = LanguageCheckConsentStore(persistence: persistence)
    let changedOrigin = try! LanguageServiceEndpoint(
      validating: "https://language.example.ee:8443"
    ).languageCheckConsentOrigin!
    #expect(relaunched.hasConsent(for: origin))
    #expect(!relaunched.hasConsent(for: changedOrigin))
    #expect(
      persistence.allValues
        == [
          #"{"origin":{"host":"language.example.ee","port":443,"scheme":"https"},"version":1}"#
        ]
    )
  }

  @Test("revocation and malformed or unknown records fail closed")
  func revocationAndInvalidRecordsFailClosed() {
    let persistence = MemoryLanguageCheckConsentPersistence()
    let origin = endpoint.languageCheckConsentOrigin!
    let consent = LanguageCheckConsentStore(persistence: persistence)
    consent.grantConsent(for: origin)
    consent.revokeConsent()

    #expect(!consent.hasConsent(for: origin))
    #expect(persistence.allValues.isEmpty)

    for invalidValue in [
      #"{"origin":{"host":"language.example.ee","port":443,"scheme":"https"},"version":2}"#,
      #"{"origin":{"host":"language.example.ee","port":0,"scheme":"https"},"version":1}"#,
      #"{"origin":{"host":"language.example.ee","port":65536,"scheme":"https"},"version":1}"#,
      #"{"origin":{"host":"LANGUAGE.example.ee","port":443,"scheme":"https"},"version":1}"#,
      #"{"origin":{"host":"language.example.ee","port":80,"scheme":"http"},"version":1}"#,
      "not-a-consent-record",
      "v1\nhttps\nlanguage.example.ee\n443",
    ] {
      persistence.set(invalidValue, forKey: LanguageCheckConsentStore.storageKey)
      let relaunched = LanguageCheckConsentStore(persistence: persistence)

      #expect(!relaunched.hasConsent(for: origin))
      #expect(persistence.allValues.isEmpty)
    }
  }

  @Test("granting displayed consent starts exactly one fresh check")
  func grantingConsentStartsFreshCheck() async {
    let consent = LanguageCheckConsentStore(
      persistence: MemoryLanguageCheckConsentPersistence()
    )
    let reader = ConsentCountingSelectionReader()
    let detector = ConsentCountingDetector()
    let model = makeViewModel(consent: consent, reader: reader, detector: detector)
    let origin = endpoint.languageCheckConsentOrigin!

    await model.check()
    #expect(model.state == .blocked(.languageCheckConsentRequired(origin)))
    #expect(await reader.readCount == 0)
    #expect(await detector.requestCount == 0)

    await model.grantLanguageCheckConsent()

    #expect(model.state == .verdict(.estonian))
    #expect(await reader.readCount == 1)
    #expect(await detector.requestCount == 1)
    #expect(consent.hasConsent(for: origin))
  }

  @Test("declining displayed consent reads and sends nothing")
  func decliningConsentPerformsNoCheck() async {
    let consent = LanguageCheckConsentStore(
      persistence: MemoryLanguageCheckConsentPersistence()
    )
    let reader = ConsentCountingSelectionReader()
    let detector = ConsentCountingDetector()
    let model = makeViewModel(consent: consent, reader: reader, detector: detector)

    await model.check()
    model.declineLanguageCheckConsent()

    #expect(model.state == .waiting)
    #expect(await reader.readCount == 0)
    #expect(await detector.requestCount == 0)
  }

  @Test("consent presentation identifies the origin and sensitive-text risk")
  func presentationIsInformed() async {
    let consent = LanguageCheckConsentStore(
      persistence: MemoryLanguageCheckConsentPersistence()
    )
    let model = makeViewModel(
      consent: consent,
      reader: ConsentCountingSelectionReader(),
      detector: ConsentCountingDetector()
    )

    await model.check()

    let presentation = model.languageCheckConsentPresentation
    #expect(presentation?.origin == endpoint.languageCheckConsentOrigin)
    #expect(presentation?.explanation.contains("language.example.ee") == true)
    #expect(presentation?.warning.contains("paroole") == true)
    #expect(presentation?.warning.contains("tundlikke isikuandmeid") == true)
  }

  @Test("changing origin or revoking consent blocks before the next content access")
  func changedOrRevokedConsentBlocks() async {
    let consent = LanguageCheckConsentStore(
      persistence: MemoryLanguageCheckConsentPersistence()
    )
    let origin = endpoint.languageCheckConsentOrigin!
    consent.grantConsent(for: origin)
    let reader = ConsentCountingSelectionReader()
    let detector = ConsentCountingDetector()
    let model = makeViewModel(consent: consent, reader: reader, detector: detector)

    await model.check()
    consent.revokeConsent()
    await model.check()

    #expect(model.state == .blocked(.languageCheckConsentRequired(origin)))
    #expect(await reader.readCount == 1)
    #expect(await detector.requestCount == 1)

    let changedEndpoint = try! LanguageServiceEndpoint(
      validating: "https://other.example.ee:8443"
    )
    let changedModel = makeViewModel(
      endpoint: changedEndpoint,
      consent: consent,
      reader: reader,
      detector: detector
    )
    await changedModel.check()
    #expect(
      changedModel.state
        == .blocked(
          .languageCheckConsentRequired(changedEndpoint.languageCheckConsentOrigin!)
        )
    )
    #expect(await reader.readCount == 1)
  }

  @Test("status distinguishes local, consented, and unconsented endpoints")
  func settingsStatusReflectsConsent() {
    let consent = LanguageCheckConsentStore(
      persistence: MemoryLanguageCheckConsentPersistence()
    )
    let origin = endpoint.languageCheckConsentOrigin!

    #expect(consent.status(for: .default) == .local)
    #expect(consent.status(for: endpoint) == .origin(origin, hasConsent: false))
    consent.grantConsent(for: origin)
    #expect(consent.status(for: endpoint) == .origin(origin, hasConsent: true))
  }

  @Test("a local endpoint bypasses language-check consent")
  func localEndpointBypassesConsent() async {
    let consent = LanguageCheckConsentStore(
      persistence: MemoryLanguageCheckConsentPersistence()
    )
    let reader = ConsentCountingSelectionReader()
    let detector = ConsentCountingDetector()
    let model = makeViewModel(
      endpoint: .default,
      consent: consent,
      reader: reader,
      detector: detector
    )

    await model.check()

    #expect(model.state == .verdict(.estonian))
    #expect(await reader.readCount == 1)
    #expect(await detector.requestCount == 1)
  }

  private func makeViewModel(
    endpoint: LanguageServiceEndpoint? = nil,
    consent: LanguageCheckConsentStore,
    reader: ConsentCountingSelectionReader,
    detector: ConsentCountingDetector
  ) -> LanguageCheckViewModel {
    LanguageCheckViewModel(
      useCase: LanguageCheckUseCase(
        configurationProvider: ConsentConfigurationProvider(
          LanguageCheckConfiguration(endpoint: endpoint ?? self.endpoint)
        ),
        selectionReader: reader,
        languageDetector: detector,
        languageCheckConsent: consent
      ),
      accessibilityPermission: ConsentPermissionController(),
      languageCheckConsent: consent
    )
  }
}

private struct ConsentConfigurationProvider: LanguageCheckConfiguring {
  let configuration: LanguageCheckConfiguration

  init(_ configuration: LanguageCheckConfiguration) {
    self.configuration = configuration
  }

  func currentConfiguration() -> LanguageCheckConfiguration { configuration }
}

private actor ConsentCountingSelectionReader: SelectionReading {
  private(set) var readCount = 0

  func readSelectedText() -> SelectedText {
    readCount += 1
    return SelectedText("Tere maailm")
  }
}

private actor ConsentCountingDetector: LanguageDetecting {
  private(set) var requestCount = 0

  func detectLanguage(
    of selectedText: SelectedText,
    configuration: LanguageCheckConfiguration
  ) -> LanguageVerdict {
    requestCount += 1
    return .estonian
  }
}

@MainActor
private final class ConsentPermissionController: AccessibilityPermissionControlling {
  func checkPermission() -> Bool { true }
  func openSettings() {}
}

private final class MemoryLanguageCheckConsentPersistence: LanguageCheckConsentPersisting,
  @unchecked Sendable
{
  private var value: String?

  var allValues: [String] { value.map { [$0] } ?? [] }

  func string(forKey key: String) -> String? { value }

  func set(_ value: String, forKey key: String) {
    self.value = value
  }

  func removeValue(forKey key: String) {
    value = nil
  }
}
