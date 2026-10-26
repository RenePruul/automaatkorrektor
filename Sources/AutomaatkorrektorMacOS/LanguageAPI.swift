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
  private let redirectDelegate: RejectingRedirectDelegate

  init(configuration: URLSessionConfiguration = LanguageAPITransport.makeConfiguration()) {
    let redirectDelegate = RejectingRedirectDelegate()
    self.redirectDelegate = redirectDelegate
    session = URLSession(
      configuration: configuration,
      delegate: redirectDelegate,
      delegateQueue: nil
    )
  }

  func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
    let taskBox = URLSessionTaskBox()
    let (data, response): (Data, URLResponse) = try await withTaskCancellationHandler {
      try Task.checkCancellation()
      return try await withCheckedThrowingContinuation {
        (continuation: CheckedContinuation<(Data, URLResponse), any Error>) in
        let task = session.dataTask(with: request) { data, response, error in
          if let identifier = taskBox.identifier,
            self.redirectDelegate.consumeRejection(for: identifier)
          {
            continuation.resume(throwing: LanguageCheckFailure.otherHTTPFailure)
          } else if let error {
            continuation.resume(throwing: error)
          } else if let data, let response {
            continuation.resume(returning: (data, response))
          } else {
            continuation.resume(throwing: LanguageCheckFailure.invalidResponse)
          }
        }
        taskBox.store(task)
        if Task.isCancelled {
          task.cancel()
        } else {
          task.resume()
        }
      }
    } onCancel: {
      taskBox.cancel()
    }

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

private final class RejectingRedirectDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable
{
  private let lock = NSLock()
  private var rejectedTaskIdentifiers: Set<Int> = []

  func urlSession(
    _ session: URLSession,
    task: URLSessionTask,
    willPerformHTTPRedirection response: HTTPURLResponse,
    newRequest request: URLRequest,
    completionHandler: @escaping (URLRequest?) -> Void
  ) {
    _ = lock.withLock {
      rejectedTaskIdentifiers.insert(task.taskIdentifier)
    }
    completionHandler(nil)
    task.cancel()
  }

  func consumeRejection(for taskIdentifier: Int) -> Bool {
    lock.withLock {
      rejectedTaskIdentifiers.remove(taskIdentifier) != nil
    }
  }
}

private final class URLSessionTaskBox: @unchecked Sendable {
  private let lock = NSLock()
  private var task: URLSessionTask?

  var identifier: Int? {
    lock.withLock { task?.taskIdentifier }
  }

  func store(_ task: URLSessionTask) {
    lock.withLock {
      self.task = task
    }
  }

  func cancel() {
    lock.withLock { task }?.cancel()
  }
}
