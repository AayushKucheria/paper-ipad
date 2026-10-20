import SwiftUI
import OSLog

@MainActor final class ReaderLibraryModel: ObservableObject {
    @Published var pdfs: [ReaderPDF] = []
    @Published var downloads: [StoredDocument] = []
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
        do { downloads = try store.documents() }
        catch { self.error = "Your downloaded library couldn’t be loaded. Your PDF files remain on this iPad. \(error.localizedDescription)" }
        if api == nil {
            do { if let token = try credentials.read() { self.api = makeAPI(token) } }
            catch { self.error = error.localizedDescription }
        }
        connected = self.api != nil
    }
    func start() async {
        guard !started else { return }
        started = true
        if connected { await refresh() }
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
    func refresh() async {
        guard let api else { return }
        _ = await sync(using: api)
    }
    private func sync(using service: any ReaderServing, token: String? = nil) async -> Bool {
        guard !isRefreshing else { return false }
        isRefreshing = true; refreshStarted = Date(); receivedCount = 0
        error = nil
        let operation = UUID().uuidString
        defer { isRefreshing = false }
        logger.info("refresh_start operation=\(operation, privacy: .public)")
        do {
            let records = try await service.listPDFs { [weak self] count in
                Task { @MainActor in if self?.isRefreshing == true { self?.receivedCount = count } }
            }
            try Task.checkCancellation()
            if let token { try credentials.save(token) }
            let date = Date()
            try catalog.save(records, syncedAt: date)
            pdfs = Self.sorted(records); lastSynced = date
            downloads = try store.documents()
            logger.info("refresh_commit operation=\(operation, privacy: .public) count=\(records.count) elapsed=\(Date().timeIntervalSince(self.refreshStarted))")
            return true
        } catch {
            logger.error("refresh_failure operation=\(operation, privacy: .public) elapsed=\(Date().timeIntervalSince(self.refreshStarted))")
            if token != nil { connectionError = error.localizedDescription }
            else { self.error = error.localizedDescription }
            return false
        }
    }
    func reloadDownloads() {
        do { downloads = try store.documents() }
        catch { self.error = error.localizedDescription }
    }
    func localDocument(for pdf: ReaderPDF) -> StoredDocument? { downloads.first { $0.readerID == pdf.id } }
    func download(_ pdf: ReaderPDF) async -> StoredDocument? {
        // Always prefer the retained working copy, including when the API is unavailable.
        reloadDownloads()
        if let existing = localDocument(for: pdf) { return existing }
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
            downloads = try store.documents()
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
            let metadata = pdfs.first { $0.id == document.readerID }
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
