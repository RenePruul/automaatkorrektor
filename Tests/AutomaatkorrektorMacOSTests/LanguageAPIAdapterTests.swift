import AutomaatkorrektorCore
import Foundation
import Testing

@testable import AutomaatkorrektorMacOS

@Suite("Language API adapter")
struct LanguageAPIAdapterTests {
  @Test("an in-flight check keeps its URL snapshot and the next check uses the new URL")
  @MainActor
  func immutablePerCheckURLSnapshot() async throws {
    let settings = APISettingsStore(storage: MemoryAPISettingsStorage())
    let reader = URLSnapshotGatedSelectionReader()
    let transport = RecordingHTTPTransport(responses: [
      .success(response(status: 200, body: "{\"verdict\":\"jah\"}")),
      .success(response(status: 200, body: "{\"verdict\":\"jah\"}")),
    ])
    let useCase = LanguageCheckUseCase(
      configurationProvider: settings,
      selectionReader: reader,
      languageDetector: LanguageAPIClient(transport: transport)
    )

    let firstCheck = Task { try await useCase.check() }
    await reader.waitUntilReadStarts()
    settings.updateBaseURL("https://replacement.example.test")
    await reader.release()
    _ = try await firstCheck.value

    _ = try await useCase.check()

    let urls = await transport.requests.compactMap(\.url?.absoluteString)
    #expect(
      urls == [
        "http://127.0.0.1:8000/detect",
        "https://replacement.example.test/detect",
      ])
  }

  @Test(
    "one request contains only the Unicode selected text and maps every verdict",
    arguments: [
      ("jah", LanguageVerdict.estonian),
      ("ei", LanguageVerdict.notEstonian),
      ("ebakindel", LanguageVerdict.uncertain),
    ])
  func exactRequestAndVerdicts(wireVerdict: String, expected: LanguageVerdict) async throws {
    let transport = RecordingHTTPTransport(
      responses: [.success(response(status: 200, body: "{\"verdict\":\"\(wireVerdict)\"}"))]
    )
    let detector = LanguageAPIClient(transport: transport)

    let verdict = try await detector.detectLanguage(
      of: SelectedText("Tere, õun 🍎"),
      configuration: testLanguageConfiguration
    )

    #expect(verdict == expected)
    let requests = await transport.requests
    #expect(requests.count == 1)
    let request = try #require(requests.first)
    #expect(request.url?.absoluteString == "http://127.0.0.1:8000/detect")
    #expect(request.httpMethod == "POST")
    #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
    #expect(request.value(forHTTPHeaderField: "Accept") == "application/json")
    let requestBody = try #require(request.httpBody)
    let object = try #require(
      JSONSerialization.jsonObject(with: requestBody) as? [String: String]
    )
    #expect(object == ["text": "Tere, õun 🍎"])
  }

  @Test(
    "invalid responses map to stable failures",
    arguments: [
      (200, "{\"verdict\":\"maybe\"}", LanguageCheckFailure.incompatibleService),
      (200, "{}", LanguageCheckFailure.invalidResponse),
      (200, "not-json", LanguageCheckFailure.invalidResponse),
      (429, "PRIVATE SERVER BODY", LanguageCheckFailure.rateLimited),
      (503, "PRIVATE SERVER BODY", LanguageCheckFailure.serverFailure),
      (404, "PRIVATE SERVER BODY", LanguageCheckFailure.otherHTTPFailure),
    ])
  func stableResponseFailures(status: Int, body: String, expected: LanguageCheckFailure) async {
    let transport = RecordingHTTPTransport(
      responses: [.success(response(status: status, body: body))]
    )
    let detector = LanguageAPIClient(transport: transport)

    await #expect(throws: expected) {
      try await detector.detectLanguage(
        of: SelectedText("Tere"),
        configuration: testLanguageConfiguration
      )
    }
  }

  @Test(
    "transport errors map without retrying",
    arguments: [
      (URLError(.timedOut), LanguageCheckFailure.timeout),
      (URLError(.cannotConnectToHost), LanguageCheckFailure.unavailableService),
      (URLError(.secureConnectionFailed), LanguageCheckFailure.insecureConnection),
    ])
  func transportFailures(error: URLError, expected: LanguageCheckFailure) async {
    let transport = RecordingHTTPTransport(responses: [.failure(error)])
    let detector = LanguageAPIClient(transport: transport)

    await #expect(throws: expected) {
      try await detector.detectLanguage(
        of: SelectedText("Tere"),
        configuration: LanguageCheckConfiguration(
          validatedServiceBaseURL: "https://api.example.test"
        )
      )
    }
    #expect(await transport.requests.count == 1)
  }

  @Test("cancellation remains cancellation")
  func cancellation() async {
    let transport = RecordingHTTPTransport(responses: [.failure(CancellationError())])
    let detector = LanguageAPIClient(transport: transport)

    await #expect(throws: CancellationError.self) {
      try await detector.detectLanguage(
        of: SelectedText("Tere"),
        configuration: testLanguageConfiguration
      )
    }
  }

  @Test("ephemeral transport has the approved privacy and deadline configuration")
  func ephemeralConfiguration() {
    let configuration = LanguageAPITransport.makeConfiguration()

    #expect(configuration.identifier == nil)
    #expect(configuration.timeoutIntervalForRequest == 3)
    #expect(configuration.timeoutIntervalForResource == 3)
    #expect(configuration.urlCache == nil)
    #expect(configuration.requestCachePolicy == .reloadIgnoringLocalCacheData)
    #expect(configuration.httpCookieStorage == nil)
    #expect(configuration.urlCredentialStorage == nil)
    #expect(configuration.httpShouldSetCookies == false)
  }

  @Test("a redirect is rejected without retransmitting selected text")
  func rejectsRedirect() async {
    RedirectRecordingURLProtocol.reset()
    let configuration = LanguageAPITransport.makeConfiguration()
    configuration.protocolClasses = [RedirectRecordingURLProtocol.self]
    let detector = LanguageAPIClient(
      transport: LanguageAPITransport(configuration: configuration)
    )

    await #expect(throws: LanguageCheckFailure.otherHTTPFailure) {
      try await detector.detectLanguage(
        of: SelectedText("AINULT-ÜKS-KORD"),
        configuration: LanguageCheckConfiguration(
          validatedServiceBaseURL: "https://configured.example.test"
        )
      )
    }

    #expect(RedirectRecordingURLProtocol.requestedPaths() == ["/detect"])
    #expect(RedirectRecordingURLProtocol.redirectedRequestBodies().isEmpty)
  }
}

