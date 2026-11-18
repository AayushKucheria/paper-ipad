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
        try UIGraphicsPDFRenderer(bounds:CGRect(x:0,y:0,width:612,height:792)).pdfData { context in
            context.beginPage()
            ("Printed words" as NSString).draw(at: CGPoint(x: 30, y: 30), withAttributes: [.font: UIFont.systemFont(ofSize: 18)])
        }.write(to: file)
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
        XCTAssertEqual(model.items.first?.alternatives?.first?.note,"A different AI transcription","A changed transcription must remain available without changing the confirmed payload")
        XCTAssertFalse(model.items.first!.canSend,"Alternative transcriptions must never enable a duplicate send")
        XCTAssertEqual(try ReviewStore(url:store.reviewURL(for:doc)).load().first?.alternatives?.first?.note,"A different AI transcription")
    }
}

private actor CountingAnalysis: MarkupAnalyzing {
    var calls = 0
    func analyze(_ pages: [AnalysisPage]) async throws -> [ReviewItem] { calls += 1; return [] }
}
extension ReviewDeliveryTests {
    func testUnchangedPagesAreNotBilledAgainAfterReopeningReview() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let file = root.appendingPathComponent("fixture.pdf")
        try UIGraphicsPDFRenderer(bounds: CGRect(x: 0,y: 0,width: 612,height: 792)).pdfData { c in c.beginPage() }.write(to: file)
        let store = DocumentStore(root: root.appendingPathComponent("Library"))
        let doc = try store.importPDF(at: file)
        let api = CountingAnalysis()
        let first = ReviewModel(document: doc, store: store, analyzer: api)
        await first.analyze()
        let second = ReviewModel(document: doc, store: store, analyzer: api)
        await second.analyze()
        let calls = await api.calls
        XCTAssertEqual(calls, 1, "Already analyzed, unchanged pages must not trigger another paid request after reopening")
        let working = try store.workingPDFURL(for: doc)
        let pdf = PDFDocument(url: working)!
        let ink = PDFAnnotation(bounds: CGRect(x: 10,y: 10,width: 100,height: 40),forType:.freeText,withProperties:nil)
        ink.contents = "New handwriting"
        pdf.page(at:0)!.addAnnotation(ink)
        XCTAssertTrue(pdf.write(to:working))
        let changed = ReviewModel(document:doc,store:store,analyzer:api)
        await changed.loadPages()
        XCTAssertEqual(changed.selectedPages,[1],"Changed marks should be selected automatically")
        await changed.analyze()
        let afterChange = await api.calls
        XCTAssertEqual(afterChange,2,"New ink must invalidate the previous analysis")
        changed.reanalyze = true
        await changed.analyze()
        let afterExplicit = await api.calls
        XCTAssertEqual(afterExplicit,3,"Explicit reanalysis may send unchanged pages")
    }
}

private actor CountingSuccessfulHighlightService: HighlightServing {
    var posts = 0
    var received: [ReviewItem] = []
    func create(parentID: String,item: ReviewItem) async throws -> String { posts += 1; received.append(item); return "created" }
    func find(parentID: String,item: ReviewItem) async throws -> String? { nil }
}
extension ReviewDeliveryTests {
    func testArticleQuoteMustMatchOriginalTextBeforeAnyPost() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:root) }
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        let file = root.appendingPathComponent("article.pdf")
        try UIGraphicsPDFRenderer(bounds:CGRect(x:0,y:0,width:612,height:792)).pdfData { c in c.beginPage() }.write(to:file)
        let store = DocumentStore(root:root.appendingPathComponent("Library"))
        let doc = try store.importReaderPDF(at:file,metadata:ReaderPDF(id:"original-article"))
        try "An exact source\npassage from Reader.".write(to:store.pdfURL(for:doc).deletingLastPathComponent().appendingPathComponent("source.txt"),atomically:true,encoding:.utf8)
        let mismatch = ReviewItem(pages:[1],quote:"An invented passage",note:"Why?",interpretation:"",kind:"handwriting")
        let match = ReviewItem(pages:[1],quote:"exact source passage",note:"Good",interpretation:"",kind:"handwriting")
        try ReviewStore(url:store.reviewURL(for:doc)).save([mismatch,match])
        let api = CountingSuccessfulHighlightService()
        let model = ReviewModel(document:doc,store:store,highlights:api)
        await model.send(mismatch.id)
        let before = await api.posts
        XCTAssertEqual(before,0,"A quote absent from original article text must never POST")
        XCTAssertEqual(model.items[0].state,.draft)
        await model.send(match.id)
        let after = await api.posts
        XCTAssertEqual(after,1,"Wrapping whitespace should not break a genuine source quote")
        XCTAssertEqual(model.items[1].state,.sent)
    }
}

