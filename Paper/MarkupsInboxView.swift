import SwiftUI
import PDFKit
import OSLog

struct MarkupInboxEntry: Identifiable {
    let document: StoredDocument
    let pending: [ReviewItem]
    let changedPages: [Int]
    let hasDirectInk: Bool
    var id: UUID { document.id }
}

enum MarkupInboxInventory {
    static func entries(store: DocumentStore) throws -> [MarkupInboxEntry] {
        try store.documents().compactMap { document in
            let items = try ReviewStore(url: store.reviewURL(for: document)).load()
            let pending = items.filter { $0.state == .draft || $0.state == .sending }
            let originalURL = store.pdfURL(for: document)
            let editedURL = originalURL.deletingLastPathComponent().appendingPathComponent("reading.pdf")
            let workingURL = FileManager.default.fileExists(atPath: editedURL.path) ? editedURL : originalURL
            let hasDirectInk = DirectInkStore(document: document, store: store).hasInk
            let changed: [Int]
            if let working = PDFDocument(url: workingURL) {
                let marked = MarkupPages.marked(in: working, original: PDFDocument(url: originalURL))
                let historyURL = store.reviewURL(for: document).deletingLastPathComponent().appendingPathComponent("analysis.json")
                let history: ReviewAnalysisHistory
                if FileManager.default.fileExists(atPath: historyURL.path) {
                    history = try JSONDecoder().decode(ReviewAnalysisHistory.self, from: Data(contentsOf: historyURL))
                } else { history = ReviewAnalysisHistory() }
                changed = try marked.filter { number in
                    guard let page = try MarkupPages.render(working: workingURL, original: originalURL, pages: [number]).first else { return false }
                    return history.fingerprints[number] != MarkupPages.fingerprint(page)
                }
            } else { changed = [] }
            guard !pending.isEmpty || !changed.isEmpty || hasDirectInk else { return nil }
            return MarkupInboxEntry(document: document, pending: pending, changedPages: changed, hasDirectInk: hasDirectInk)
        }
    }
}

struct MarkupsInboxView: View {
    let store: DocumentStore
    let readerCredentials: ReaderCredentials
    let aiCredentials: ReaderCredentials
    let readerBaseURL: URL
    let anthropicEndpoint: URL
    let query: String
    let onOpen: (StoredDocument, UUID?) -> Void
    var onReadDirect: ((StoredDocument) -> Void)? = nil
    @State private var entries: [MarkupInboxEntry] = []
    @State private var loading = true
    @State private var hasReviewHistory = false
    @State private var error: String?
    @State private var started = Date()
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if loading {
                HStack { ProgressView(); TimelineView(.periodic(from: started, by: 1)) { context in
                    Text("Finding your saved markup · \(Int(context.date.timeIntervalSince(started)))s").font(.subheadline)
                } }.padding(26)
            } else if let error { Text(error).padding(26) }
            else if entries.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "pencil.and.outline").font(.largeTitle)
                    Text(hasReviewHistory ? "All caught up" : "Your markup will appear here").font(.system(size: 25, design: .serif))
                    Text(hasReviewHistory ? "Your reviewed notes stay with their documents. New marks will appear here when they’re ready to review." : "Read and write on a downloaded document. Finish with Done, then return here to review your notes.").foregroundStyle(.secondary).multilineTextAlignment(.center)
                }.padding(40).frame(maxWidth: .infinity)
            }
            ForEach(entries.filter { query.isEmpty || ([$0.document.title] + $0.pending.flatMap { [$0.quote, $0.note, $0.interpretation] }).joined(separator: " ").localizedStandardContains(query) }) { entry in
                InboxDocumentCards(model: ReviewModel(document: entry.document, store: store, readerCredentials: readerCredentials, aiCredentials: aiCredentials, readerBaseURL: readerBaseURL, anthropicEndpoint: anthropicEndpoint), changedPages: entry.changedPages, hasDirectInk: entry.hasDirectInk, onOpen: onOpen, onReadDirect: onReadDirect)
            }
        }.background(.background)
        .task {
            let log = Logger(subsystem: "com.aayush.paper.reader", category: "MarkupInbox")
            let operation = UUID().uuidString; started = Date()
            log.info("inventory_start operation=\(operation, privacy: .public)")
            do {
                let inventory = try await Task.detached(priority: .userInitiated) {
                    let entries = try MarkupInboxInventory.entries(store: store)
                    let hasHistory = try store.documents().contains { document in
                        !(try ReviewStore(url: store.reviewURL(for: document)).load()).isEmpty
                    }
                    return (entries, hasHistory)
                }.value
                entries = inventory.0; hasReviewHistory = inventory.1
                log.info("inventory_complete operation=\(operation, privacy: .public) documents=\(entries.count) elapsed=\(Date().timeIntervalSince(started))")
            } catch {
                self.error = "Some saved markup couldn’t be read. Open the document to see your marks."
                log.error("inventory_failure operation=\(operation, privacy: .public) elapsed=\(Date().timeIntervalSince(started))")
            }
            loading = false
        }
    }
}

