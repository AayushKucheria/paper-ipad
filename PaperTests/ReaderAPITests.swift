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
    func testArticlesListFiltersChildrenAndRetainsOriginalIdentity() async throws {
        ReaderURLProtocol.handle = { request in
            let query = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!.queryItems!
            XCTAssertTrue(query.contains(URLQueryItem(name: "category", value: "article")))
            XCTAssertFalse(query.contains { $0.name == "withHtmlContent" })
            return (200, [:], Data(#"{"results":[{"id":"original-article","category":"article","title":"An article"},{"id":"child","category":"article","parent_id":"original-article"},{"id":"book","category":"epub"}],"nextPageCursor":null}"#.utf8))
        }
        let result = try await api().listArticles { _ in }
        XCTAssertEqual(result.map(\.id), ["original-article"], "Article conversion must keep the original Reader identity")
    }
    func testArticleContentUsesReadersHTML() async throws {
        ReaderURLProtocol.handle = { request in
            let query = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!.queryItems!
            XCTAssertTrue(query.contains(URLQueryItem(name: "withHtmlContent", value: "true")))
            XCTAssertTrue(query.contains(URLQueryItem(name: "id", value: "original-article")))
            return (200, [:], Data(#"{"results":[{"id":"original-article","category":"article","html_content":"<p>The equation is E = mc².</p>"}],"nextPageCursor":null}"#.utf8))
        }
        let content = try await api().articleContent(id: "original-article")
        XCTAssertEqual(content, "<p>The equation is E = mc².</p>")
    }
    func testArticleContentCannotUseAnUnrelatedRecord() async throws {
        ReaderURLProtocol.handle = { _ in
            (200, [:], Data(#"{"results":[{"id":"other","category":"article","html_content":"<p>Wrong item</p>"},{"id":"wanted","category":"article","parent_id":"other","html_content":"<p>Child item</p>"}]}"#.utf8))
        }
        do { _ = try await api().articleContent(id: "wanted"); XCTFail("Only the original parent article may supply content") }
        catch { XCTAssertTrue(error is ReaderAPIError) }
    }
    func testEpubListUsesDocumentedParametersAndDecodesRealUploadShapes() async throws {
        ReaderURLProtocol.handle = { request in
            let query = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!.queryItems!
            XCTAssertEqual(Set(query.map(\.name)), ["category", "limit", "withRawSourceUrl"])
            XCTAssertTrue(query.contains(URLQueryItem(name: "category", value: "epub")))
            XCTAssertTrue(query.contains(URLQueryItem(name: "withRawSourceUrl", value: "true")))
            // Shapes observed for uploaded EPUBs: empty source_url/author/image_url, private:// source_url, null title.
            return (200, [:], Data(#"{"count":3,"nextPageCursor":null,"results":[{"id":"broken","category":"epub","title":null,"author":"","source_url":"","image_url":"","url":"https://read.readwise.io/read/broken","summary":"Your file was uploaded but we were unable to load and read it.","reading_progress":0,"raw_source_url":""},{"id":"good","category":"epub","title":"A book","author":"An author","source_url":"private://read/good","image_url":"https://img.example/c.jpg","url":"https://read.readwise.io/read/good","reading_progress":0.02,"raw_source_url":"https://files.example/good.epub"},{"id":"nulls","category":"epub","title":null,"source_url":null,"url":"","raw_source_url":null}]}"#.utf8))
        }
        let books = try await api().listBooks { _ in }
        XCTAssertEqual(books.map(\.id), ["broken", "good", "nulls"], "One odd record must not hide the whole EPUB catalog")
        XCTAssertEqual(books.map(\.hasDownload), [false, true, false])
        XCTAssertEqual(books[1].title, "A book")
    }
    func testOneUndecodableRecordDoesNotDropTheRestOfAPage() async throws {
        ReaderURLProtocol.handle = { _ in
            (200, [:], Data(#"{"results":[{"id":"a","category":"epub"},{"id":42,"category":"epub"},{"category":"epub"},null,"text",7,{"id":"b","category":"epub"}],"nextPageCursor":null}"#.utf8))
        }
        let books = try await api().listBooks { _ in }
        XCTAssertEqual(books.map(\.id), ["a", "b"])
    }
    func testBookDownloadResolvesFreshEpubSourceWithoutToken() async throws {
        var sawToken = false
        ReaderURLProtocol.handle = { request in
            if request.url!.host == "files.example" { sawToken = request.value(forHTTPHeaderField: "Authorization") != nil; return (200, [:], Data("epub".utf8)) }
            let query = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!.queryItems!
            XCTAssertTrue(query.contains(URLQueryItem(name: "id", value: "book")))
            XCTAssertTrue(query.contains(URLQueryItem(name: "withRawSourceUrl", value: "true")))
            return (200, [:], Data(#"{"results":[{"id":"book","category":"epub","source_url":"","raw_source_url":"https://files.example/book.epub"}]}"#.utf8))
        }
        let file = try await api().downloadBook(id: "book") { _, _ in }
        defer { try? FileManager.default.removeItem(at: file) }
        XCTAssertFalse(sawToken)
    }
    func testMalformedOptionalCoverDoesNotAbortValidPDFCatalog() async throws {
        ReaderURLProtocol.handle = { _ in
            (200, [:], Data(#"{"results":[{"id":"bad-cover","category":"pdf","title":"Keep this document","image_url":"http://["},{"id":"valid-cover","category":"pdf","image_url":"https://images.example/cover.jpg"}],"nextPageCursor":null}"#.utf8))
        }
        let records = try await api().listPDFs { _ in }
        XCTAssertEqual(records.map(\.id), ["bad-cover","valid-cover"])
        XCTAssertNil(records.first?.imageURL, "Malformed optional cover should fall back without dropping metadata")
        XCTAssertEqual(records.last?.imageURL?.host, "images.example")
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
