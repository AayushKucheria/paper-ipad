import XCTest
import PDFKit
@testable import Paper

final class ReviewWorkflowTests: XCTestCase {
    var root: URL!
    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }
    func testRemovalRestoresEditedBytesAndKeepsOriginal() throws {
        let store = DocumentStore(root: root.appendingPathComponent("Library"))
        let fixture = root.appendingPathComponent("sample.pdf")
        try UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 612, height: 792)).pdfData { c in c.beginPage() }.write(to: fixture)
        let doc = try store.importPDF(at: fixture)
        let working = try store.workingPDFURL(for: doc)
        let pdf = PDFDocument(url: working)!
        let note = PDFAnnotation(bounds: CGRect(x: 40,y: 40,width: 100,height: 40), forType: .freeText, withProperties: nil)
        note.contents = "Keep my note"; pdf.page(at: 0)!.addAnnotation(note); XCTAssertTrue(pdf.write(to: working))
        let edited = try Data(contentsOf: working), original = try Data(contentsOf: store.pdfURL(for: doc))
        try store.removeDownload(doc)
        XCTAssertTrue(try store.documents().isEmpty)
        XCTAssertEqual(try store.removedDocuments().map(\.id), [doc.id])
        try store.restoreDownload(doc)
        XCTAssertEqual(try Data(contentsOf: working), edited)
        XCTAssertEqual(try Data(contentsOf: store.pdfURL(for: doc)), original)
        try store.removeDownload(doc); try store.permanentlyDelete(doc)
        XCTAssertTrue(try store.removedDocuments().isEmpty)
    }
    func testAnalysisRejectsOutOfRangePagesAndDistinguishesInterpretation() throws {
        let valid = Data(#"{"items":[{"pages":[2,3],"quote":"Exact passage","note":"Why?","interpretation":"Diagram: two arrows","kind":"diagram"}]}"#.utf8)
        let items = try MarkupExtraction.decode(valid, allowedPages: [2,3])
        XCTAssertEqual(items.first?.pages, [2,3]); XCTAssertEqual(items.first?.note, "Why?")
        XCTAssertEqual(items.first?.interpretation, "Diagram: two arrows")
        XCTAssertThrowsError(try MarkupExtraction.decode(valid, allowedPages: [2]))
    }
    func testDraftsPersistBeforeDeliveryAndAmbiguousStateCannotBeSentAgain() throws {
        let store = ReviewStore(url: root.appendingPathComponent("review.json"))
        var item = ReviewItem(pages: [1,2], quote: "Exact passage", note: "My note", interpretation: "", kind: "handwriting")
        try store.save([item])
        XCTAssertEqual(try store.load().first?.note, "My note")
        item.state = .sending; try store.save([item])
        let recovered = try store.load().first!
        XCTAssertFalse(recovered.canSend, "Interrupted delivery must be reconciled before any second POST")
        item.state = .sent; item.remoteID = "remote-one"; try store.save([item])
        XCTAssertEqual(try store.load().first?.remoteID, "remote-one")
        XCTAssertFalse(try store.load().first!.canSend)
    }
}

private actor AmbiguousHighlightService: HighlightServing {
    private(set) var posts = 0
    func create(parentID:String,item:ReviewItem) async throws -> String { posts += 1; throw ReviewError.ambiguous }
    func find(parentID:String,item:ReviewItem) async throws -> String? { "already-created" }
}
@MainActor final class ReviewDeliveryTests:XCTestCase {
    func testTimeoutPersistsPendingAndRelaunchCannotPostAgainBeforeReconciliation() async throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer{try? FileManager.default.removeItem(at:root)}
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        let file=root.appendingPathComponent("fixture.pdf")
        try UIGraphicsPDFRenderer(bounds:CGRect(x:0,y:0,width:612,height:792)).pdfData{c in c.beginPage()}.write(to:file)
        let store=DocumentStore(root:root.appendingPathComponent("Library"))
        let doc=try store.importReaderPDF(at:file,metadata:ReaderPDF(id:"parent"))
        let item=ReviewItem(pages:[1],quote:"Printed words",note:"Why?",interpretation:"",kind:"handwriting")
        try ReviewStore(url:store.reviewURL(for:doc)).save([item])
        let service=AmbiguousHighlightService()
        let first=ReviewModel(document:doc,store:store,highlights:service)
        await first.send(item.id)
        XCTAssertEqual(first.items.first?.state,.sending)
        let second=ReviewModel(document:doc,store:store,highlights:service)
        await second.send(item.id)
        let posts=await service.posts;XCTAssertEqual(posts,1,"Relaunch must not duplicate an ambiguous POST")
        await second.checkDelivery(item.id)
        XCTAssertEqual(second.items.first?.state,.sent)
        XCTAssertEqual(try ReviewStore(url:store.reviewURL(for:doc)).load().first?.remoteID,"already-created")
    }
}

private struct ReanalysisService:MarkupAnalyzing {
    func analyze(_ pages:[AnalysisPage]) async throws->[ReviewItem]{[ReviewItem(pages:[1],quote:"Printed words",note:"A different AI transcription",interpretation:"",kind:"handwriting")]}
}
extension ReviewDeliveryTests {
    func testReanalysisDoesNotCreateAnotherDraftForAnAlreadySentPassage() async throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer{try? FileManager.default.removeItem(at:root)}
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        let file=root.appendingPathComponent("fixture.pdf")
        try UIGraphicsPDFRenderer(bounds:CGRect(x:0,y:0,width:612,height:792)).pdfData{c in c.beginPage()}.write(to:file)
        let store=DocumentStore(root:root.appendingPathComponent("Library"))
        let doc=try store.importReaderPDF(at:file,metadata:ReaderPDF(id:"parent"))
        var item=ReviewItem(pages:[1],quote:"Printed words",note:"My confirmed words",interpretation:"",kind:"handwriting")
        item.state = .sent;item.remoteID="keep-remote"
        try ReviewStore(url:store.reviewURL(for:doc)).save([item])
        let model=ReviewModel(document:doc,store:store,analyzer:ReanalysisService())
        await model.analyze()
        XCTAssertEqual(model.items.count,1,"Reanalyzing a sent passage must not offer a duplicate send")
        XCTAssertEqual(model.items.first?.remoteID,"keep-remote")
        XCTAssertEqual(model.items.first?.note,"My confirmed words")
    }
}
