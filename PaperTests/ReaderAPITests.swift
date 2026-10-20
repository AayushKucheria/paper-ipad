import XCTest
@testable import Paper

private final class ReaderURLProtocol: URLProtocol, @unchecked Sendable {
    static var handle: ((URLRequest) throws -> (Int, [String: String], Data))!
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            let (status, headers, data) = try Self.handle(request)
            client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: headers)!, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}
final class ReaderAPITests: XCTestCase {
    func api() -> ReaderAPI {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [ReaderURLProtocol.self]
        return ReaderAPI(token: "test-secret", session: URLSession(configuration: config), minimumRequestInterval: 0)
    }
    func testPaginationFiltersChildrenAndDeduplicatesAndDecodesNullMetadata() async throws {
        var calls = 0
        ReaderURLProtocol.handle = { request in
            calls += 1
            let query = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!.queryItems!
            XCTAssertTrue(query.contains(URLQueryItem(name: "category", value: "pdf")))
            XCTAssertTrue(query.contains(URLQueryItem(name: "withRawSourceUrl", value: "true")))
            XCTAssertFalse(query.contains { $0.name == "location" })
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Token test-secret")
            let json = calls == 1 ? #"{"results":[{"id":"one","category":"pdf","parent_id":null,"title":null,"author":null,"summary":null,"raw_source_url":"https://files.example/secret"},{"id":"child","category":"pdf","parent_id":"one"}],"nextPageCursor":"next"}"# : #"{"results":[{"id":"one","category":"pdf"},{"id":"two","category":"pdf"},{"id":"article","category":"article"}],"nextPageCursor":null}"#
            if calls == 2 { XCTAssertTrue(query.contains(URLQueryItem(name: "pageCursor", value: "next"))) }
            return (200, [:], Data(json.utf8))
        }
        let result = try await api().listPDFs { _ in }
        XCTAssertEqual(result.map(\.id), ["one", "two"])
        XCTAssertNil(result.first?.title)
        XCTAssertEqual(result.map(\.hasDownload), [true, false])
        XCTAssertEqual(calls, 2)
        let persisted = String(data: try JSONEncoder().encode(result), encoding: .utf8)!
        XCTAssertFalse(persisted.contains("secret"))
    }
    func testCursorLoopFailsWithoutLeakingResponse() async throws {
        var calls = 0
        ReaderURLProtocol.handle = { _ in
            calls += 1
            return (200, [:], Data(#"{"results":[],"nextPageCursor":"same"}"#.utf8))
        }
        do { _ = try await api().listPDFs { _ in }; XCTFail("Repeated cursors must fail") }
        catch { XCTAssertFalse(error.localizedDescription.contains("test-secret")) }
        XCTAssertEqual(calls, 2)
    }
    func testAuthenticationFailureHasSafeActionableMessage() async throws {
        ReaderURLProtocol.handle = { _ in (401, [:], Data("private-server-body test-secret".utf8)) }
        do { _ = try await api().listPDFs { _ in }; XCTFail("Authentication must fail") }
        catch {
            XCTAssertTrue(error.localizedDescription.lowercased().contains("token"))
            XCTAssertFalse(error.localizedDescription.contains("test-secret"))
            XCTAssertFalse(error.localizedDescription.contains("private-server-body"))
        }
    }
    func testThrottleRetriesAreBounded() async throws {
        var calls = 0
        ReaderURLProtocol.handle = { _ in calls += 1; return (429, ["Retry-After": "0"], Data()) }
        do { _ = try await api().listPDFs { _ in }; XCTFail("Persistent throttle must fail") }
        catch { XCTAssertTrue(error.localizedDescription.lowercased().contains("wait")) }
        XCTAssertEqual(calls, 3)
    }
    func testDownloadRefreshesExpiredSourceAndNeverSendsReaderTokenToFileHost() async throws {
        var resolves = 0, downloads = 0
        ReaderURLProtocol.handle = { request in
            if request.url!.host == "readwise.io" {
                resolves += 1
                XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Token test-secret")
                let query = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!.queryItems!
                XCTAssertTrue(query.contains(URLQueryItem(name: "id", value: "one")))
                return (200, [:], Data(#"{"results":[{"id":"one","category":"pdf","raw_source_url":"https://files.example/file.pdf"}]}"#.utf8))
            }
            downloads += 1
            XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
            return downloads == 1 ? (403, [:], Data()) : (200, ["Content-Type": "application/pdf"], Data("%PDF-test".utf8))
        }
        let url = try await api().downloadPDF(id: "one") { _, _ in }
        defer { try? FileManager.default.removeItem(at: url) }
        XCTAssertEqual(try Data(contentsOf: url), Data("%PDF-test".utf8))
        XCTAssertEqual(resolves, 2)
        XCTAssertEqual(downloads, 2)
    }
    func testUnavailableOrInsecureSourceDoesNotAttemptDownload() async throws {
        for source in ["null", #""http://unsafe.example/file.pdf""#] {
            var calls = 0
            ReaderURLProtocol.handle = { _ in
                calls += 1
                return (200, [:], Data((#"{"results":[{"id":"one","raw_source_url":"# + source + "}]}" ).utf8))
            }
            do { _ = try await api().downloadPDF(id: "one") { _, _ in }; XCTFail("Unsafe or missing source must fail") }
            catch { XCTAssertFalse(error.localizedDescription.contains("unsafe.example")) }
            XCTAssertEqual(calls, 1)
        }
    }

    func testMissingReaderLinkRecoversRecognizedGitHubPDFWithoutCredentials() async throws {
        let source = URL(string: "https://github.com/example/research/blob/main/papers/paper.pdf")!
        let metadata = ReaderPDF(id: "github", sourceURL: source, hasDownload: false)
        XCTAssertTrue(metadata.canDownload, "Recognized GitHub PDF preview has a public raw download route")
        var downloads = 0
        ReaderURLProtocol.handle = { request in
            if request.url!.host == "readwise.io" {
                return (200, [:], Data(#"{"results":[{"id":"github","category":"pdf","source_url":"https://github.com/example/research/blob/main/papers/paper.pdf"}]}"#.utf8))
            }
            downloads += 1
            XCTAssertEqual(request.url!.host, "github.com")
            XCTAssertEqual(request.url!.path, "/example/research/blob/main/papers/paper.pdf")
            XCTAssertTrue(URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!.queryItems!.contains(URLQueryItem(name: "raw", value: "true")))
            XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
            return (200, [:], Data("%PDF-github".utf8))
        }
        let file = try await api().downloadPDF(id: "github") { _, _ in }
        defer { try? FileManager.default.removeItem(at: file) }
        XCTAssertEqual(try Data(contentsOf: file), Data("%PDF-github".utf8))
        XCTAssertEqual(downloads, 1)
    }

    func testSourceFallbackIsLimitedToSecureGitHubPDFBlobURLs() {
        let rejected = [
            "http://github.com/example/research/blob/main/paper.pdf",
            "https://github.com.evil.example/example/research/blob/main/paper.pdf",
            "https://user:password@github.com/example/research/blob/main/paper.pdf",
            "https://github.com:8443/example/research/blob/main/paper.pdf",
            "https://github.com/example/research/issues/paper.pdf",
            "https://github.com/example/research/blob/main/paper.pdf.html",
            "https://example.com/paper.pdf"
        ]
        for source in rejected {
            XCTAssertFalse(ReaderPDF(id: "one", sourceURL: URL(string: source), hasDownload: false).canDownload)
        }
    }

    func testEmptyAndNullRawSourceLinksAreUnavailable() async throws {
        ReaderURLProtocol.handle = { _ in
            (200, [:], Data(#"{"results":[{"id":"empty","category":"pdf","raw_source_url":""},{"id":"null","category":"pdf","raw_source_url":null}],"nextPageCursor":null}"#.utf8))
        }
        let results = try await api().listPDFs { _ in }
        XCTAssertEqual(results.map(\.id), ["empty", "null"])
        XCTAssertEqual(results.map(\.hasDownload), [false, false])
        XCTAssertEqual(results.map(\.canDownload), [false, false])
        do {
            _ = try await api().downloadPDF(id: "empty") { _, _ in }
            XCTFail("An empty raw source must be treated as absent")
        } catch {
            guard case ReaderAPIError.unavailableSource = error else {
                return XCTFail("Empty source should report missing original, not an insecure download")
            }
        }
    }

}