private actor URLSnapshotGatedSelectionReader: SelectionReading {
  private var firstReadStarted = false
  private var firstReadContinuation: CheckedContinuation<Void, Never>?

  func readSelectedText() async -> SelectedText {
    guard !firstReadStarted else { return SelectedText("Tere jälle") }
    firstReadStarted = true
    await withCheckedContinuation { firstReadContinuation = $0 }
    return SelectedText("Tere")
  }

  func waitUntilReadStarts() async {
    while !firstReadStarted { await Task.yield() }
  }

  func release() {
    firstReadContinuation?.resume()
    firstReadContinuation = nil
  }
}

@Suite("API base URL settings")
@MainActor
struct APIBaseURLSettingsTests {
  @Test("the default and exact loopback HTTP addresses are accepted")
  func loopbackPolicy() throws {
    #expect(APIBaseURL.default.url.absoluteString == "http://127.0.0.1:8000")
    #expect(try APIBaseURL(validating: "http://127.0.0.1:9000").url.port == 9000)
    #expect(try APIBaseURL(validating: "http://localhost:8000").url.host == "localhost")
    #expect(try APIBaseURL(validating: "http://[::1]:8000").url.host == "::1")
  }

  @Test(
    "remote HTTP and URL capabilities that can leak selected text are rejected",
    arguments: [
      "http://example.com",
      "https://user:secret@example.com",
      "https://example.com/api",
      "https://example.com?tenant=1",
      "https://example.com#detect",
      "ftp://example.com",
      "not a url",
    ])
  func rejectsUnsafeValues(value: String) {
    #expect(throws: APIBaseURL.ValidationError.self) {
      try APIBaseURL(validating: value)
    }
  }

  @Test("a valid edit applies immediately while an invalid edit retains the prior value")
  func immediateValidation() {
    let storage = MemoryAPISettingsStorage()
    let settings = APISettingsStore(storage: storage)

    settings.updateBaseURL("https://language.example.ee")
    #expect(settings.baseURL.url.absoluteString == "https://language.example.ee")
    #expect(storage.string(forKey: APISettingsStore.storageKey) == "https://language.example.ee")
    #expect(settings.validationMessage == nil)

    settings.updateBaseURL("http://language.example.ee")
    #expect(settings.baseURL.url.absoluteString == "https://language.example.ee")
    #expect(storage.string(forKey: APISettingsStore.storageKey) == "https://language.example.ee")
    #expect(settings.validationMessage != nil)
  }

  @Test("an invalid persisted value recovers to and persists the default")
  func recoversStoredValue() {
    let storage = MemoryAPISettingsStorage(values: [
      APISettingsStore.storageKey: "http://remote.example.ee"
    ])

    let settings = APISettingsStore(storage: storage)

    #expect(settings.baseURL == .default)
    #expect(storage.string(forKey: APISettingsStore.storageKey) == "http://127.0.0.1:8000")
  }
}

