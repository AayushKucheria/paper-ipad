import XCTest
import PDFKit
import UIKit
import WebKit
@testable import Paper

@MainActor final class ArticleTests: XCTestCase {
    // PDFKit inserts line breaks at wrapping and occasionally before punctuation following raised glyphs.
    // Compare every original word and punctuation mark while ignoring those layout-only boundaries.
    private func canonicalPDFText(_ text: String) -> String {
        text.replacingOccurrences(of: "\\s+([.,;:!?])", with: "$1", options: .regularExpression)
            .split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }
    func testJavaScriptBodyWaitsForPromiseResolution() async throws {
        let loaded = expectation(description: "WebKit navigation completed")
        let observer = ArticleTestNavigationObserver(loaded: loaded)
        let web = WKWebView(frame: CGRect(x: 0, y: 0, width: 468, height: 680))
        web.navigationDelegate = observer
        defer { web.navigationDelegate = nil; web.stopLoading(); _ = observer }
        web.loadHTMLString("<html><body>Waiting</body></html>", baseURL: nil)
        await fulfillment(of: [loaded], timeout: 15)
        XCTAssertFalse(observer.failed)
        let result = try await ArticleRenderer().runJavaScript(in: web, body: "await new Promise(resolve => setTimeout(resolve, 80)); document.body.dataset.ready = 'resolved'; return document.body.dataset.ready;", arguments: [:])
        XCTAssertEqual(result as? String, "resolved", "Article preparation must await the actual JavaScript completion, including a pending Promise")
        let evaluated = try await ArticleRenderer().evaluateJavaScript(in: web, source: "document.body.dataset.ready")
        XCTAssertEqual(evaluated as? String, "resolved", "Legacy completion evaluation must return the inserted body state")
        do {
            _ = try await ArticleRenderer().evaluateJavaScript(in: web, source: "throw new Error('synthetic failure')")
            XCTFail("A failed WebKit evaluation must produce a recoverable article error")
        } catch { XCTAssertEqual(error as? ArticleRenderError, .failed) }
    }
    func testRealHTMLMakesMultipleSelectablePDFPagesAndRetainsText() async throws {
        let sentence = "An equation relates energy to mass: E = mc². Handwriting needs stable pages."
        let html = (0..<65).map { "<p>Paragraph \($0). \(sentence)</p>" }.joined()
        let rendered = try await ArticleRenderer().render(html: html, title: "Physics", baseURL: nil)
        let pdf = try XCTUnwrap(PDFDocument(data: rendered.pdf))
        let pdfAttachment = XCTAttachment(data: rendered.pdf, uniformTypeIdentifier: "com.adobe.pdf")
        pdfAttachment.name = "article-pagination"; pdfAttachment.lifetime = .keepAlways; add(pdfAttachment)
        print("paper_synthetic_pagination_text=\(String((pdf.string ?? "").prefix(450)).debugDescription)")
        XCTAssertGreaterThan(pdf.pageCount, 1)
        XCTAssertTrue(rendered.text.contains(sentence))
        XCTAssertTrue(canonicalPDFText(pdf.string ?? "").contains(sentence), "Every word and punctuation mark of the source sentence must remain selectable across line wraps")
        XCTAssertTrue(pdf.string?.contains("Paragraph 64") == true, "Pagination must preserve the end of the article")
    }
    func testFullHTMLUsesBodyAndPreservesOneTitleWithHandwritingMargins() async throws {
        let html = "<!doctype html><html><head><title>Hidden document metadata</title><style>body { width:4000px; } p { font-size:1px; }</style></head><body><h1>Reading physics</h1><p>A full document still needs readable text and margins.</p><p>The last sentence survives.</p></body></html>"
        let rendered = try await ArticleRenderer().render(html: html, title: "Reading physics", baseURL: nil)
        let pdf = try XCTUnwrap(PDFDocument(data: rendered.pdf))
        XCTAssertFalse(rendered.text.contains("Hidden document metadata"))
        XCTAssertTrue(rendered.text.contains("The last sentence survives."))
        let content = try XCTUnwrap(pdf.string)
        XCTAssertEqual(content.components(separatedBy: "Reading physics").count - 1, 1, "Title should appear once when Reader already includes it")
        let page = try XCTUnwrap(pdf.page(at: 0))
        let quote = try XCTUnwrap(pdf.findString("A full document", withOptions: []).first)
        XCTAssertGreaterThan(quote.bounds(for: page).height, 10, "Source document styles must not shrink reading text")
        XCTAssertLessThanOrEqual(quote.bounds(for: page).maxX, 512, "Keep the right margin free for handwriting")
    }
    func testEquationAndFigureRemainVisibleInPreparedPDF() async throws {
        let green = UIGraphicsImageRenderer(size: CGSize(width: 80, height: 80)).image { context in
            UIColor.green.setFill(); context.fill(CGRect(x: 0, y: 0, width: 80, height: 80))
        }
        let image = try XCTUnwrap(green.pngData()).base64EncodedString()
        let html = "<p>Energy: E = mc².</p><math xmlns='http://www.w3.org/1998/Math/MathML'><mfrac><mi>numerator</mi><mi>denominator</mi></mfrac></math><p>Figure:</p><img width='80' height='80' src='data:image/png;base64,\(image)'>"
        let rendered = try await ArticleRenderer().render(html: html, title: "Equations and figures", baseURL: nil)
        let pdf = try XCTUnwrap(PDFDocument(data: rendered.pdf))
        let pdfAttachment = XCTAttachment(data: rendered.pdf, uniformTypeIdentifier: "com.adobe.pdf")
        pdfAttachment.name = "article-equations-figures"; pdfAttachment.lifetime = .keepAlways; add(pdfAttachment)
        print("paper_synthetic_equation_text=\((pdf.string ?? "").debugDescription)")
        XCTAssertTrue(canonicalPDFText(pdf.string ?? "").contains("Energy: E = mc²."), "Selectable equation must retain its superscript and punctuation")
        XCTAssertTrue(pdf.string?.contains("numerator") == true, "Native MathML numerator should retain selectable text")
        XCTAssertTrue(pdf.string?.contains("denominator") == true, "Native MathML denominator should retain selectable text")
        let page = try XCTUnwrap(pdf.page(at: 0))
        let thumbnail = page.thumbnail(of: CGSize(width: 612, height: 792), for: .mediaBox)
        let cgImage = try XCTUnwrap(thumbnail.cgImage)
        let width = cgImage.width, height = cgImage.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let greenPixels = pixels.withUnsafeMutableBytes { bytes -> Int in
            guard let context = CGContext(data: bytes.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return 0 }
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
            let buffer = bytes.bindMemory(to: UInt8.self)
            return stride(from: 0, to: buffer.count, by: 4).filter { buffer[$0] < 90 && buffer[$0 + 1] > 150 && buffer[$0 + 2] < 90 }.count
        }
        XCTAssertGreaterThan(greenPixels, 500, "Prepared PDF must contain the article figure, not just its text")
    }
    func testUnavailableFigureIsVisibleAndExcludedFromOriginalSource() async throws {
        let original = "A physics explanation needs its diagram."
        let rendered = try await ArticleRenderer().render(html: "<p>\(original)</p><img alt='Diagram' src='data:image/png;base64,bm90YW5pbWFnZQ=='>", title: "Missing figure", baseURL: nil)
        XCTAssertEqual(rendered.missingFigureCount, 1)
        XCTAssertEqual(rendered.text, original, "Generated figure warnings must not enter retained Reader source text")
        let pdf = try XCTUnwrap(PDFDocument(data: rendered.pdf))
        let visible = canonicalPDFText(pdf.string ?? "")
        XCTAssertTrue(visible.contains("Paper: 1 figure unavailable"), "The reading copy must warn prominently about unavailable figures")
        XCTAssertTrue(visible.contains("Figure unavailable in Paper"), "A missing figure must retain a visible placeholder at its source position")
        XCTAssertTrue(visible.contains(original))
        XCTAssertFalse(rendered.text.contains("Figure unavailable"))
        let attachment = XCTAttachment(data: rendered.pdf, uniformTypeIdentifier: "com.adobe.pdf")
        attachment.name = "article-unavailable-figure-warning"; attachment.lifetime = .keepAlways; add(attachment)
    }
    func testEmptyArticleCannotPublishBlankPDF() async throws {
        do {
            _ = try await ArticleRenderer().render(html: "<p> </p>", title: "Blank", baseURL: nil)
            XCTFail("Blank article must not create a readable document")
        } catch { XCTAssertEqual(error as? ArticleRenderError, .emptyContent) }
    }
}

