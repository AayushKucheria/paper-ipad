import XCTest
import PDFKit
@testable import Paper

private actor LibraryTestService: ReaderServing {
    let records: [ReaderPDF]
    let file: URL?
    let fail: Bool
    private(set) var downloadCalls = 0
    init(records: [ReaderPDF] = [], file: URL? = nil, fail: Bool = false) {
        self.records = records; self.file = file; self.fail = fail
    }
    func listPDFs(progress: @escaping @Sendable (Int) -> Void) async throws -> [ReaderPDF] {
        progress(records.count)
        if fail { throw URLError(.notConnectedToInternet) }
        return records
    }
    func downloadPDF(id: String, progress: @escaping @Sendable (Int64, Int64?) -> Void) async throws -> URL {
        downloadCalls += 1
        guard let file, !fail else { throw URLError(.notConnectedToInternet) }
        let copy = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".pdf")
        try FileManager.default.copyItem(at: file, to: copy)
        return copy
    }
}
@MainActor final class ReaderLibraryModelTests: XCTestCase {
    var root: URL!
    var store: DocumentStore { DocumentStore(root: root.appendingPathComponent("Library")) }
    var catalog: ReaderCatalog { ReaderCatalog(url: root.appendingPathComponent("reader-catalog.json")) }
    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: root) }
    func testRefreshFetchesMetadataOnlyAndSearchesAllThreeFields() async throws {
        let records = [ReaderPDF(id: "one", title: "Reading", author: "Alex", summary: "Margins and meaning"), ReaderPDF(id: "two", title: "Thinking")]
        let service = LibraryTestService(records: records)
        let model = ReaderLibraryModel(store: store, catalog: catalog, api: service)
        await model.refresh()
        XCTAssertEqual(Set(model.pdfs.map(\.id)), Set(records.map(\.id)))
        XCTAssertEqual(model.filteredPDFs(query: "MARGINS").map(\.id), ["one"])
        XCTAssertEqual(model.filteredPDFs(query: "alex").map(\.id), ["one"])
        XCTAssertEqual(model.filteredPDFs(query: "Thinking").map(\.id), ["two"])
        XCTAssertTrue(model.downloads.isEmpty)
        let calls = await service.downloadCalls
        XCTAssertEqual(calls, 0, "Refreshing the catalog must never download PDFs")
        XCTAssertEqual(try catalog.load()?.documents.count, 2)
    }
    func testCorruptCatalogCannotHideRetainedPDFsOrBlockRefresh() async throws {
        let file = root.appendingPathComponent("retained.pdf")
        try UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 612, height: 792)).pdfData { context in
            context.beginPage()
            ("Keep my saved work" as NSString).draw(at: CGPoint(x: 40, y: 40), withAttributes: nil)
        }.write(to: file)
        let local = try store.importPDF(at: file)
        let retained = try Data(contentsOf: store.workingPDFURL(for: local))
        try Data("broken catalog".utf8).write(to: catalog.url)
        let model = ReaderLibraryModel(store: store, catalog: catalog, api: LibraryTestService(records: [ReaderPDF(id: "remote")]))
        XCTAssertEqual(model.downloads, [local], "A catalog failure must never hide saved PDFs")
        XCTAssertTrue(model.connected, "A cached-metadata failure must not block Reader recovery")
        await model.refresh()
        XCTAssertEqual(model.pdfs.map(\.id), ["remote"])
        XCTAssertEqual(try Data(contentsOf: store.workingPDFURL(for: local)), retained)
    }
    func testFailedRefreshPreservesCompleteOfflineCatalog() async throws {
        let cached = [ReaderPDF(id: "cached", title: "Available offline")]
        try catalog.save(cached, syncedAt: Date())
        let model = ReaderLibraryModel(store: store, catalog: catalog, api: LibraryTestService(fail: true))
        XCTAssertEqual(model.pdfs, cached)
        await model.refresh()
        XCTAssertEqual(model.pdfs, cached)
        XCTAssertEqual(try catalog.load()?.documents, cached)
        XCTAssertNotNil(model.error)
    }
    func testDownloadedPDFReopensWithoutNetworkAndSurvivesCatalogRemoval() async throws {
        let file = root.appendingPathComponent("fixture.pdf")
        try UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 612, height: 792)).pdfData { context in
            context.beginPage()
            ("Keep my notes" as NSString).draw(at: CGPoint(x: 40, y: 40), withAttributes: nil)
        }.write(to: file)
        let metadata = ReaderPDF(id: "stable-reader-id", title: "Original title")
        let service = LibraryTestService(records: [metadata], file: file)
        let model = ReaderLibraryModel(store: store, catalog: catalog, api: service)
        await model.refresh()
        let downloaded = await model.download(metadata)
        let document = try XCTUnwrap(downloaded)
        let working = try store.workingPDFURL(for: document)
        let pdf = try XCTUnwrap(PDFDocument(url: working))
        pdf.page(at: 0)!.addAnnotation(PDFAnnotation(bounds: CGRect(x: 20, y: 20, width: 60, height: 20), forType: .freeText, withProperties: nil))
        XCTAssertTrue(pdf.write(to: working))
        let edited = try Data(contentsOf: working)
        let offline = ReaderLibraryModel(store: store, catalog: catalog, api: LibraryTestService(fail: true))
        let reopened = await offline.download(ReaderPDF(id: metadata.id, title: "Renamed elsewhere"))
        XCTAssertEqual(reopened?.id, document.id)
        let empty = ReaderLibraryModel(store: store, catalog: catalog, api: LibraryTestService())
        await empty.refresh()
        XCTAssertTrue(empty.pdfs.isEmpty)
        XCTAssertEqual(empty.downloads.map(\.id), [document.id])
        XCTAssertEqual(try Data(contentsOf: working), edited)
    }
}