private actor RecordingHTTPTransport: LanguageAPITransporting {
  private(set) var requests: [URLRequest] = []
  private var responses: [Result<(Data, HTTPURLResponse), any Error>]

  init(responses: [Result<(Data, HTTPURLResponse), any Error>]) {
    self.responses = responses
  }

  func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
    requests.append(request)
    return try responses.removeFirst().get()
  }
}

private func response(status: Int, body: String) -> (Data, HTTPURLResponse) {
  (
    Data(body.utf8),
    HTTPURLResponse(
      url: URL(string: "http://127.0.0.1:8000/detect")!,
      statusCode: status,
      httpVersion: "HTTP/1.1",
      headerFields: ["Content-Type": "application/json"]
    )!
  )
}

private final class MemoryAPISettingsStorage: APISettingsPersisting, @unchecked Sendable {
  private var values: [String: String]

  init(values: [String: String] = [:]) {
    self.values = values
  }

  func string(forKey key: String) -> String? {
    values[key]
  }

  func set(_ value: String, forKey key: String) {
    values[key] = value
  }
}

private final class RedirectRecordingURLProtocol: URLProtocol, @unchecked Sendable {
  private static let recorder = RedirectRequestRecorder()

  static func reset() {
    recorder.reset()
  }

  static func requestedPaths() -> [String] {
    recorder.requestedPaths()
  }

  static func redirectedRequestBodies() -> [Data] {
    recorder.redirectedRequestBodies()
  }

  override class func canInit(with request: URLRequest) -> Bool {
    request.url?.host == "configured.example.test"
  }

  override class func canonicalRequest(for request: URLRequest) -> URLRequest {
    request
  }

  override func startLoading() {
    let path = request.url?.path ?? ""
    Self.recorder.record(path: path, body: request.httpBody)

    if path == "/detect" {
      let response = HTTPURLResponse(
        url: request.url!,
        statusCode: 307,
        httpVersion: "HTTP/1.1",
        headerFields: ["Location": "https://configured.example.test/redirected"]
      )!
      client?.urlProtocol(
        self,
        wasRedirectedTo: URLRequest(
          url: URL(string: "https://configured.example.test/redirected")!),
        redirectResponse: response
      )
      return
    }

    let response = HTTPURLResponse(
      url: request.url!,
      statusCode: 200,
      httpVersion: "HTTP/1.1",
      headerFields: ["Content-Type": "application/json"]
    )!
    client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
    client?.urlProtocol(self, didLoad: Data(#"{"verdict":"jah"}"#.utf8))
    client?.urlProtocolDidFinishLoading(self)
  }

  override func stopLoading() {}
}

private final class RedirectRequestRecorder: @unchecked Sendable {
  private let lock = NSLock()
  private var paths: [String] = []
  private var redirectedBodies: [Data] = []

  func reset() {
    lock.withLock {
      paths = []
      redirectedBodies = []
    }
  }

  func record(path: String, body: Data?) {
    lock.withLock {
      paths.append(path)
      if path == "/redirected", let body {
        redirectedBodies.append(body)
      }
    }
  }

  func requestedPaths() -> [String] {
    lock.withLock { paths }
  }

  func redirectedRequestBodies() -> [Data] {
    lock.withLock { redirectedBodies }
  }
}
