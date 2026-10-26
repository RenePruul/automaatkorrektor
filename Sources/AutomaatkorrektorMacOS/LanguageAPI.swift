import AutomaatkorrektorCore
import Foundation

protocol LanguageAPITransporting: Sendable {
  func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

struct LanguageAPIClient: LanguageDetecting, Sendable {
  private let baseURL: @Sendable () async -> URL
  private let transport: any LanguageAPITransporting

  init(
    baseURL: @escaping @Sendable () async -> URL,
    transport: any LanguageAPITransporting = LanguageAPITransport()
  ) {
    self.baseURL = baseURL
    self.transport = transport
  }

  func detectLanguage(of selectedText: SelectedText) async throws -> LanguageVerdict {
    let endpoint = await baseURL().appending(path: "detect", directoryHint: .notDirectory)
    var request = URLRequest(url: endpoint)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue("application/json", forHTTPHeaderField: "Accept")

    do {
      request.httpBody = try JSONEncoder().encode(RequestBody(text: selectedText.value))
    } catch {
      throw LanguageCheckFailure.invalidInput
    }

    do {
      let (data, response) = try await transport.data(for: request)
      try Task.checkCancellation()
      try validate(response)

      let body: ResponseBody
      do {
        body = try JSONDecoder().decode(ResponseBody.self, from: data)
      } catch {
        throw LanguageCheckFailure.invalidResponse
      }

      switch body.verdict {
      case "jah": return .estonian
      case "ei": return .notEstonian
      case "ebakindel": return .uncertain
      default: throw LanguageCheckFailure.incompatibleService
      }
    } catch is CancellationError {
      throw CancellationError()
    } catch let failure as LanguageCheckFailure {
      throw failure
    } catch let error as URLError {
      if Task.isCancelled || error.code == .cancelled {
        throw CancellationError()
      }
      throw map(error)
    } catch {
      throw LanguageCheckFailure.unavailableService
    }
  }

  private func validate(_ response: HTTPURLResponse) throws {
    switch response.statusCode {
    case 200...299: return
    case 429: throw LanguageCheckFailure.rateLimited
    case 500...599: throw LanguageCheckFailure.serverFailure
    default: throw LanguageCheckFailure.otherHTTPFailure
    }
  }

  private func map(_ error: URLError) -> LanguageCheckFailure {
    switch error.code {
    case .timedOut:
      return .timeout
    case .appTransportSecurityRequiresSecureConnection,
      .secureConnectionFailed,
      .serverCertificateHasBadDate,
      .serverCertificateUntrusted,
      .serverCertificateHasUnknownRoot,
      .serverCertificateNotYetValid,
      .clientCertificateRejected,
      .clientCertificateRequired:
      return .insecureConnection
    default:
      return .unavailableService
    }
  }

  private struct RequestBody: Encodable {
    let text: String
  }

  private struct ResponseBody: Decodable {
    let verdict: String
  }
}

final class LanguageAPITransport: LanguageAPITransporting, @unchecked Sendable {
  private let session: URLSession

  init(configuration: URLSessionConfiguration = LanguageAPITransport.makeConfiguration()) {
    session = URLSession(configuration: configuration)
  }

  func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
    let (data, response) = try await session.data(for: request)
    guard let httpResponse = response as? HTTPURLResponse else {
      throw LanguageCheckFailure.invalidResponse
    }
    return (data, httpResponse)
  }

  static func makeConfiguration() -> URLSessionConfiguration {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.timeoutIntervalForRequest = 3
    configuration.timeoutIntervalForResource = 3
    configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
    configuration.urlCache = nil
    configuration.httpCookieStorage = nil
    configuration.urlCredentialStorage = nil
    configuration.httpShouldSetCookies = false
    configuration.httpShouldUsePipelining = false
    configuration.httpMaximumConnectionsPerHost = 1
    return configuration
  }
}
