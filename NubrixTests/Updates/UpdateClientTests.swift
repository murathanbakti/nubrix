import XCTest
@testable import Nubrix

final class UpdateStubProtocol: URLProtocol {
    enum Behavior {
        case respond(status: Int, headers: [String: String], body: Data)
        case fail(Error)
    }

    struct Seen {
        let url: URL?
        let method: String?
        let headers: [String: String?]
    }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var seen: [Seen] = []
    nonisolated(unsafe) private static var script: [Behavior] = []
    nonisolated(unsafe) private static var fallback: Behavior = .respond(status: 200, headers: [:], body: Data())

    static let trackedHeaders = ["Authorization", "User-Agent", "Accept", "X-GitHub-Api-Version", "Cookie"]

    static func reset(script: [Behavior] = [], fallback: Behavior = .respond(status: 200, headers: [:], body: Data())) {
        lock.lock()
        defer { lock.unlock() }
        seen = []
        self.script = script
        self.fallback = fallback
    }

    static var requests: [Seen] {
        lock.lock()
        defer { lock.unlock() }
        return seen
    }

    private static func next(for request: URLRequest) -> Behavior {
        lock.lock()
        defer { lock.unlock() }
        var headers: [String: String?] = [:]
        for name in trackedHeaders { headers[name] = request.value(forHTTPHeaderField: name) }
        seen.append(Seen(url: request.url, method: request.httpMethod, headers: headers))
        return script.isEmpty ? fallback : script.removeFirst()
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        switch Self.next(for: request) {
        case .respond(let status, let headers, let body):
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: body)
            client?.urlProtocolDidFinishLoading(self)
        case .fail(let error):
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

final class UpdateClientTests: XCTestCase {
    private let testURL = URL(string: "https://api.github.com/repos/murathanbakti/nubrix/releases/latest")!

    override func setUp() {
        super.setUp()
        UpdateStubProtocol.reset()
    }

    override func tearDown() {
        UpdateStubProtocol.reset()
        super.tearDown()
    }

    private func makeClient(appVersion: String? = "0.1.1") -> UpdateClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [UpdateStubProtocol.self]
        return UpdateClient(url: testURL, configuration: configuration, appVersion: appVersion)
    }

    private func ok(_ json: String) -> UpdateStubProtocol.Behavior {
        .respond(status: 200, headers: ["Content-Type": "application/json"], body: Data(json.utf8))
    }

    private func status(_ code: Int, headers: [String: String] = [:]) -> UpdateStubProtocol.Behavior {
        .respond(status: code, headers: headers, body: Data(#"{"message":"x"}"#.utf8))
    }

    private func assertFetchFails(_ expected: UpdateFailure, file: StaticString = #filePath, line: UInt = #line) async {
        do {
            let version = try await makeClient().fetchLatest()
            XCTFail("expected \(expected), got \(version)", file: file, line: line)
        } catch {
            XCTAssertEqual(error as? UpdateFailure, expected, file: file, line: line)
        }
    }

    func testSuccessReturnsVersion() async throws {
        UpdateStubProtocol.reset(fallback: ok(#"{"tag_name":"v0.2.0","draft":false,"prerelease":false}"#))
        let version = try await makeClient().fetchLatest()
        XCTAssertEqual(version, ReleaseVersion(major: 0, minor: 2, patch: 0))
    }

    func testRequestShape() async throws {
        UpdateStubProtocol.reset(fallback: ok(#"{"tag_name":"v0.2.0"}"#))
        _ = try await makeClient(appVersion: "0.1.1").fetchLatest()
        let requests = UpdateStubProtocol.requests
        XCTAssertEqual(requests.count, 1)
        let request = try XCTUnwrap(requests.first)
        XCTAssertEqual(request.url, testURL)
        XCTAssertEqual(request.method, "GET")
        XCTAssertNil(request.headers["Authorization"] ?? nil)
        XCTAssertEqual(request.headers["User-Agent"] ?? nil, "Nubrix/0.1.1")
        XCTAssertEqual(request.headers["Accept"] ?? nil, "application/vnd.github+json")
        XCTAssertEqual(request.headers["X-GitHub-Api-Version"] ?? nil, "2022-11-28")
        XCTAssertNil(request.headers["Cookie"] ?? nil)
    }

    func testUserAgentNormalizesTwoComponentVersion() async throws {
        UpdateStubProtocol.reset(fallback: ok(#"{"tag_name":"v0.2.0"}"#))
        _ = try await makeClient(appVersion: "1.2").fetchLatest()
        XCTAssertEqual(UpdateStubProtocol.requests.first?.headers["User-Agent"] ?? nil, "Nubrix/1.2.0")
    }

    func testUserAgentFallsBackForUnknownVersion() async throws {
        UpdateStubProtocol.reset(fallback: ok(#"{"tag_name":"v0.2.0"}"#))
        _ = try await makeClient(appVersion: nil).fetchLatest()
        XCTAssertEqual(UpdateStubProtocol.requests.first?.headers["User-Agent"] ?? nil, "Nubrix/unknown")
    }

    func testNotFound() async {
        UpdateStubProtocol.reset(fallback: status(404))
        await assertFetchFails(.notFound)
    }

    func testRateLimitedByRemainingHeader() async {
        UpdateStubProtocol.reset(fallback: status(403, headers: ["x-ratelimit-remaining": "0"]))
        await assertFetchFails(.rateLimited)
    }

    func testRateLimitedBy429WithRetryAfter() async {
        UpdateStubProtocol.reset(fallback: status(429, headers: ["Retry-After": "60"]))
        await assertFetchFails(.rateLimited)
    }

    func testPlain403IsHTTPError() async {
        UpdateStubProtocol.reset(fallback: status(403))
        await assertFetchFails(.http(403))
    }

    func testRemainingNonZeroIs403HTTPError() async {
        UpdateStubProtocol.reset(fallback: status(403, headers: ["x-ratelimit-remaining": "12"]))
        await assertFetchFails(.http(403))
    }

    func testServerError() async {
        UpdateStubProtocol.reset(fallback: status(500))
        await assertFetchFails(.http(500))
    }

    func testRedirectIsRefusedAndTargetNeverRequested() async {
        UpdateStubProtocol.reset(fallback: .respond(status: 302, headers: ["Location": "https://evil.example/x"], body: Data()))
        await assertFetchFails(.redirected)
        let requests = UpdateStubProtocol.requests
        XCTAssertFalse(requests.contains { $0.url?.host == "evil.example" })
        XCTAssertEqual(requests.map(\.url), [testURL])
    }

    func testPermanentRedirectIsRefused() async {
        UpdateStubProtocol.reset(fallback: .respond(status: 301, headers: ["Location": "https://evil.example/x"], body: Data()))
        await assertFetchFails(.redirected)
        XCTAssertFalse(UpdateStubProtocol.requests.contains { $0.url?.host == "evil.example" })
    }

    func testTransportErrorIsNetwork() async {
        UpdateStubProtocol.reset(fallback: .fail(URLError(.notConnectedToInternet)))
        await assertFetchFails(.network)
    }

    func testTimeoutIsNetwork() async {
        UpdateStubProtocol.reset(fallback: .fail(URLError(.timedOut)))
        await assertFetchFails(.network)
    }

    func testMalformedBodyIsMalformed() async {
        UpdateStubProtocol.reset(fallback: ok("[]"))
        await assertFetchFails(.malformed)
    }

    func testPrereleaseBodyIsNotEligible() async {
        UpdateStubProtocol.reset(fallback: ok(#"{"tag_name":"v1.0.0","prerelease":true}"#))
        await assertFetchFails(.notEligible)
    }

    func testInvalidTagBody() async {
        UpdateStubProtocol.reset(fallback: ok(#"{"tag_name":"latest"}"#))
        await assertFetchFails(.invalidTag)
    }

    func testEachFetchIsOneRequest() async throws {
        UpdateStubProtocol.reset(fallback: ok(#"{"tag_name":"v0.2.0"}"#))
        let client = makeClient()
        _ = try await client.fetchLatest()
        _ = try await client.fetchLatest()
        XCTAssertEqual(UpdateStubProtocol.requests.count, 2)
    }

    func testNoRedirectDelegatePassesNil() {
        let session = URLSession(configuration: .ephemeral)
        defer { session.invalidateAndCancel() }
        let task = session.dataTask(with: testURL)
        let response = HTTPURLResponse(url: testURL, statusCode: 302, httpVersion: "HTTP/1.1", headerFields: ["Location": "https://evil.example/x"])!
        let newRequest = URLRequest(url: URL(string: "https://evil.example/x")!)
        let called = expectation(description: "completion handler called")
        var received: URLRequest?? = .none
        UpdateNoRedirect().urlSession(session, task: task, willPerformHTTPRedirection: response, newRequest: newRequest) { request in
            received = .some(request)
            called.fulfill()
        }
        wait(for: [called], timeout: 1)
        guard case .some(let request) = received else { return XCTFail("completion handler not called") }
        XCTAssertNil(request)
    }
}
