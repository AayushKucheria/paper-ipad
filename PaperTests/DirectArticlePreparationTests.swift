import XCTest
@testable import Paper

final class DirectArticlePreparationTests: XCTestCase {
    @MainActor
    func testPersistsOfflineArticleAndKeepsCanonicalTextSeparateFromReadingLabels() async throws {
        let html = """
        <!doctype html><html><head><style>p{display:none}</style><script>throw new Error('forbidden')</script></head>
        <body><p onclick="alert(1)">A precise source sentence.</p>
        <img src="http://invalid.example/pic.png" alt="An illustration">
        <img src="data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aRwAAAABJRU5ErkJggg==" alt="A local figure">
        </body></html>
        """
        let snapshot = try await DirectArticlePreparation().prepare(html: html, title: "Sample article", baseURL: nil) { _ in }
        XCTAssertEqual(snapshot.text, "A precise source sentence.")
        XCTAssertEqual(snapshot.missingFigures, 1)
        XCTAssertTrue(snapshot.html.contains(">Sample article</h1>"))
        XCTAssertTrue(snapshot.html.contains("Figure unavailable · An illustration"))
        XCTAssertTrue(snapshot.html.contains("data:image/png;base64,"))
        XCTAssertFalse(snapshot.html.contains("onclick"))
        XCTAssertFalse(snapshot.html.contains("invalid.example"))
        XCTAssertFalse(snapshot.html.contains("throw new Error"))

        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = DocumentStore(root: folder)
        let document = try store.importDirectArticle(metadata: ReaderPDF(id: "article-id", title: "Sample article"),
                                                      originalHTML: html, readingHTML: snapshot.html,
                                                      sourceText: snapshot.text, missingFigures: snapshot.missingFigures)
        XCTAssertEqual(document.readerID, "article-id")
        XCTAssertEqual(document.format, .article)
        XCTAssertEqual(try store.articleText(for: document), snapshot.text)
        let page = try XCTUnwrap(store.directReadingSections(for: document).first)
        XCTAssertEqual(try String(contentsOf: page.fileURL, encoding: .utf8), snapshot.html)
        XCTAssertEqual(try store.documents(), [document])
    }
}