final class ArticleStorageTests: XCTestCase {
    func testArticleSourceAndOriginalIdentitySurviveReopenWithoutReplacingInk() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = DocumentStore(root: root)
        let pdf = PDFDocument(); pdf.insert(PDFPage(), at: 0)
        let source = root.deletingLastPathComponent().appendingPathComponent("\(UUID().uuidString).pdf")
        defer { try? FileManager.default.removeItem(at: source) }
        try XCTUnwrap(pdf.dataRepresentation()).write(to: source)
        let metadata = ReaderPDF(id: "original-article", title: "Original article")
        let document = try store.importReaderArticle(at: source, metadata: metadata, html: "<p>Source sentence.</p>", text: "Source sentence.", missingFigures: 2)
        XCTAssertEqual(document.readerID, "original-article")
        XCTAssertTrue(document.preparationWarning?.contains("2 figures") == true)
        XCTAssertEqual(try store.documents().first?.preparationWarning, document.preparationWarning)
        XCTAssertEqual(try store.articleText(for: document), "Source sentence.")
        let reading = try store.workingPDFURL(for: document)
        let before = try Data(contentsOf: reading)
        let same = try store.importReaderArticle(at: source, metadata: metadata, html: "replacement", text: "replacement")
        XCTAssertEqual(same.id, document.id)
        XCTAssertEqual(try Data(contentsOf: reading), before)
        XCTAssertEqual(try store.articleText(for: document), "Source sentence.")
    }
}

