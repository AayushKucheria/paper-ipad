import XCTest
import PDFKit
@testable import Paper

final class DocumentStoreTests: XCTestCase {
    var root: URL!
    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: root) }
    func sourcePDF() throws -> URL {
        let url = root.appendingPathComponent("Reading.pdf")
        let data = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 612, height: 792)).pdfData { ctx in
            for _ in 0..<2 { ctx.beginPage(); ("A page to annotate" as NSString).draw(at: CGPoint(x: 40, y: 40), withAttributes: nil) }
        }
        try data.write(to: url)
        return url
    }
    func testEditsSurviveReopeningAndPreserveOriginal() throws {
        let source = try sourcePDF(), original = try Data(contentsOf: source)
        let store = DocumentStore(root: root.appendingPathComponent("library"))
        let doc = try store.importPDF(at: source)
        let working = try store.workingPDFURL(for: doc)
        let pdf = try XCTUnwrap(PDFDocument(url: working))
        let annotation = PDFAnnotation(bounds: CGRect(x: 60,y: 60,width: 120,height: 40), forType: .ink, withProperties: nil)
        let path = UIBezierPath(); path.move(to: CGPoint(x:0,y:0)); path.addLine(to: CGPoint(x:100,y:20)); annotation.add(path)
        pdf.page(at: 1)!.addAnnotation(annotation)
        XCTAssertTrue(pdf.write(to: working))
        let reopened = DocumentStore(root: store.root)
        XCTAssertEqual(try reopened.documents(), [doc])
        XCTAssertEqual(PDFDocument(url: try reopened.workingPDFURL(for: doc))?.page(at: 1)?.annotations.count, 1)
        XCTAssertEqual(try Data(contentsOf: source), original)
        XCTAssertEqual(try Data(contentsOf: reopened.pdfURL(for: doc)), original)
    }
    func testInvalidPDFIsRejectedWithoutLibraryEntry() throws {
        let source = root.appendingPathComponent("broken.pdf")
        try Data("not a PDF".utf8).write(to: source)
        let store = DocumentStore(root: root.appendingPathComponent("library"))
        XCTAssertThrowsError(try store.importPDF(at: source))
        XCTAssertEqual(try store.documents(), [])
    }
    func testEditedCopyIsSavedAndInvalidCopyPreservesLastGoodVersion() throws {
        let store = DocumentStore(root: root.appendingPathComponent("library"))
        let doc = try store.importPDF(at: sourcePDF())
        let copy = root.appendingPathComponent("edited.pdf")
        let pdf = try XCTUnwrap(PDFDocument(url: store.pdfURL(for: doc)))
        pdf.page(at: 0)!.addAnnotation(PDFAnnotation(bounds: CGRect(x:10,y:10,width:100,height:40),forType:.freeText,withProperties:nil))
        XCTAssertTrue(pdf.write(to: copy))
        try store.saveEditedCopy(at: copy, document: doc)
        let working = try store.workingPDFURL(for: doc), good = try Data(contentsOf: working)
        XCTAssertEqual(PDFDocument(url: working)?.page(at: 0)?.annotations.count, 1)
        try Data("broken".utf8).write(to: copy)
        XCTAssertThrowsError(try store.saveEditedCopy(at: copy, document: doc))
        XCTAssertEqual(try Data(contentsOf: working), good)
        XCTAssertEqual(PDFDocument(url: store.pdfURL(for: doc))?.page(at: 0)?.annotations.count, 0)
    }
}
