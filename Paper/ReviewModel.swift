import SwiftUI
import PDFKit
import OSLog

@MainActor final class ReviewModel: ObservableObject {
    @Published var items: [ReviewItem] = []
    @Published var pageCount = 1
    @Published var firstPage = 1
    @Published var lastPage = 1
    @Published var markedPages: [Int] = []
    @Published var selectedPages: Set<Int> = [1]
    @Published var changedPages: [Int] = []
    @Published var reanalyze = false
    @Published var usage: [AnalysisUsage] = []
    private var history = ReviewAnalysisHistory()
    private var historyURL: URL { draftStore.url.deletingLastPathComponent().appendingPathComponent(isDirectReading ? "direct-analysis.json" : "analysis.json") }
    var pendingItems: [ReviewItem] { items.filter { $0.state == .draft || $0.state == .sending } }
    func togglePage(_ number: Int) {
        if selectedPages.contains(number) { selectedPages.remove(number) }
        else if selectedPages.count < 6 { selectedPages.insert(number) }
    }
    @Published var busy = false
    @Published var phase = ""
    @Published var started = Date()
    @Published var error: String?
    @Published private(set) var feedbackItemID: UUID?
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
    let directPages: [AnalysisPage]?
    private let directSourceText: String?
    var isDirectReading: Bool { directPages != nil }
    var analysisNumbers: [Int] { directPages?.map(\.number) ?? Array(1...pageCount) }
    private let suppliedAnalyzer: (any MarkupAnalyzing)?
    private let suppliedHighlights: (any HighlightServing)?
    private var canPersist = true
    private let log = Logger(subsystem:"com.aayush.paper.reader",category:"Review")
    init(document: StoredDocument, store: DocumentStore, readerCredentials: ReaderCredentials = ReaderCredentials(),
         aiCredentials: ReaderCredentials = ReaderCredentials(service:"com.aayush.paper.anthropic"),
         readerBaseURL: URL = URL(string:"https://readwise.io/api/v3/")!, anthropicEndpoint: URL = URL(string:"https://api.anthropic.com/v1/messages")!, analyzer: (any MarkupAnalyzing)? = nil, highlights: (any HighlightServing)? = nil,
         directPages: [AnalysisPage]? = nil, directSourceText: String? = nil) {
        self.document = document; documentStore = store; draftStore = ReviewStore(url: store.reviewURL(for:document))
        self.aiCredentials = aiCredentials; self.readerCredentials = readerCredentials; self.readerBaseURL = readerBaseURL; self.anthropicEndpoint = anthropicEndpoint
        suppliedAnalyzer = analyzer; suppliedHighlights = highlights
        self.directPages = directPages; self.directSourceText = directSourceText
        do {
            items = try draftStore.load(); selectedID = items.first?.id
            if FileManager.default.fileExists(atPath: historyURL.path) {
                history = try JSONDecoder().decode(ReviewAnalysisHistory.self, from: Data(contentsOf: historyURL))
                usage = history.usage
            }
        }
        catch { self.error = "Saved review drafts couldn’t be loaded. Keep the original document before recovering the review file."; canPersist = false }
    }
    func loadPages() async {
        if let directPages {
            markedPages = directPages.map(\.number)
            changedPages = directPages.filter { history.fingerprints[$0.number] != MarkupPages.fingerprint($0) }.map(\.number)
            selectedPages = Set(changedPages.prefix(6))
            pageCount = max(1, directPages.count)
            firstPage = markedPages.first ?? 1
            lastPage = markedPages.last ?? firstPage
            showPages()
            return
        }
        do {
            let url = try documentStore.workingPDFURL(for: document), source = documentStore.pdfURL(for: document)
            let result = await Task.detached { () -> (Int,[Int],[Int:String]) in
                guard let pdf = PDFDocument(url:url) else { return (1,[],[:]) }
                guard let sourcePDF = PDFDocument(url:source) else { return (pdf.pageCount,[],[:]) }
                let marked = MarkupPages.marked(in:pdf,original:sourcePDF)
                var fingerprints: [Int:String] = [:]
                for number in marked {
                    if let page = try? MarkupPages.render(pdf:pdf,source:sourcePDF,pages:[number]).first { fingerprints[number] = MarkupPages.fingerprint(page) }
                }
                return (pdf.pageCount,marked,fingerprints)
            }.value
            pageCount = max(1,result.0); markedPages = result.1
            changedPages = markedPages.filter { result.2[$0] != history.fingerprints[$0] }
            selectedPages = Set(changedPages.prefix(6))
            firstPage = markedPages.first ?? 1; lastPage = min(pageCount, firstPage + 5)
            if let last = markedPages.last, last <= firstPage + 5 { lastPage = last }
            jumpPage = items.first(where: { $0.id == selectedID })?.pages.first ?? firstPage; jumpID = UUID()
        } catch { self.error = error.localizedDescription }
    }
    func save() {
        guard canPersist else { return }
        do { try draftStore.save(items) } catch { self.error = "Your review draft couldn’t be saved. Keep this screen open to preserve your edits." }
    }
    func select(_ id: UUID) { selectedID = id; showPages() }
    func showPages() {
        let item = items.first { $0.id == selectedID }
        jumpPage = (item?.directInk == true) == isDirectReading ? item?.pages.first ?? firstPage : firstPage
        jumpID = UUID()
    }
    private func begin(_ phase: String, itemID: UUID? = nil) {
        busy = true
        started = Date()
        self.phase = phase
        feedbackItemID = itemID
        error = nil
        message = nil
        log.info("review_start phase=\(phase,privacy:.public)")
    }
    private func end() { busy = false; log.info("review_complete elapsed=\(Date().timeIntervalSince(self.started))") }
    func analyze() async {
        guard !busy, canPersist else { return }
        guard (1...6).contains(selectedPages.count), selectedPages.isSubset(of: Set(analysisNumbers)) else { error = ReviewError.invalidPages.localizedDescription; return }
        begin(isDirectReading ? "Preparing marked regions" : "Preparing selected pages")
        defer { end() }
        do {
            let service: any MarkupAnalyzing
            if let suppliedAnalyzer { service = suppliedAnalyzer }
            else { guard let key = try aiCredentials.read() else { throw ReviewError.noKey }; service = AnthropicMarkupAPI(key:key,model:UserDefaults.standard.string(forKey:"analysis-model") ?? AnthropicMarkupAPI.model,endpoint:anthropicEndpoint) }
            let rendered: [AnalysisPage]
            let selected = selectedPages
            if let directPages {
                rendered = directPages.filter { selected.contains($0.number) }
            } else {
                let working = try documentStore.workingPDFURL(for: document), original = documentStore.pdfURL(for: document)
                rendered = try await Task.detached(priority: .userInitiated) {
                    try MarkupPages.render(working: working, original: original, pages: selected.sorted())
                }.value
            }
            try Task.checkCancellation()
            let needsAnalysis = reanalyze || rendered.contains { history.fingerprints[$0.number] != MarkupPages.fingerprint($0) }
            guard needsAnalysis else { message = "This selection is unchanged and already analyzed. Choose Reanalyze to request another paid analysis."; return }
            // Every selected page is intentional context, including unchanged neighbors.
            let pages = rendered
            phase = "Reading your markup with Claude"
            log.info("analysis_request pages=\(pages.count) elapsed=\(Date().timeIntervalSince(self.started))")
            let direct = isDirectReading
            let extracted = try await service.analyze(pages).map { item in
                var tagged = item
                tagged.directInk = direct ? true : nil
                return tagged
            }
            try Task.checkCancellation()
            var next = items
            for item in extracted {
                let normalize: (String) -> String = { $0.split(whereSeparator: { $0.isWhitespace }).joined(separator:" ").lowercased() }
                if let index = next.firstIndex(where: { existing in
                    guard existing.pages == item.pages, existing.directInk == item.directInk else { return false }
                    let quote = normalize(item.quote)
                    if !quote.isEmpty { return normalize(existing.quote) == quote }
                    return normalize(existing.note) == normalize(item.note) && normalize(existing.interpretation) == normalize(item.interpretation)
                }) {
                    let differs = normalize(next[index].note) != normalize(item.note) || normalize(next[index].interpretation) != normalize(item.interpretation)
                    let alreadySaved = (next[index].alternatives ?? []).contains { normalize($0.note) == normalize(item.note) && normalize($0.interpretation) == normalize(item.interpretation) }
                    if differs && !alreadySaved {
                        var alternatives = next[index].alternatives ?? []
                        alternatives.append(ReviewAlternative(note:item.note,interpretation:item.interpretation,date:Date()))
                        next[index].alternatives = alternatives
                    }
                } else { next.append(item) }
            }
            try draftStore.save(next); items = next
            for page in pages { history.fingerprints[page.number] = MarkupPages.fingerprint(page) }
            if let measured = await service.lastUsage() { history.usage.append(measured); usage = history.usage }
            try JSONEncoder().encode(history).write(to:historyURL,options:[.atomic,.completeFileProtectionUntilFirstUserAuthentication])
            changedPages.removeAll { pages.map(\.number).contains($0) }
            reanalyze = false
            selectedID = extracted.first.flatMap { e in next.first(where:{ $0.directInk == e.directInk && $0.pages == e.pages && $0.quote == e.quote && $0.note == e.note })?.id } ?? selectedID
            message = extracted.isEmpty ? "No meaningful markup found in the selection. Try another selection or add a draft manually." : "Analysis saved. Check each passage, transcription, and interpretation before sending."
            showPages()
        } catch is CancellationError { message = "Analysis cancelled. Your saved drafts are kept." }
        catch { self.error = error.localizedDescription; log.error("analysis_failure elapsed=\(Date().timeIntervalSince(self.started))") }
    }
    func useAlternative(_ id: UUID, index: Int) {
        guard !busy, canPersist, let itemIndex = items.firstIndex(where: { $0.id == id }), items[itemIndex].state == .draft,
            var alternatives = items[itemIndex].alternatives, alternatives.indices.contains(index) else { return }
        let chosen = alternatives.remove(at:index)
        alternatives.append(ReviewAlternative(note:items[itemIndex].note,interpretation:items[itemIndex].interpretation,date:Date()))
        items[itemIndex].note = chosen.note; items[itemIndex].interpretation = chosen.interpretation
        items[itemIndex].alternatives = alternatives
        save()
    }
    func addDraft() {
        guard canPersist, !busy else { return }
        var item = ReviewItem(pages:selectedPages.isEmpty ? [jumpPage] : selectedPages.sorted(),quote:"",note:"",interpretation:"",kind:"other")
        item.directInk = isDirectReading ? true : nil
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
        begin("Checking quote against the original", itemID: id); defer { end() }
        do {
            let quote = items[index].quote
            let direct = items[index].directInk == true
            let suppliedText = direct ? directSourceText : nil
            let store = documentStore, document = self.document
            let deliveryQuote = try await Task.detached(priority: .userInitiated) {
                let source: String?
                if let suppliedText {
                    source = suppliedText
                } else if let articleText = try store.articleText(for: document) {
                    source = articleText
                } else if direct {
                    source = nil
                } else {
                    source = PDFDocument(url: store.pdfURL(for: document))?.string
                }
                guard let source else { throw SourceQuoteError.sourceUnavailable }
                return try SourceQuote.exactMatch(quote, in: source)
            }.value
            let api = try service()
            phase = "Sending reviewed highlight to Reader"
            // Persist the exact confirmed payload before touching the network.
            items[index].deliveryQuote = deliveryQuote
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
        begin("Checking delivery in Reader", itemID: id); defer { end() }
        do {
            if let remote = try await service().find(parentID:parent,item:items[index]) {
                items[index].state = .sent; items[index].remoteID = remote; try draftStore.save(items); message = "Confirmed in Reader."
            } else { message = "Not found yet. Keep this item pending and check again, or inspect Reader before allowing a retry." }
        } catch { self.error = error.localizedDescription }
    }
    func clearQuoteFeedback(_ id: UUID) {
        guard feedbackItemID == id, !busy, error != nil else { return }
        error = nil
        feedbackItemID = nil
    }
    func allowRetry(_ id: UUID) {
        guard let index = items.firstIndex(where:{$0.id == id}), items[index].state == .sending else { return }
        items[index].state = .draft; save()
    }
}
