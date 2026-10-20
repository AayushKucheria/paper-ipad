import XCTest
import PDFKit
@testable import Paper

final class ReaderStorageTests: XCTestCase {
    var root: URL!
    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: root) }
    func pdf() throws -> URL {
        let url = root.appendingPathComponent("input.pdf")
        try UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 612, height: 792)).pdfData { context in
            context.beginPage()
            ("Saved PDF" as NSString).draw(at: CGPoint(x: 30, y: 30), withAttributes: nil)
        }.write(to: url)
        return url
    }
    func testOldRecordsRemainReadable() throws {
        let id = UUID()
        let data = Data("{\"id\":\"\(id.uuidString)\",\"title\":\"Old PDF\"}".utf8)
        let document = try JSONDecoder().decode(StoredDocument.self, from: data)
        XCTAssertEqual(document.id, id)
        XCTAssertNil(document.readerID)
    }
    func testReaderDownloadRetainsMetadataAndDuplicateNeverOverwritesEdits() throws {
        let store = DocumentStore(root: root.appendingPathComponent("library"))
        let metadata = ReaderPDF(id: "reader-test", title: "Title", author: "Author", summary: "Summary", readerURL: URL(string: "https://read.readwise.io/read/test"), sourceURL: URL(string: "https://example.com/test.pdf"))
        let document = try store.importReaderPDF(at: pdf(), metadata: metadata)
        XCTAssertEqual(document.readerID, metadata.id)
        XCTAssertEqual(document.author, metadata.author)
        XCTAssertEqual(document.summary, metadata.summary)
        XCTAssertEqual(document.readerURL, metadata.readerURL)
        XCTAssertEqual(document.sourceURL, metadata.sourceURL)
        let original = try Data(contentsOf: store.pdfURL(for: document))
        let working = try store.workingPDFURL(for: document)
        let edited = try XCTUnwrap(PDFDocument(url: working))
        edited.page(at: 0)!.addAnnotation(PDFAnnotation(bounds: CGRect(x: 10, y: 10, width: 80, height: 40), forType: .freeText, withProperties: nil))
        XCTAssertTrue(edited.write(to: working))
        let editedBytes = try Data(contentsOf: working)
        let duplicate = try store.importReaderPDF(at: pdf(), metadata: ReaderPDF(id: metadata.id, title: "Changed"))
        XCTAssertEqual(duplicate.id, document.id)
        let catalog = ReaderCatalog(url: store.root.appendingPathComponent("reader-catalog.json"))
        try catalog.save([], syncedAt: Date())
        XCTAssertEqual(try store.documents(), [document])
        XCTAssertEqual(try Data(contentsOf: store.pdfURL(for: document)), original)
        XCTAssertEqual(try Data(contentsOf: working), editedBytes)
    }
    func testInvalidReaderDownloadLeavesNoRow() throws {
        let store = DocumentStore(root: root.appendingPathComponent("library"))
        let invalid = root.appendingPathComponent("invalid.pdf")
        try Data("invalid".utf8).write(to: invalid)
        XCTAssertThrowsError(try store.importReaderPDF(at: invalid, metadata: ReaderPDF(id: "invalid")))
        XCTAssertEqual(try store.documents(), [])
    }
    func testSnapshotRoundTripAndFailedReplacementPreserveSnapshot() throws {
        let catalog = ReaderCatalog(url: root.appendingPathComponent("catalog.json"))
        XCTAssertNil(try catalog.load())
        let saved = try catalog.save([ReaderPDF(id: "test", title: "Title")], syncedAt: Date(timeIntervalSince1970: 1234))
        XCTAssertEqual(try catalog.load(), saved)
        let blocked = ReaderCatalog(url: catalog.url.appendingPathComponent("impossible.json"))
        XCTAssertThrowsError(try blocked.save([], syncedAt: Date()))
        XCTAssertEqual(try catalog.load(), saved)
    }
}
