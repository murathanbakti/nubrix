import Foundation

final class UpdateNoRedirect: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

actor UpdateClient {
    static let apiVersion = "2022-11-28"

    private let url: URL
    private let session: URLSession
    private let userAgent: String

    init(url: URL = UpdateLinks.latestReleaseAPI, configuration: URLSessionConfiguration? = nil,
         appVersion: String? = Bundle.main.releaseVersionNumber) {
        self.url = url
        let configuration = configuration ?? URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 30
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCredentialStorage = nil
        session = URLSession(configuration: configuration)
        userAgent = "Nubrix/\(appVersion.flatMap { ReleaseVersion(bundleVersion: $0)?.description } ?? "unknown")"
    }

    func fetchLatest() async throws -> ReleaseVersion {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue(Self.apiVersion, forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        let data: Data
        let response: HTTPURLResponse
        do {
            let (d, r) = try await session.data(for: request, delegate: UpdateNoRedirect())
            guard let http = r as? HTTPURLResponse else { throw UpdateFailure.network }
            data = d
            response = http
        } catch let failure as UpdateFailure {
            throw failure
        } catch {
            throw UpdateFailure.network
        }
        guard let finalURL = response.url,
              finalURL.scheme?.lowercased() == url.scheme?.lowercased(),
              finalURL.host?.lowercased() == url.host?.lowercased()
        else { throw UpdateFailure.redirected }
        switch response.statusCode {
        case 200:
            return try UpdateParsing.latestVersion(from: data)
        case 403, 429:
            let exhausted = response.value(forHTTPHeaderField: "x-ratelimit-remaining") == "0"
            if exhausted || response.value(forHTTPHeaderField: "retry-after") != nil { throw UpdateFailure.rateLimited }
            throw UpdateFailure.http(response.statusCode)
        case 404:
            throw UpdateFailure.notFound
        case 300..<400:
            throw UpdateFailure.redirected
        default:
            throw UpdateFailure.http(response.statusCode)
        }
    }
}