private actor ContextRecordingAnalyzer: MarkupAnalyzing {
    var requests: [[Int]] = []
    func analyze(_ pages: [AnalysisPage]) async throws -> [ReviewItem] { requests.append(pages.map(\.number)); return [] }
}
extension ReviewDeliveryTests {
    func testChangedPageKeepsUnchangedSelectedContextInAnalysisRequest() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:root) }
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        let file = root.appendingPathComponent("two-pages.pdf")
        try UIGraphicsPDFRenderer(bounds:CGRect(x:0,y:0,width:612,height:792)).pdfData { c in c.beginPage(); c.beginPage() }.write(to:file)
        let store = DocumentStore(root:root.appendingPathComponent("Library"))
        let doc = try store.importPDF(at:file)
        let api = ContextRecordingAnalyzer()
        let model = ReviewModel(document:doc,store:store,analyzer:api)
        model.pageCount = 2; model.selectedPages = [1,2]
        await model.analyze()
        let working = try store.workingPDFURL(for:doc)
        let pdf = PDFDocument(url:working)!
        let ink = PDFAnnotation(bounds:CGRect(x:10,y:10,width:80,height:30),forType:.freeText,withProperties:nil)
        ink.contents = "Continued thought"
        pdf.page(at:1)!.addAnnotation(ink)
        XCTAssertTrue(pdf.write(to:working))
        await model.analyze()
        let requests = await api.requests
        XCTAssertEqual(requests,[[1,2],[1,2]],"A selected unchanged page provides context for a changed page and must remain in the request")
        await model.analyze()
        let afterUnchanged = await api.requests
        XCTAssertEqual(afterUnchanged.count,2,"An entirely unchanged selection must still skip the paid request")
    }
}

extension ReviewDeliveryTests {
    func testNewTranscriptionPreservesEditedDraftUntilAlternativeIsChosen() async throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:root) }
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        let file=root.appendingPathComponent("fixture.pdf")
        try UIGraphicsPDFRenderer(bounds:CGRect(x:0,y:0,width:612,height:792)).pdfData { c in c.beginPage() }.write(to:file)
        let store=DocumentStore(root:root.appendingPathComponent("Library"))
        let doc=try store.importPDF(at:file)
        let item=ReviewItem(pages:[1],quote:"Printed words",note:"My edited transcription",interpretation:"My interpretation",kind:"handwriting")
        try ReviewStore(url:store.reviewURL(for:doc)).save([item])
        let model=ReviewModel(document:doc,store:store,analyzer:ReanalysisService())
        await model.analyze()
        XCTAssertEqual(model.items.count,1)
        XCTAssertEqual(model.items[0].note,"My edited transcription")
        XCTAssertEqual(model.items[0].alternatives?.count,1)
        model.useAlternative(item.id,index:0)
        XCTAssertEqual(model.items[0].note,"A different AI transcription")
        XCTAssertEqual(model.items[0].alternatives?.first?.note,"My edited transcription","Choosing AI text should preserve the user's prior edit")
    }
}

