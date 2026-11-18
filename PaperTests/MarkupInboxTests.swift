import XCTest
import PDFKit
@testable import Paper

final class MarkupInboxTests: XCTestCase {
    func testInboxIncludesPendingAcrossDocumentsAndNewInkButExcludesCompletedAndRemoved() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let source = root.appendingPathComponent("input.pdf")
        try UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 612, height: 792)).pdfData { context in
            context.beginPage(); ("A thought to keep" as NSString).draw(at: CGPoint(x: 50, y: 50), withAttributes: nil)
        }.write(to: source)
        let store = DocumentStore(root: root.appendingPathComponent("Library"))
        let first = try store.importPDF(at: source), second = try store.importPDF(at: source), completed = try store.importPDF(at: source), ink = try store.importPDF(at: source)
        var draft = ReviewItem(pages: [1], quote: "A thought to keep", note: "Why?", interpretation: "", kind: "handwriting")
        try ReviewStore(url: store.reviewURL(for: first)).save([draft])
        draft.state = .sending
        try ReviewStore(url: store.reviewURL(for: second)).save([draft])
        draft.state = .sent
        try ReviewStore(url: store.reviewURL(for: completed)).save([draft])
        let working = try store.workingPDFURL(for: ink)
        let pdf = try XCTUnwrap(PDFDocument(url: working))
        let annotation = PDFAnnotation(bounds: CGRect(x: 50, y: 50, width: 150, height: 40), forType: .ink, withProperties: nil)
        let path = UIBezierPath(); path.move(to: .zero); path.addLine(to: CGPoint(x: 100, y: 25)); annotation.add(path)
        pdf.page(at: 0)?.addAnnotation(annotation); XCTAssertTrue(pdf.write(to: working))
        var entries = try MarkupInboxInventory.entries(store: store)
        XCTAssertEqual(Set(entries.map(\.id)), Set([first.id, second.id, ink.id]))
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.pdfURL(for: completed).deletingLastPathComponent().appendingPathComponent("reading.pdf").path), "Browsing the inbox must not create edited copies of unread downloads")
        XCTAssertEqual(entries.first { $0.id == ink.id }?.changedPages, [1])
        let rendered = try MarkupPages.render(working: working, original: store.pdfURL(for: ink), pages: [1])
        let history = ReviewAnalysisHistory(fingerprints: [1: MarkupPages.fingerprint(rendered[0])], usage: [])
        try JSONEncoder().encode(history).write(to: store.reviewURL(for: ink).deletingLastPathComponent().appendingPathComponent("analysis.json"))
        try store.removeDownload(first)
        entries = try MarkupInboxInventory.entries(store: store)
        XCTAssertEqual(entries.map(\.id), [second.id], "Unchanged analyzed ink, completed items and removed documents stay outside pending review")
    }
}

extension MarkupInboxTests {
    func testInboxFindsDirectInkSeparatelyFromPDFAnnotations() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let source = root.appendingPathComponent("input.pdf")
        try UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 612, height: 792)).pdfData {
            $0.beginPage()
        }.write(to: source)
        let store = DocumentStore(root: root.appendingPathComponent("Library"))
        let document = try store.importPDF(at: source)
        let pen = DirectInkStore(document: document, store: store)
        try pen.save(DirectInkState(drawing: testInkDrawing()),
                     section: "body")
        let entry = try XCTUnwrap(MarkupInboxInventory.entries(store: store).first)
        XCTAssertTrue(entry.hasDirectInk)
        XCTAssertTrue(entry.changedPages.isEmpty)
    }
}