private actor ArticleServiceFixture: ReaderServing {
    private(set) var contentRequests = 0
    func listPDFs(progress: @escaping @Sendable (Int) -> Void) async throws -> [ReaderPDF] { [] }
    func listArticles(progress: @escaping @Sendable (Int) -> Void) async throws -> [ReaderPDF] { throw ReaderAPIError.networkFailure }
    func articleContent(id: String) async throws -> String { contentRequests += 1; throw ReaderAPIError.networkFailure }
    func downloadPDF(id: String, progress: @escaping @Sendable (Int64, Int64?) -> Void) async throws -> URL { throw ReaderAPIError.networkFailure }
}

@MainActor final class ArticleLibraryTests: XCTestCase {
    func testFailedArticleRefreshKeepsArticleAndPDFCatalogsSeparate() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let pdfCatalog = ReaderCatalog(url: root.appendingPathComponent("reader-catalog.json"))
        let articleCatalog = ReaderCatalog(url: root.appendingPathComponent("reader-articles.json"))
        let article = ReaderPDF(id: "article", title: "Saved article")
        let pdf = ReaderPDF(id: "pdf", title: "Saved PDF")
        try articleCatalog.save([article], syncedAt: Date())
        try pdfCatalog.save([pdf], syncedAt: Date())
        let model = ReaderLibraryModel(store: DocumentStore(root: root.appendingPathComponent("Library")), catalog: pdfCatalog, api: ArticleServiceFixture())
        await model.refreshArticles()
        XCTAssertEqual(model.articles, [article])
        XCTAssertEqual(model.pdfs, [pdf])
        XCTAssertEqual(try articleCatalog.load()?.documents, [article])
        XCTAssertNotNil(model.articleError)
    }
    func testPreparingRetainedArticleReusesOriginalLocalCopyOffline() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let store = DocumentStore(root: root.appendingPathComponent("Library"))
        let file = root.appendingPathComponent("fixture.pdf")
        try UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 612, height: 792)).pdfData { context in
            context.beginPage(); ("Retained article" as NSString).draw(at: CGPoint(x: 40, y: 40), withAttributes: nil)
        }.write(to: file)
        let metadata = ReaderPDF(id: "original-article", title: "Retained article")
        let document = try store.importReaderArticle(at: file, metadata: metadata, html: "<p>Retained article</p>", text: "Retained article")
        let service = ArticleServiceFixture()
        let model = ReaderLibraryModel(store: store, catalog: ReaderCatalog(url: root.appendingPathComponent("reader-catalog.json")), api: service)
        let retained = await model.prepareArticle(metadata)
        XCTAssertEqual(retained?.id, document.id)
        let calls = await service.contentRequests
        XCTAssertEqual(calls, 0, "Preparing a downloaded article must never replace its pages or handwritten edits")
    }
}