private struct InboxDocumentCards: View {
    @StateObject var model: ReviewModel
    let changedPages: [Int]
    let hasDirectInk: Bool
    let onOpen: (StoredDocument, UUID?) -> Void
    let onReadDirect: ((StoredDocument) -> Void)?
    @State private var task: Task<Void, Never>?
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                VStack(alignment: .leading, spacing: 5) {
                    Text(model.document.title).font(.system(size: 24, design: .serif))
                    Text("\(model.pendingItems.count) to review\(changedPages.isEmpty ? "" : " · \(changedPages.count) pages with new marks")").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if !changedPages.isEmpty || model.pendingItems.contains(where: { $0.directInk != true }) {
                    Button("Review pages", systemImage: "doc.text.magnifyingglass") { onOpen(model.document, nil) }
                }
                if hasDirectInk, let onReadDirect {
                    Button("Open marked text", systemImage: "scribble") { onReadDirect(model.document) }
                }
            }
            if !changedPages.isEmpty {
                Button("Choose marked pages to analyze", systemImage: "sparkles") { onOpen(model.document, nil) }.buttonStyle(.bordered)
            }
            ForEach(model.items.indices.filter { model.items[$0].state == .draft || model.items[$0].state == .sending }, id: \.self) { index in
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Label(model.items[index].locationLabel, systemImage: model.items[index].quote.isEmpty ? "scribble" : "highlighter")
                        Spacer()
                        Button(model.items[index].directInk == true ? "Open review" : "See in PDF") { onOpen(model.document, model.items[index].id) }.font(.subheadline)
                    }.font(.caption).foregroundStyle(.secondary)
                    if model.items[index].directInk != true, let page = model.items[index].pages.first {
                        InboxPagePreview(url: model.documentStore.pdfURL(for: model.document).deletingLastPathComponent().appendingPathComponent("reading.pdf"), page: page)
                    }
                    if model.items[index].quote.isEmpty {
                        Text("Drawing or note without a passage. Keep it here, or choose a meaningful source passage before sending.").font(.footnote).foregroundStyle(.secondary)
                    }
                    field("Quoted passage", text: $model.items[index].quote, disabled: model.items[index].state != .draft)
                        .onChange(of: model.items[index].quote) { _, _ in model.clearQuoteFeedback(model.items[index].id) }
                    if model.feedbackItemID == model.items[index].id, let error = model.error {
                        Label(error, systemImage: "exclamationmark.circle").font(.caption).foregroundStyle(.secondary)
                    }
                    field("Your handwriting", text: $model.items[index].note, disabled: model.items[index].state != .draft)
                    if !model.items[index].interpretation.isEmpty { field("AI interpretation", text: $model.items[index].interpretation, disabled: model.items[index].state != .draft) }
                    HStack {
                        if model.items[index].state == .draft {
                            Button(model.items[index].canSend ? "Skip" : "Keep on iPad") { model.items[index].state = .skipped; model.save() }
                            Spacer()
                            Button("Confirm and send to Reader") { let id = model.items[index].id; task = Task { await model.send(id) } }.buttonStyle(.borderedProminent).disabled(!model.items[index].canSend || model.document.readerID == nil)
                        } else {
                            Text("Delivery unconfirmed").font(.caption)
                            Button("Check delivery") { let id = model.items[index].id; task = Task { await model.checkDelivery(id) } }
                        }
                    }.disabled(model.busy)
                }.padding(20).background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
            }
            if model.busy {
                HStack { ProgressView(); TimelineView(.periodic(from: model.started, by: 1)) { context in Text("\(model.phase) · \(Int(context.date.timeIntervalSince(model.started)))s").font(.caption) } }
            }
            if model.feedbackItemID == nil, let error = model.error { Text(error).font(.subheadline).foregroundStyle(.secondary) }
            if let message = model.message { Text(message).font(.subheadline).foregroundStyle(.secondary) }
            if model.pendingItems.isEmpty && changedPages.isEmpty && !hasDirectInk { Text("All caught up").font(.headline) }
        }.padding(22)
        .onChange(of: model.items) { _, _ in model.save() }
        .onDisappear { BackupCoordinator.shared.requestBackup(store: model.documentStore) }
    }
    private func field(_ title: String, text: Binding<String>, disabled: Bool) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            TextEditor(text: text).frame(minHeight: 70).padding(5).background(.background, in: RoundedRectangle(cornerRadius: 8)).disabled(disabled || model.busy)
        }
    }
}

private struct InboxPagePreview: View {
    let url: URL
    let page: Int
    @State private var thumbnail: UIImage?
    var body: some View {
        Group {
            if let thumbnail { Image(uiImage: thumbnail).resizable().scaledToFit().frame(maxHeight: 230).frame(maxWidth: .infinity).accessibilityLabel("Saved markup on page \(page)") }
            else { ProgressView().frame(height: 100).frame(maxWidth: .infinity) }
        }.task(id: "\(url.path)-\(page)") {
            thumbnail = await Task.detached(priority: .utility) {
                PDFDocument(url: url)?.page(at: max(0, page - 1))?.thumbnail(of: CGSize(width: 700, height: 900), for: .mediaBox)
            }.value
        }
    }
}
