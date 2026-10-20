import SwiftUI
import PDFKit
import OSLog

@MainActor final class ReviewModel: ObservableObject {
    @Published var items: [ReviewItem] = []
    @Published var pageCount = 1
    @Published var firstPage = 1
    @Published var lastPage = 1
    @Published var markedPages: [Int] = []
    @Published var busy = false
    @Published var phase = ""
    @Published var started = Date()
    @Published var error: String?
    @Published var message: String?
    @Published var selectedID: UUID?
    @Published var jumpPage = 1
    @Published var jumpID = UUID()
    let document: StoredDocument
    let documentStore: DocumentStore
    let draftStore: ReviewStore
    let aiCredentials: ReaderCredentials
    let readerCredentials: ReaderCredentials
    let readerBaseURL: URL
    let anthropicEndpoint: URL
    private let suppliedAnalyzer: (any MarkupAnalyzing)?
    private let suppliedHighlights: (any HighlightServing)?
    private var canPersist = true
    private let log = Logger(subsystem:"com.aayush.paper.reader",category:"Review")
    init(document: StoredDocument, store: DocumentStore, readerCredentials: ReaderCredentials = ReaderCredentials(),
         aiCredentials: ReaderCredentials = ReaderCredentials(service:"com.aayush.paper.anthropic"),
         readerBaseURL: URL = URL(string:"https://readwise.io/api/v3/")!, anthropicEndpoint: URL = URL(string:"https://api.anthropic.com/v1/messages")!, analyzer: (any MarkupAnalyzing)? = nil, highlights: (any HighlightServing)? = nil) {
        self.document = document; documentStore = store; draftStore = ReviewStore(url: store.reviewURL(for:document))
        self.aiCredentials = aiCredentials; self.readerCredentials = readerCredentials; self.readerBaseURL = readerBaseURL; self.anthropicEndpoint = anthropicEndpoint
        suppliedAnalyzer = analyzer; suppliedHighlights = highlights
        do { items = try draftStore.load(); selectedID = items.first?.id }
        catch { self.error = "Saved review drafts couldn’t be loaded. Export a copy of this PDF before recovering the review file."; canPersist = false }
    }
    func loadPages() async {
        do {
            let url = try documentStore.workingPDFURL(for: document), source = documentStore.pdfURL(for: document)
            let result = await Task.detached { () -> (Int,[Int]) in
                guard let pdf = PDFDocument(url:url) else { return (1,[]) }
                return (pdf.pageCount,MarkupPages.marked(in:pdf,original:PDFDocument(url:source)))
            }.value
            pageCount = max(1,result.0); markedPages = result.1
            firstPage = markedPages.first ?? 1; lastPage = min(pageCount, firstPage + 5)
            if let last = markedPages.last, last <= firstPage + 5 { lastPage = last }
            jumpPage = firstPage; jumpID = UUID()
        } catch { self.error = error.localizedDescription }
    }
    func save() {
        guard canPersist else { return }
        do { try draftStore.save(items) } catch { self.error = "Your review draft couldn’t be saved. Keep this screen open and export the PDF." }
    }
    func select(_ id: UUID) { selectedID = id; showPages() }
    func showPages() { jumpPage = items.first(where:{$0.id == selectedID})?.pages.first ?? firstPage; jumpID = UUID() }
    private func begin(_ phase: String) { busy = true; started = Date(); self.phase = phase; error = nil; message = nil; log.info("review_start phase=\(phase,privacy:.public)") }
    private func end() { busy = false; log.info("review_complete elapsed=\(Date().timeIntervalSince(self.started))") }
    func analyze() async {
        guard !busy, canPersist else { return }
        guard firstPage >= 1, lastPage >= firstPage, lastPage <= pageCount, lastPage-firstPage < 6 else { error = ReviewError.invalidPages.localizedDescription; return }
        begin("Preparing selected pages")
        defer { end() }
        do {
            let service: any MarkupAnalyzing
            if let suppliedAnalyzer { service = suppliedAnalyzer }
            else { guard let key = try aiCredentials.read() else { throw ReviewError.noKey }; service = AnthropicMarkupAPI(key:key,endpoint:anthropicEndpoint) }
            let working = try documentStore.workingPDFURL(for:document), original = documentStore.pdfURL(for:document)
            let selected = Array(firstPage...lastPage)
            let pages = try await Task.detached(priority:.userInitiated) { try MarkupPages.render(working:working,original:original,pages:selected) }.value
            try Task.checkCancellation()
            phase = "Reading your markup with Claude"
            log.info("analysis_request pages=\(pages.count) elapsed=\(Date().timeIntervalSince(self.started))")
            let extracted = try await service.analyze(pages)
            try Task.checkCancellation()
            var next = items
            for item in extracted where !next.contains(where:{ existing in
                if existing.pages != item.pages { return false }
                let quote = item.quote.trimmingCharacters(in:.whitespacesAndNewlines)
                if !quote.isEmpty && existing.quote.trimmingCharacters(in:.whitespacesAndNewlines) == quote { return true }
                return existing.quote == item.quote && existing.note == item.note && existing.interpretation == item.interpretation
            }) { next.append(item) }
            try draftStore.save(next); items = next
            selectedID = extracted.first.flatMap { e in next.first(where:{ $0.pages == e.pages && $0.quote == e.quote && $0.note == e.note })?.id } ?? selectedID
            message = extracted.isEmpty ? "No meaningful markup found in those pages. Try another page range or add a draft manually." : "Analysis saved. Check each passage, transcription, and interpretation before sending."
            showPages()
        } catch is CancellationError { message = "Analysis cancelled. Your saved drafts are kept." }
        catch { self.error = error.localizedDescription; log.error("analysis_failure elapsed=\(Date().timeIntervalSince(self.started))") }
    }
    func addDraft() {
        guard canPersist, !busy else { return }
        let item = ReviewItem(pages:Array(firstPage...max(firstPage,lastPage)),quote:"",note:"",interpretation:"",kind:"other")
        items.append(item); selectedID = item.id; save(); showPages()
    }
    private func service() throws -> any HighlightServing {
        if let suppliedHighlights { return suppliedHighlights }
        guard let token = try readerCredentials.read() else { throw ReaderAPIError.authenticationRequired }
        return ReaderHighlightAPI(token:token,baseURL:readerBaseURL)
    }
    func send(_ id: UUID) async {
        guard !busy, canPersist, let index = items.firstIndex(where:{$0.id == id}), items[index].canSend else { return }
        guard let parent = document.readerID else { error = ReviewError.noReader.localizedDescription; return }
        begin("Sending reviewed highlight to Reader"); defer { end() }
        do {
            let api = try service()
            // Persist the exact confirmed payload before touching the network.
            items[index].deliveryQuote = items[index].quote
            items[index].deliveryNote = items[index].readerNote
            items[index].attemptedAt = Date(); items[index].state = .sending
            try draftStore.save(items)
            let remote = try await api.create(parentID:parent,item:items[index])
            items[index].remoteID = remote; items[index].state = .sent
            try draftStore.save(items); message = "Sent to Reader."
        } catch {
            if let e = error as? ReviewError, [.unmatched,.rateLimited].contains(e) { items[index].state = .draft }
            if error is ReaderAPIError { items[index].state = .draft }
            // Unknown outcomes remain .sending and cannot generate another POST.
            save(); self.error = error.localizedDescription
            log.error("delivery_failure elapsed=\(Date().timeIntervalSince(self.started))")
        }
    }
    func checkDelivery(_ id: UUID) async {
        guard !busy, canPersist, let parent = document.readerID, let index = items.firstIndex(where:{$0.id == id}) else { return }
        begin("Checking delivery in Reader"); defer { end() }
        do {
            if let remote = try await service().find(parentID:parent,item:items[index]) {
                items[index].state = .sent; items[index].remoteID = remote; try draftStore.save(items); message = "Confirmed in Reader."
            } else { message = "Not found yet. Keep this item pending and check again, or inspect Reader before allowing a retry." }
        } catch { self.error = error.localizedDescription }
    }
    func allowRetry(_ id: UUID) {
        guard let index = items.firstIndex(where:{$0.id == id}), items[index].state == .sending else { return }
        items[index].state = .draft; save()
    }
}
