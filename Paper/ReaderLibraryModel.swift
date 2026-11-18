import SwiftUI
import OSLog

@MainActor final class ReaderLibraryModel: ObservableObject {
    @Published var articles: [ReaderPDF] = []
    @Published var books: [ReaderPDF] = []
    @Published var isRefreshingBooks = false
    @Published var booksError: String?
    @Published var booksLastSynced: Date?
    @Published var isRefreshingArticles = false
    @Published var articleRefreshStarted = Date()
    @Published var articleReceivedCount = 0
    @Published var articleError: String?
    @Published var articlePhase = ""
    @Published var articlesLastSynced: Date?
    private var articleCatalog: ReaderCatalog { ReaderCatalog(url: catalog.url.deletingLastPathComponent().appendingPathComponent("reader-articles.json")) }
    private var bookCatalog: ReaderCatalog { ReaderCatalog(url: catalog.url.deletingLastPathComponent().appendingPathComponent("reader-books.json")) }
    @Published var pdfs: [ReaderPDF] = []
    @Published var downloads: [StoredDocument] = []
    @Published var removed: [StoredDocument] = []
    @Published var error: String?
    @Published var connectionError: String?
    @Published var isRefreshing = false
    @Published var isConnecting = false
    @Published var connected = false
    @Published var refreshStarted = Date()
    @Published var receivedCount = 0
    @Published var lastSynced: Date?
    @Published var activeDownloadID: String?
    @Published var downloadStarted = Date()
    @Published var receivedBytes: Int64 = 0
    @Published var expectedBytes: Int64?
    @Published var downloadErrorID: String?
    @Published var downloadError: String?
    let store: DocumentStore
    let catalog: ReaderCatalog
    private var api: (any ReaderServing)?
    private let credentials: ReaderCredentials
    private let makeAPI: (String) -> any ReaderServing
    private let logger = Logger(subsystem: "com.aayush.paper.reader", category: "Library")
    private var started = false