extension ReviewDeliveryTests {
    func testArticleDeliveryUsesExactSourceWhitespaceAndPreservesReviewedQuote() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:root) }
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        let file = root.appendingPathComponent("article.pdf")
        try UIGraphicsPDFRenderer(bounds:CGRect(x:0,y:0,width:612,height:792)).pdfData { c in c.beginPage() }.write(to:file)
        let store = DocumentStore(root:root.appendingPathComponent("Library"))
        let doc = try store.importReaderPDF(at:file,metadata:ReaderPDF(id:"original-article"))
        let source = "Previous paragraph.\n\nWriting helps us see what we think.\n\nFollowing paragraph."
        try source.write(to:store.pdfURL(for:doc).deletingLastPathComponent().appendingPathComponent("source.txt"),atomically:true,encoding:.utf8)
        let quote = "Writing helps\nus see what we think."
        let item = ReviewItem(pages:[1],quote:quote,note:"My note",interpretation:"",kind:"handwriting")
        try ReviewStore(url:store.reviewURL(for:doc)).save([item])
        let api = CountingSuccessfulHighlightService()
        let model = ReviewModel(document:doc,store:store,highlights:api)
        await model.send(item.id)
        let delivered = await api.received
        XCTAssertEqual(delivered.first?.deliveryQuote,"Writing helps us see what we think.","Send the retained Reader substring, not PDF line wrapping")
        XCTAssertEqual(model.items.first?.quote,quote,"Keep the reviewed local quote intact")
        let saved = try ReviewStore(url:store.reviewURL(for:doc)).load().first
        XCTAssertEqual(saved?.deliveryQuote,"Writing helps us see what we think.")
        XCTAssertEqual(saved?.quote,quote)
        XCTAssertEqual(saved?.state,.sent)
    }
}

extension ReviewDeliveryTests {
    func testArticleDeliveryAcceptsLayoutWhitespaceBeforePunctuationWithoutChangingCharacters() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:root) }
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        let file = root.appendingPathComponent("article.pdf")
        try UIGraphicsPDFRenderer(bounds:CGRect(x:0,y:0,width:612,height:792)).pdfData { c in c.beginPage() }.write(to:file)
        let store = DocumentStore(root:root.appendingPathComponent("Library"))
        let doc = try store.importReaderPDF(at:file,metadata:ReaderPDF(id:"original-article"))
        try "Energy: E = mc².".write(to:store.pdfURL(for:doc).deletingLastPathComponent().appendingPathComponent("source.txt"),atomically:true,encoding:.utf8)
        let wrapped = ReviewItem(pages:[1],quote:"Energy: E = mc²\n.",note:"Why?",interpretation:"",kind:"handwriting")
        let wrongPunctuation = ReviewItem(pages:[1],quote:"Energy: E = mc²!",note:"No",interpretation:"",kind:"handwriting")
        let wrongWords = ReviewItem(pages:[1],quote:"Energy: E = m c².",note:"No",interpretation:"",kind:"handwriting")
        try ReviewStore(url:store.reviewURL(for:doc)).save([wrapped,wrongPunctuation,wrongWords])
        let api = CountingSuccessfulHighlightService()
        let model = ReviewModel(document:doc,store:store,highlights:api)
        await model.send(wrapped.id)
        let delivered = await api.received
        XCTAssertEqual(delivered.first?.deliveryQuote,"Energy: E = mc².","PDF layout whitespace before punctuation must map to exact retained source")
        XCTAssertEqual(model.items[0].quote,"Energy: E = mc²\n.")
        await model.send(wrongPunctuation.id)
        await model.send(wrongWords.id)
        let all = await api.received
        XCTAssertEqual(all.count,1,"Matching must never replace punctuation or remove a space between word characters")
        XCTAssertEqual(model.items[1].state,.draft)
        XCTAssertEqual(model.items[2].state,.draft)
    }
}