@MainActor final class ArticleLiveReadOnlyTests: XCTestCase {
    /// Opt in on the installed physical app host. Reads Reader once; writes neither Reader nor Documents.
    func testLiveArticleReadOnlyRender() async throws {
        guard ProcessInfo.processInfo.environment["PAPER_LIVE_ARTICLE"] == "1" else {
            throw XCTSkip("Set TEST_RUNNER_PAPER_LIVE_ARTICLE=1 to read and render one real Reader article.")
        }
        #if targetEnvironment(simulator)
        throw XCTSkip("This test uses the installed iPad app’s Reader Keychain credential.")
        #else
        guard let token = try ReaderCredentials().read(), !token.isEmpty else {
            XCTFail("Connect Reader on the iPad before running the live article test."); return
        }
        var components = URLComponents(string: "https://readwise.io/api/v3/list/")!
        components.queryItems = [URLQueryItem(name: "category", value: "article"), URLQueryItem(name: "limit", value: "1"), URLQueryItem(name: "withHtmlContent", value: "true")]
        var request = URLRequest(url: components.url!)
        request.timeoutInterval = 90
        request.setValue("Token \(token)", forHTTPHeaderField: "Authorization")
        let session = URLSession(configuration: .ephemeral)
        defer { session.invalidateAndCancel() }
        let (data, response) = try await session.data(for: request, delegate: NoCredentialRedirects())
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            XCTFail("Reader article retrieval did not succeed."); return
        }
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let record = (object?["results"] as? [[String: Any]])?.first,
              record["category"] as? String == "article", record["parent_id"] is NSNull || record["parent_id"] == nil,
              let html = record["html_content"] as? String, !html.isEmpty else {
            XCTFail("Reader did not return a parent article with HTML content."); return
        }
        let source = (record["source_url"] as? String).flatMap(URL.init(string:))
        let temporary = FileManager.default.temporaryDirectory
        try Data(html.utf8).write(to: temporary.appendingPathComponent("paper-live-article.html"), options: .atomic)
        let metadata: [String: String] = ["title": record["title"] as? String ?? "Article", "source_url": source?.absoluteString ?? ""]
        try JSONSerialization.data(withJSONObject: metadata).write(to: temporary.appendingPathComponent("paper-live-article-metadata.json"), options: .atomic)
        let rendered: RenderedArticle
        do {
            rendered = try await ArticleRenderer().render(html: html, title: record["title"] as? String ?? "Article", baseURL: source)
        } catch {
            let diagnostic = error as NSError
            let kind: String
            switch error as? ArticleRenderError {
            case .emptyContent: kind = "emptyContent"
            case .failed: kind = "failed"
            case .timedOut: kind = "timedOut"
            case .missingImages: kind = "missingImages"
            case nil: kind = "other"
            }
            print("paper_live_article_error kind=\(kind) domain=\(diagnostic.domain) code=\(diagnostic.code)")
            throw error
        }
        let pdf = try XCTUnwrap(PDFDocument(data: rendered.pdf))
        XCTAssertGreaterThan(pdf.pageCount, 0)
        XCTAssertGreaterThan(rendered.text.count, 20)
        XCTAssertFalse((pdf.string ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        let longWords = rendered.text.split(whereSeparator: { $0.isWhitespace }).filter { $0.count > 7 }
        XCTAssertTrue(longWords.prefix(20).contains { pdf.string?.contains(String($0)) == true }, "Prepared PDF must retain original article text")
        let pdfAttachment = XCTAttachment(data: rendered.pdf, uniformTypeIdentifier: "com.adobe.pdf")
        pdfAttachment.name = "live-reader-article"; pdfAttachment.lifetime = .keepAlways; add(pdfAttachment)
        print("paper_live_article_read_only missingFigures=\(rendered.missingFigureCount) pages=\(pdf.pageCount) sourceCharacters=\(rendered.text.count) bytes=\(rendered.pdf.count)")
        #endif
    }
}


@MainActor private final class ArticleTestNavigationObserver: NSObject, WKNavigationDelegate {
    let loaded: XCTestExpectation
    var failed = false
    init(loaded: XCTestExpectation) { self.loaded = loaded }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { loaded.fulfill() }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { failed = true; loaded.fulfill() }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { failed = true; loaded.fulfill() }
}