    init(store: DocumentStore, catalog: ReaderCatalog, api: (any ReaderServing)? = nil,
         credentials: ReaderCredentials = ReaderCredentials(),
         makeAPI: @escaping (String) -> any ReaderServing = { ReaderAPI(token: $0) }) {
        self.store = store; self.catalog = catalog; self.credentials = credentials; self.makeAPI = makeAPI
        self.api = api
        do {
            if let snapshot = try catalog.load() {
                pdfs = Self.sorted(snapshot.documents); lastSynced = snapshot.syncedAt
            }
        } catch { self.error = "Saved Reader metadata couldn’t be loaded. Refresh to rebuild the catalog; your PDFs are kept separately." }
        do { downloads = try store.documents(); removed = try store.removedDocuments() }
        catch { self.error = "Your downloaded library couldn’t be loaded. Your PDF files remain on this iPad. \(error.localizedDescription)" }
        if api == nil {
            do { if let token = try credentials.read() { self.api = makeAPI(token) } }
            catch { self.error = error.localizedDescription }
        }
        do {
            if let snapshot = try articleCatalog.load() {
                articles = Self.sorted(snapshot.documents); articlesLastSynced = snapshot.syncedAt
            }
        } catch { articleError = "Saved article metadata couldn’t be loaded. Refresh Articles to try again." }
        do {
            if let snapshot = try bookCatalog.load() { books = Self.sorted(snapshot.documents); booksLastSynced = snapshot.syncedAt }
        } catch { booksError = "Saved book metadata couldn’t be loaded. Refresh Books to try again." }
        connected = self.api != nil
    }
    func start() async {
        guard !started else { return }
        started = true
        if connected && (lastSynced == nil || Date().timeIntervalSince(lastSynced!) > 900) { await refresh() }
        // Books and articles also refresh at launch, not only when the Library shelf is opened.
        if connected, booksLastSynced.map({ Date().timeIntervalSince($0) > 900 }) ?? true { await refreshBooks() }
        if connected, articlesLastSynced.map({ Date().timeIntervalSince($0) > 900 }) ?? true { await refreshArticles() }
    }
    func connect(token: String) async -> Bool {
        let clean = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { connectionError = "Enter your Reader access token."; return false }
        guard !isRefreshing else { return false }
        isConnecting = true; connectionError = nil
        defer { isConnecting = false }
        let candidate = makeAPI(clean)
        let success = await sync(using: candidate, token: clean)
        if success { api = candidate; connected = true }
        return success
    }
    func refresh(full: Bool = false) async {
        guard let api else { return }
        _ = await sync(using: api, full: full)
    }
    private func sync(using service: any ReaderServing, token: String? = nil, full: Bool = false) async -> Bool {
        guard !isRefreshing else { return false }
        isRefreshing = true; refreshStarted = Date(); receivedCount = 0
        error = nil
        let operation = UUID().uuidString
        defer { isRefreshing = false }
        logger.info("refresh_start operation=\(operation, privacy: .public)")
        do {
            let checkpoint = token == nil && !full ? lastSynced?.addingTimeInterval(-60) : nil
            let updates = try await service.listPDFs(updatedAfter: checkpoint) { [weak self] count in
                Task { @MainActor in if self?.isRefreshing == true { self?.receivedCount = count } }
            }
            try Task.checkCancellation()
            if let token { try credentials.save(token) }
            var merged = checkpoint == nil ? [:] : Dictionary(pdfs.map { ($0.id, $0) }, uniquingKeysWith: { _, new in new })
            for record in updates { merged[record.id] = record }
            let records = Array(merged.values)
            let date = refreshStarted
            try catalog.save(records, syncedAt: date)
            pdfs = Self.sorted(records); lastSynced = date
            downloads = try store.documents(); removed = try store.removedDocuments()
            logger.info("refresh_commit operation=\(operation, privacy: .public) count=\(records.count) elapsed=\(Date().timeIntervalSince(self.refreshStarted))")
            return true
        } catch {
            logger.error("refresh_failure operation=\(operation, privacy: .public) elapsed=\(Date().timeIntervalSince(self.refreshStarted))")
            if token != nil { connectionError = error.localizedDescription }
            else { self.error = error.localizedDescription }
            return false
        }
    }
    func refreshArticles() async {
        guard !isRefreshingArticles, let api else { return }
        isRefreshingArticles = true; articleRefreshStarted = Date(); articleReceivedCount = 0; articleError = nil
        defer { isRefreshingArticles = false }
        do {
            let records = try await api.listArticles { [weak self] count in
                Task { @MainActor in if self?.isRefreshingArticles == true { self?.articleReceivedCount = count } }
            }
            try Task.checkCancellation()
            let date = Date()
            try articleCatalog.save(records, syncedAt: date)
            articles = Self.sorted(records); articlesLastSynced = date
        } catch {
            logger.error("articles_refresh_failure kind=\(ReaderAPI.kind(of: error), privacy: .public)")
            articleError = error.localizedDescription
        }
    }
    func refreshBooks() async {
        guard !isRefreshingBooks, let api else { return }
        isRefreshingBooks = true; booksError = nil
        defer { isRefreshingBooks = false }
        do {
            let records = try await api.listBooks { _ in }
            try Task.checkCancellation()
            let date = Date()
            try bookCatalog.save(records, syncedAt: date)
            books = Self.sorted(records); booksLastSynced = date
        } catch {
            logger.error("books_refresh_failure kind=\(ReaderAPI.kind(of: error), privacy: .public)")
            booksError = error.localizedDescription
        }
    }
    func prepareBook(_ book: ReaderPDF) async -> StoredDocument? {
        reloadDownloads()
        if let existing = localDocument(for: book) { return existing }
        if let retained = removedDocument(for: book) {
            do { try store.restoreDownload(retained); reloadDownloads(); return retained }
            catch { booksError = "The retained EPUB couldn’t be restored. Check Recently Removed."; return nil }
        }
        guard activeDownloadID == nil else { return nil }
        guard let api else { booksError = "Connect Reader to download an EPUB."; return nil }
        activeDownloadID = book.id; downloadStarted = Date(); receivedBytes = 0; expectedBytes = nil
        downloadError = nil; downloadErrorID = nil; booksError = nil
        let operation = UUID().uuidString
        logger.info("book_prepare_start operation=\(operation, privacy: .public)")
        defer { activeDownloadID = nil; articlePhase = "" }
        do {
            articlePhase = "Downloading the EPUB"
            let file = try await api.downloadBook(id: book.id) { [weak self] received, total in
                Task { @MainActor in
                    guard self?.activeDownloadID == book.id else { return }
                    self?.receivedBytes = max(0, received); self?.expectedBytes = total
                }
            }
            defer { try? FileManager.default.removeItem(at: file) }
            try Task.checkCancellation()
            articlePhase = "Preparing chapters for offline reading"
            logger.info("book_unpack_start operation=\(operation, privacy: .public) elapsed=\(Date().timeIntervalSince(self.downloadStarted))")
            let store = store
            let document = try await Task.detached(priority: .userInitiated) { try store.importEPUB(at: file, metadata: book) }.value
            reloadDownloads()
            logger.info("book_prepare_complete operation=\(operation, privacy: .public) elapsed=\(Date().timeIntervalSince(self.downloadStarted))")
            return document
        } catch {
            logger.error("book_prepare_failure operation=\(operation, privacy: .public) elapsed=\(Date().timeIntervalSince(self.downloadStarted))")
            downloadErrorID = book.id; downloadError = error.localizedDescription; booksError = error.localizedDescription
            return nil
        }
    }
    func prepareArticleForDirectReading(_ article: ReaderPDF) async -> StoredDocument? {
        reloadDownloads()
        if let existing = localDocument(for: article) { return existing }
        if let retained = removedDocument(for: article) {
            do { try store.restoreDownload(retained); reloadDownloads(); return retained }
            catch { articleError = "The retained article couldn’t be restored. Check Recently Removed."; return nil }
        }
        guard activeDownloadID == nil else { return nil }
        guard let api else { articleError = "Connect Reader to prepare an article."; return nil }
        activeDownloadID = article.id; downloadStarted = Date(); receivedBytes = 0; expectedBytes = nil
        downloadError = nil; downloadErrorID = nil; articleError = nil; articlePhase = "Fetching article text"
        let operation = UUID().uuidString
        logger.info("direct_article_start operation=\(operation, privacy: .public)")
        defer { activeDownloadID = nil; articlePhase = "" }
        do {
            let html = try await api.articleContent(id: article.id)
            try Task.checkCancellation()
            articlePhase = "Preparing article"
            logger.info("direct_article_layout operation=\(operation, privacy: .public) elapsed=\(Date().timeIntervalSince(self.downloadStarted))")
            let snapshot = try await DirectArticlePreparation().prepare(html: html, title: article.title ?? "Untitled article", baseURL: article.sourceURL) { phase in
                articlePhase = phase
                logger.info("direct_article_figures operation=\(operation, privacy: .public) elapsed=\(Date().timeIntervalSince(self.downloadStarted))")
            }
            try Task.checkCancellation()
            let store = store
            let document = try await Task.detached(priority: .userInitiated) {
                try store.importDirectArticle(metadata: article, originalHTML: html, readingHTML: snapshot.html,
                                              sourceText: snapshot.text, missingFigures: snapshot.missingFigures)
            }.value
            reloadDownloads()
            logger.info("direct_article_complete operation=\(operation, privacy: .public) elapsed=\(Date().timeIntervalSince(self.downloadStarted))")
            return document
        } catch {
            logger.error("direct_article_failure operation=\(operation, privacy: .public) elapsed=\(Date().timeIntervalSince(self.downloadStarted))")
            downloadErrorID = article.id; downloadError = error.localizedDescription; articleError = error.localizedDescription
            return nil
        }
    }
    func filteredArticles(query: String) -> [ReaderPDF] {
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return articles }
        return articles.filter { [$0.title, $0.author, $0.summary].compactMap { $0 }.joined(separator: " ").localizedStandardContains(query) }
    }
    func prepareArticle(_ article: ReaderPDF) async -> StoredDocument? {
        reloadDownloads()
        if let existing = localDocument(for: article) { return existing }
        if let retained = removedDocument(for: article) {
            do { try store.restoreDownload(retained); reloadDownloads(); return retained }
            catch { articleError = "The retained article couldn’t be restored. Check Recently Removed."; return nil }
        }
        guard activeDownloadID == nil else { return nil }
        guard let api else { articleError = "Connect Reader to prepare an article."; return nil }
        activeDownloadID = article.id; downloadStarted = Date(); receivedBytes = 0; expectedBytes = nil
        downloadError = nil; downloadErrorID = nil; articleError = nil; articlePhase = "Fetching article text"
        let operation = UUID().uuidString
        logger.info("article_prepare_start operation=\(operation, privacy: .public)")
        defer { activeDownloadID = nil; articlePhase = "" }
        do {
            let html = try await api.articleContent(id: article.id)
            try Task.checkCancellation()
            articlePhase = "Preparing pages with space for handwriting"
            let rendered = try await ArticleRenderer().render(html: html, title: article.title ?? "Untitled article", baseURL: article.sourceURL)
            try Task.checkCancellation()
            articlePhase = "Saving your reading copy"
            let temporary = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).pdf")
            defer { try? FileManager.default.removeItem(at: temporary) }
            try rendered.pdf.write(to: temporary, options: .atomic)
            let store = store
            let document = try await Task.detached(priority: .userInitiated) {
                try store.importReaderArticle(at: temporary, metadata: article, html: html, text: rendered.text, missingFigures: rendered.missingFigureCount)
            }.value
            reloadDownloads()
            logger.info("article_prepare_complete operation=\(operation, privacy: .public) elapsed=\(Date().timeIntervalSince(self.downloadStarted))")
            return document
        } catch {
            logger.error("article_prepare_failure operation=\(operation, privacy: .public) elapsed=\(Date().timeIntervalSince(self.downloadStarted))")
            downloadErrorID = article.id; downloadError = error.localizedDescription; articleError = error.localizedDescription
            return nil
        }
    }
    func reloadDownloads() {
        do { downloads = try store.documents(); removed = try store.removedDocuments() }
        catch { self.error = error.localizedDescription }
    }
    func localDocument(for pdf: ReaderPDF) -> StoredDocument? { downloads.first { $0.readerID == pdf.id } }
    func removedDocument(for pdf: ReaderPDF) -> StoredDocument? { removed.first { $0.readerID == pdf.id } }
    func download(_ pdf: ReaderPDF) async -> StoredDocument? {
        // Always prefer the retained working copy, including when the API is unavailable.
        reloadDownloads()
        if let existing = localDocument(for: pdf) { return existing }
        if let retained = removedDocument(for: pdf) {
            do { try store.restoreDownload(retained);reloadDownloads();return retained }
            catch { self.error = "The retained PDF couldn’t be restored. Check Recently Removed.";return nil }
        }
        guard activeDownloadID == nil else { return nil }
        guard let api else { error = "Connect Reader to download a PDF."; return nil }
        activeDownloadID = pdf.id; downloadStarted = Date(); receivedBytes = 0; expectedBytes = nil
        downloadError = nil; downloadErrorID = nil
        let operation = UUID().uuidString
        defer { activeDownloadID = nil }
        do {
            let file = try await api.downloadPDF(id: pdf.id) { [weak self] received, total in
                Task { @MainActor in
                    guard self?.activeDownloadID == pdf.id else { return }
                    self?.receivedBytes = max(0, received); self?.expectedBytes = total
                }
            }
            defer { try? FileManager.default.removeItem(at: file) }
            try Task.checkCancellation()
            logger.info("pdf_validation_start operation=\(operation, privacy: .public) elapsed=\(Date().timeIntervalSince(self.downloadStarted))")
            let store = store
            let document = try await Task.detached(priority: .userInitiated) {
                try store.importReaderPDF(at: file, metadata: pdf)
            }.value
            downloads = try store.documents(); removed = try store.removedDocuments()
            logger.info("pdf_persisted operation=\(operation, privacy: .public) elapsed=\(Date().timeIntervalSince(self.downloadStarted))")
            return document
        } catch {
            logger.error("pdf_download_failure operation=\(operation, privacy: .public) elapsed=\(Date().timeIntervalSince(self.downloadStarted))")
            downloadErrorID = pdf.id; downloadError = error.localizedDescription
            return nil
        }
    }
    func filteredPDFs(query: String) -> [ReaderPDF] {
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return pdfs }
        return pdfs.filter { [$0.title, $0.author, $0.summary].compactMap { $0 }.joined(separator: " ").localizedStandardContains(query) }
    }
    func filteredDownloads(query: String) -> [StoredDocument] {
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return downloads }
        return downloads.filter { document in
            let metadata = (pdfs + articles + books).first { $0.id == document.readerID }
            return [metadata?.title ?? document.title, metadata?.author ?? document.author,
                    metadata?.summary ?? document.summary].compactMap { $0 }.joined(separator: " ").localizedStandardContains(query)
        }
    }
    private static func sorted(_ records: [ReaderPDF]) -> [ReaderPDF] {
        records.sorted {
            if $0.savedAt != $1.savedAt { return ($0.savedAt ?? "") > ($1.savedAt ?? "") }
            return ($0.title ?? "").localizedStandardCompare($1.title ?? "") == .orderedAscending
        }
    }
}