extension ReviewDeliveryTests {
    func testPDFDeliveryRejectsMissingAndRepeatedQuotesAndSendsExactSourceText() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let file = root.appendingPathComponent("source.pdf")
        try UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 612, height: 792)).pdfData { context in
            for sentence in ["Common phrase in the first paragraph.", "Common phrase in the second paragraph."] {
                context.beginPage()
                (sentence as NSString).draw(at: CGPoint(x: 30, y: 30), withAttributes: [.font: UIFont.systemFont(ofSize: 18)])
            }
        }.write(to: file)
        let store = DocumentStore(root: root.appendingPathComponent("Library"))
        let doc = try store.importReaderPDF(at: file, metadata: ReaderPDF(id: "parent"))
        let absent = ReviewItem(pages: [1], quote: "Invented words", note: "Keep locally", interpretation: "", kind: "handwriting")
        let duplicate = ReviewItem(pages: [1], quote: "Common phrase", note: "First occurrence", interpretation: "", kind: "handwriting")
        let partialWord = ReviewItem(pages: [1], quote: "ommon", note: "", interpretation: "", kind: "handwriting")
        let confirmed = ReviewItem(pages: [1], quote: "Common phrase in the\nfirst paragraph.", note: "Valid", interpretation: "", kind: "handwriting")
        let draftStore = ReviewStore(url: store.reviewURL(for: doc))
        try draftStore.save([absent, duplicate, partialWord, confirmed])
        let api = CountingSuccessfulHighlightService()
        let model = ReviewModel(document: doc, store: store, highlights: api)
        await model.send(absent.id)
        await model.send(duplicate.id)
        await model.send(partialWord.id)
        let before = await api.received
        XCTAssertEqual(before.count, 0, "Only a unique passage occurring in the original source can reach Reader")
        XCTAssertEqual(model.items.prefix(3).map(\.state), [.draft, .draft, .draft])
        XCTAssertEqual(try draftStore.load().first?.note, "Keep locally")
        await model.send(confirmed.id)
        let delivered = await api.received
        XCTAssertEqual(delivered.count, 1)
        XCTAssertEqual(delivered.last?.deliveryQuote, "Common phrase in the first paragraph.")
    }
}

private actor DirectCaptureAnalyzer: MarkupAnalyzing {
    var received: [AnalysisPage] = []
    func analyze(_ pages: [AnalysisPage]) async throws -> [ReviewItem] {
        received += pages
        return pages.map { ReviewItem(pages: [$0.number], quote: "Exact article passage",
                                      note: "An ink note", interpretation: "", kind: "handwriting") }
    }
}

extension ReviewDeliveryTests {
    func testDirectCaptureUsesItsImageAndSourceTextAndKeepsPDFReviewDistinct() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let file = root.appendingPathComponent("fallback.pdf")
        try UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 612, height: 792)).pdfData {
            $0.beginPage()
        }.write(to: file)
        let store = DocumentStore(root: root.appendingPathComponent("Library"))
        let document = try store.importReaderPDF(at: file, metadata: ReaderPDF(id: "article"))
        let originalDraft = ReviewItem(pages: [42], quote: "Exact article passage", note: "Prior PDF review",
                                       interpretation: "", kind: "handwriting")
        let draftStore = ReviewStore(url: store.reviewURL(for: document))
        try draftStore.save([originalDraft])
        let imageData = Data([0x01, 0x02, 0x03])
        let capture = AnalysisPage(number: 42, jpeg: imageData, sourceText: "Exact article passage follows.")
        let analyzer = DirectCaptureAnalyzer()
        let api = CountingSuccessfulHighlightService()
        let model = ReviewModel(document: document, store: store, analyzer: analyzer, highlights: api,
                                directPages: [capture], directSourceText: "Introduction. Exact article passage follows.")
        await model.loadPages()
        XCTAssertEqual(model.selectedPages, [42])
        await model.analyze()
        let received = await analyzer.received
        XCTAssertEqual(received.first?.jpeg, imageData)
        XCTAssertEqual(received.first?.sourceText, capture.sourceText)
        let drafts = try draftStore.load()
        XCTAssertEqual(drafts.first, originalDraft)
        let directDraft = try XCTUnwrap(drafts.first { $0.directInk == true })
        await model.send(directDraft.id)
        let delivered = await api.received
        XCTAssertEqual(delivered.first?.deliveryQuote, "Exact article passage")
        XCTAssertEqual(delivered.first?.locationLabel, "Marked region")
        let reopened = ReviewModel(document: document, store: store, analyzer: analyzer, directPages: [capture])
        await reopened.loadPages()
        XCTAssertTrue(reopened.changedPages.isEmpty)
        XCTAssertTrue(reopened.selectedPages.isEmpty)
    }
}
