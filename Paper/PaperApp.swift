import SwiftUI
import UniformTypeIdentifiers

@main struct PaperApp: App {
    var body: some Scene { WindowGroup { ReadingView() } }
}

private struct LibrarySetup {
    let store: DocumentStore
    let catalog: ReaderCatalog
    let credentials: ReaderCredentials
    let baseURL: URL
    let aiCredentials: ReaderCredentials
    init() {
        let files = FileManager.default
        var root = files.urls(for: .documentDirectory, in: .userDomainMask)[0]
        var service = "com.aayush.paper.reader"
        var baseURL = URL(string: "https://readwise.io/api/v3/")!
        #if DEBUG
        let environment = ProcessInfo.processInfo.environment
        if environment["PAPER_UI_TEST"] == "1" {
            root.appendPathComponent("UITestLibrary", isDirectory: true)
            service += ".uitest"
            if environment["PAPER_TEST_RESET"] == "1" {
                try? files.removeItem(at: root)
                try? ReaderCredentials(service: service).remove()
                try? ReaderCredentials(service: service + ".anthropic").remove()
                for key in ["shortlist", "reading", "lastOpened"] {
                    UserDefaults.standard.removeObject(forKey: "paper.uitest." + key)
                }
            }
            if let value = environment["PAPER_READER_BASE_URL"], let url = URL(string: value),
               ["localhost", "127.0.0.1"].contains(url.host ?? "") { baseURL = url }
        }
        #endif
        self.baseURL = baseURL
        store = DocumentStore(root: root.appendingPathComponent("Library", isDirectory: true))
        catalog = ReaderCatalog(url: root.appendingPathComponent("reader-catalog.json"))
        credentials = ReaderCredentials(service: service)
        aiCredentials = ReaderCredentials(service: service + ".anthropic")
        // One-time development provisioning, outside the app bundle and repository.
        // The credential file is removed only after successful Keychain storage.
        let provision = files.temporaryDirectory.appendingPathComponent("reader-token.txt")
        do { try aiCredentials.consumeProvisionedToken(at: files.temporaryDirectory.appendingPathComponent("anthropic-key.txt")) }
        catch { /* AI settings allow a retry. */ }
        do { try credentials.consumeProvisionedToken(at: provision) }
        catch { /* Connection UI offers retry without risking any saved PDFs. */ }
    }
}

private func libraryPreferenceKey(_ name: String) -> String {
    #if DEBUG
    if ProcessInfo.processInfo.environment["PAPER_UI_TEST"] == "1" { return "paper.uitest." + name }
    #endif
    return "paper." + name
}

struct ReadingView: View {
    @StateObject private var reading: ReadingModel
    @StateObject private var library: ReaderLibraryModel
    private let readerCredentials: ReaderCredentials
    private let aiCredentials: ReaderCredentials
    private let readerBaseURL: URL
    @State private var reviewDocument: StoredDocument?
    @State private var removing: StoredDocument?
    @State private var showRemoved = false
    @State private var showAISettings = false
    @FocusState private var searchFocused: Bool
    private enum Shelf: String { case downloaded = "Downloaded", reading = "Reading", shortlist = "Shortlist", library = "Library", markups = "Markups" }
    private enum Format: String, CaseIterable { case all = "All formats", pdf = "PDFs", article = "Articles", epub = "Books" }
    @State private var shelf = Shelf.downloaded
    @State private var format = Format.all
    @State private var booksRefreshStarted = Date()
    @AppStorage(libraryPreferenceKey("shortlist")) private var shortlistData = Data()
    @AppStorage(libraryPreferenceKey("reading")) private var currentlyReadingData = Data()
    @AppStorage(libraryPreferenceKey("lastOpened")) private var lastOpenedData = Data()
    private var shortlist: Set<String> { (try? JSONDecoder().decode(Set<String>.self, from: shortlistData)) ?? [] }
    private var currentlyReading: Set<String> { (try? JSONDecoder().decode(Set<String>.self, from: currentlyReadingData)) ?? [] }
    private var lastOpened: [String: Date] { (try? JSONDecoder().decode([String: Date].self, from: lastOpenedData)) ?? [:] }
    @State private var showBackup = false
    @State private var reviewItemID: UUID?
    @State private var inboxRevision = UUID()
    @Environment(\.scenePhase) private var scenePhase
    @ObservedObject private var backup = BackupCoordinator.shared
    @State private var query = ""
    @State private var showImporter = false
    @State private var showConnection = false
    @State private var unavailablePDF: ReaderPDF?
    @State private var status = "Your downloads and markup stay on this iPad."
    init() {
        let setup = LibrarySetup()
        readerCredentials = setup.credentials; aiCredentials = setup.aiCredentials; readerBaseURL = setup.baseURL
        _reading = StateObject(wrappedValue: ReadingModel(store: setup.store))
        _library = StateObject(wrappedValue: ReaderLibraryModel(store: setup.store, catalog: setup.catalog,
            credentials: setup.credentials, makeAPI: { ReaderAPI(token: $0, baseURL: setup.baseURL) }))
    }
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                libraryControls.padding(.horizontal, 20).padding(.vertical, 10)
                ScrollView {
                    LazyVStack(spacing: 1) {
                        if shelf == .markups {
                            MarkupsInboxView(store: reading.store, readerCredentials: readerCredentials, aiCredentials: aiCredentials, readerBaseURL: readerBaseURL, anthropicEndpoint: analysisEndpoint, query: query, onOpen: { document, itemID in
                                searchFocused = false; reviewItemID = itemID; reviewDocument = document
                            }, onReadDirect: { open($0) }).id(inboxRevision)
                        } else { shelfRows }
                    }.background(Color(uiColor: .separator).opacity(0.15))
                        .clipShape(RoundedRectangle(cornerRadius: 10)).padding(.horizontal, 20).padding(.bottom, 16)
                }.scrollDismissesKeyboard(.interactively)
            }.frame(maxWidth: 1000).frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(uiColor: .systemGroupedBackground))
                .navigationTitle("Paper").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button(library.connected ? "Reader connected" : "Connect Reader", systemImage: "books.vertical") { showConnection = true }
                            .accessibilityIdentifier("reader-connection")
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu {
                            Button("Recently Removed") { showRemoved = true }
                            Button("AI settings") { showAISettings = true }
                            Button("Backups", systemImage: "externaldrive") { showBackup = true }
                        } label: { Image(systemName:"ellipsis.circle") }.accessibilityLabel("Library actions")
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Import PDF or ePub", systemImage: "folder") { showImporter = true }.disabled(reading.importing)
                    }
                }
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    Text(backupStatus).font(.caption).foregroundStyle(.secondary).padding(.vertical, 7)
                        .frame(maxWidth: .infinity).background(.regularMaterial)
                }
                .overlay { if reading.importing { importProgress } }
                .fileImporter(isPresented: $showImporter, allowedContentTypes: [.pdf, UTType(filenameExtension: "epub") ?? .data]) { result in
                    switch result {
                    case .success(let url): reading.importPDF(url)
                    case .failure(let error): reading.error = error.localizedDescription
                    }
                }
                .fullScreenCover(item: $reviewDocument) { document in
                    ReviewView(model: makeReviewModel(document))
                }
                .sheet(isPresented: $showBackup) { BackupSettingsView(store: reading.store) }
                .onChange(of: reviewDocument) { _, document in if document == nil { inboxRevision = UUID(); backup.requestBackup(store: reading.store) } }
                .sheet(isPresented:$showRemoved) { RemovedDownloadsView(store:reading.store,onChange:{library.reloadDownloads()}) }
                .sheet(isPresented:$showAISettings) { AISettingsView(credentials:aiCredentials) }
                .confirmationDialog("Remove this download?",isPresented:Binding(get:{removing != nil},set:{if !$0{removing=nil}}),titleVisibility:.visible) {
                    Button("Move to Recently Removed",role:.destructive) {
                        if let document=removing {
                            do { try reading.store.removeDownload(document);library.reloadDownloads();status="Moved to Recently Removed. Your markup can be restored." }
                            catch { reading.error="This PDF couldn’t be removed. Its files remain on this iPad." }
                        }
                        removing=nil
                    }
                } message: { Text("The document, markup, and review drafts can be restored from Recently Removed. Storage is freed only when you permanently delete them.") }
                .sheet(isPresented: $showConnection) { connectionSheet }
                .sheet(item: $unavailablePDF) { pdf in unavailableSheet(pdf) }
                .fullScreenCover(item: $reading.selected) { document in
                    if reading.previewURL == nil, let sections = try? reading.store.directReadingSections(for: document), !sections.isEmpty {
                        DirectArticleReader(document: document, sections: sections, store: reading.store,
                            onClose: { reading.selected = nil; inboxRevision = UUID(); backup.requestBackup(store: reading.store) },
                            makeReview: { pages, text in makeReviewModel(document, directPages: pages, directSourceText: text) })
                    } else if let url = reading.previewURL {
                        NativePDFPreview(document: document, url: url, store: reading.store,
                            onSave: { status = "Saved on this iPad"; backup.requestBackup(store: reading.store) },
                            onError: { reading.error = $0 },
                            onClose: { reading.selected = nil; library.reloadDownloads(); inboxRevision = UUID(); backup.requestBackup(store: reading.store) })
                            .ignoresSafeArea()
                            .alert("Couldn’t save your PDF", isPresented: readingErrorPresented) {
                                Button("OK") { reading.error = nil }
                            } message: { Text(reading.error ?? "") }
                    }
                }
                .alert("Couldn’t open this document", isPresented: readingErrorPresented) {
                    Button("OK") { reading.error = nil }
                } message: { Text(reading.error ?? "") }
                .onChange(of: reading.documents) { _, _ in library.reloadDownloads() }
                .onChange(of: library.connected) { _, connected in if connected { refreshVisibleCatalogs() } }
                .onChange(of: scenePhase) { _, phase in if phase == .active { backup.requestBackup(store: reading.store); inboxRevision = UUID() } }
                .task { await library.start(); backup.requestBackup(store: reading.store) }
        }.tint(Color(red: 0.20, green: 0.31, blue: 0.25)).preferredColorScheme(.light)
    }
    private var analysisEndpoint: URL {
        #if DEBUG
        if ProcessInfo.processInfo.environment["PAPER_UI_TEST"] == "1", ["localhost","127.0.0.1"].contains(readerBaseURL.host ?? "") {
            return readerBaseURL.deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("anthropic/messages")
        }
        #endif
        return URL(string:"https://api.anthropic.com/v1/messages")!
    }
    private var backupStatus: String {
        if backup.isBackingUp { return "Saved on this iPad · Backing up…" }
        if backup.errorMessage != nil { return "Saved on this iPad · Backup needs attention in Backups" }
        if let date = backup.lastBackup { return "Saved on this iPad · Last backup " + date.formatted(date: .abbreviated, time: .shortened) }
        return status + " · Set up Backups to keep another copy."
    }
    private var libraryControls: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 5) {
                tab(.downloaded, id: "downloaded-tab")
                tab(.reading, id: "reading-tab")
                tab(.shortlist, id: "shortlisted-tab")
                tab(.library, id: "library-tab")
                tab(.markups, id: "markups-tab")
                Spacer(minLength: 0)
            }
            HStack(spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Search title, author, or description", text: $query)
                        .focused($searchFocused)
                        .accessibilityIdentifier("pdf-search")
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                    if !query.isEmpty {
                        Button { query = "" } label: { Image(systemName: "xmark.circle.fill") }
                            .accessibilityLabel("Clear search")
                    }
                }.padding(8).background(.background, in: RoundedRectangle(cornerRadius: 8))
                if shelf != .markups {
                    Menu {
                        ForEach(Format.allCases, id: \.self) { choice in
                            Button {
                                format = choice
                                refreshVisibleCatalogs()
                            } label: {
                                if choice == format { Label(choice.rawValue, systemImage: "checkmark") }
                                else { Text(choice.rawValue) }
                            }.accessibilityIdentifier(choice == .article ? "articles-tab" : "format-\(choice)")
                        }
                    } label: {
                        Label(format.rawValue, systemImage: "line.3.horizontal.decrease")
                    }.buttonStyle(.bordered).accessibilityIdentifier("format-filter")
                    if shelf == .library && library.connected {
                        Menu {
                            Button("Check for updates") { refreshVisibleCatalogs(force: true) }
                            Button("Refresh entire catalog") {
                                Task { await library.refresh(full: true) }
                                refreshVisibleCatalogs(force: true, includePDFs: false)
                            }
                        } label: { Image(systemName: "arrow.clockwise") }
                            .accessibilityLabel("Refresh catalog").accessibilityIdentifier("refresh-library")
                    }
                }
            }
            if shelf != .markups {
                HStack(spacing: 8) {
                    if let start = activeCatalogStarted {
                        HStack(spacing: 6) {
                            ProgressView().controlSize(.small)
                            elapsed(from: start, hint: "Checking Reader")
                        }.accessibilityElement(children: .combine).accessibilityIdentifier("refresh-progress")
                    }
                    let count = visibleLocal.count + visibleRemote.count
                    Text(count == 1 ? "1 document" : "\(count) documents")
                        .font(.caption).foregroundStyle(.secondary).accessibilityIdentifier("pdf-count")
                    Spacer()
                }
            }
            if let error = visibleCatalogError {
                HStack(alignment: .top) {
                    Text(error).font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("Retry") { refreshVisibleCatalogs(force: true) }
                }.accessibilityIdentifier("library-error")
            }
        }
    }

    private var activeCatalogStarted: Date? {
        guard shelf == .library else { return nil }
        if library.isRefreshing, format == .all || format == .pdf { return library.refreshStarted }
        if library.isRefreshingArticles, format == .all || format == .article { return library.articleRefreshStarted }
        if library.isRefreshingBooks, format == .all || format == .epub { return booksRefreshStarted }
        return nil
    }

    private var visibleCatalogError: String? {
        guard shelf == .library else { return nil }
        switch format {
        case .all: return library.error ?? library.articleError ?? library.booksError
        case .pdf: return library.error
        case .article: return library.articleError
        case .epub: return library.booksError
        }
    }

    private func refreshVisibleCatalogs(force: Bool = false, includePDFs: Bool = true) {
        guard shelf == .library, library.connected else { return }
        if includePDFs, force, (format == .all || format == .pdf) { Task { await library.refresh() } }
        if (format == .all || format == .article),
           force || (library.articlesLastSynced.map { Date().timeIntervalSince($0) > 900 } ?? true) {
            Task { await library.refreshArticles() }
        }
        if (format == .all || format == .epub),
           force || (library.booksLastSynced.map { Date().timeIntervalSince($0) > 900 } ?? true) {
            if !library.isRefreshingBooks { booksRefreshStarted = Date() }
            Task { await library.refreshBooks() }
        }
    }

    private func tab(_ choice: Shelf, id: String) -> some View {
        Button {
            shelf = choice
            if choice == .markups { inboxRevision = UUID() }
            refreshVisibleCatalogs()
        } label: {
            Text(choice.rawValue).font(.subheadline.weight(.medium)).padding(.horizontal, 11).frame(minHeight: 40)
                .foregroundStyle(shelf == choice ? Color.white : Color.accentColor)
                .background(shelf == choice ? Color.accentColor : .clear, in: RoundedRectangle(cornerRadius: 7))
        }.buttonStyle(.plain).accessibilityIdentifier(id).accessibilityAddTraits(shelf == choice ? .isSelected : [])
    }

    private func makeReviewModel(_ document: StoredDocument, directPages: [AnalysisPage]? = nil, directSourceText: String? = nil) -> ReviewModel {
        let isDirect = directPages != nil || usesDirectReader(document)
        let model = ReviewModel(document: document, store: reading.store, readerCredentials: readerCredentials,
            aiCredentials: aiCredentials, readerBaseURL: readerBaseURL, anthropicEndpoint: analysisEndpoint,
            directPages: isDirect ? (directPages ?? []) : nil, directSourceText: directSourceText)
        if let reviewItemID { model.select(reviewItemID) }
        return model
    }

    private var visibleLocal: [StoredDocument] {
        var documents = library.filteredDownloads(query: query).filter { document in
            guard format == .all || format == documentFormat(document) else { return false }
            let id = identity(document)
            switch shelf {
            case .reading: return currentlyReading.contains(id)
            case .shortlist: return shortlist.contains(id)
            case .downloaded, .library: return true
            case .markups: return false
            }
        }
        if shelf == .reading {
            let dates = lastOpened
            documents.sort { (dates[identity($0)] ?? .distantPast) > (dates[identity($1)] ?? .distantPast) }
        }
        return documents
    }

    private var visibleRemote: [RemoteEntry] {
        guard shelf == .library || shelf == .shortlist else { return [] }
        let savedIDs = Set(library.downloads.compactMap(\.readerID))
        let entries = (format == .all || format == .pdf ? library.filteredPDFs(query: query).map { RemoteEntry(item: $0, format: .pdf) } : [])
            + (format == .all || format == .article ? library.filteredArticles(query: query).map { RemoteEntry(item: $0, format: .article) } : [])
            + (format == .all || format == .epub ? library.books.filter { matchesQuery($0) }.map { RemoteEntry(item: $0, format: .epub) } : [])
        return entries.filter { !savedIDs.contains($0.id) && (shelf != .shortlist || shortlist.contains($0.id)) }
    }

    private struct RemoteEntry: Identifiable {
        let item: ReaderPDF
        let format: Format
        var id: String { item.id }
    }

    private func matchesQuery(_ item: ReaderPDF) -> Bool {
        let value = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty || [item.title, item.author, item.summary].compactMap { $0 }.contains { $0.localizedStandardContains(value) }
    }

    @ViewBuilder private var shelfRows: some View {
        let local = visibleLocal
        let remote = visibleRemote
        if local.isEmpty && remote.isEmpty {
            emptyState(title: query.isEmpty ? shelf.rawValue : "No matches",
                message: query.isEmpty ? shelfHint : "Try another format, title, author, or description.")
            if query.isEmpty && shelf == .library && !library.connected {
                Button("Connect Reader") { showConnection = true }.buttonStyle(.borderedProminent).padding()
            }
            if query.isEmpty && shelf == .downloaded && format == .all {
                Button("Try a sample PDF") { reading.openSample() }.accessibilityIdentifier("sample").padding()
            }
        }
        ForEach(local) { localRow($0) }
        ForEach(remote) { remoteRow($0) }
    }

    private var shelfHint: String {
        switch shelf {
        case .downloaded: return "Download from Library or import a file to read offline."
        case .reading: return "Use a document’s menu to mark it as currently reading."
        case .shortlist: return "Bookmark a document to keep it here."
        case .library: return library.connected ? "Check Reader for more saved documents." : "Connect Reader to browse saved documents."
        case .markups: return ""
        }
    }

    private func identity(_ document: StoredDocument) -> String { document.readerID ?? document.id.uuidString }

    private func documentFormat(_ document: StoredDocument) -> Format {
        if document.format == .epub { return .epub }
        if document.format == .article { return .article }
        let source = reading.store.pdfURL(for: document).deletingLastPathComponent().appendingPathComponent("source.html")
        return FileManager.default.fileExists(atPath: source.path) ? .article : .pdf
    }

    private func usesDirectReader(_ document: StoredDocument) -> Bool {
        documentFormat(document) != .pdf && !FileManager.default.fileExists(atPath: reading.store.pdfURL(for: document).path)
    }

    private func open(_ document: StoredDocument) {
        searchFocused = false
        var dates = lastOpened
        dates[identity(document)] = Date()
        if let data = try? JSONEncoder().encode(dates) { lastOpenedData = data }
        reading.select(document)
    }

    private func bookmark(_ id: String) -> some View {
        let saved = shortlist.contains(id)
        return Button {
            var next = shortlist
            if saved { next.remove(id) } else { next.insert(id) }
            if let data = try? JSONEncoder().encode(next) { shortlistData = data }
        } label: {
            Image(systemName: saved ? "bookmark.fill" : "bookmark").frame(width: 42, height: 44)
        }.buttonStyle(.borderless).accessibilityLabel(saved ? "Remove from shortlist" : "Add to shortlist")
            .accessibilityIdentifier("shortlist-\(id)")
    }

    private func setReading(_ id: String, active: Bool) {
        var next = currentlyReading
        if active { next.insert(id) } else { next.remove(id) }
        if let data = try? JSONEncoder().encode(next) { currentlyReadingData = data }
    }

    private func localRow(_ document: StoredDocument) -> some View {
        let id = identity(document)
        let active = currentlyReading.contains(id)
        let kind = documentFormat(document)
        let remote = (library.pdfs + library.articles + library.books).first { $0.id == document.readerID }
        let date = lastOpened[id].map { "Opened " + $0.formatted(.relative(presentation: .named)) }
        return VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .center, spacing: 4) {
                Button { open(document) } label: {
                    rowMetadata(title: remote?.title ?? document.title, author: remote?.author ?? document.author,
                        summary: remote?.summary ?? document.summary, kind: kind,
                        status: [active ? "Reading" : nil, "Offline", date, readerDetails(remote)].compactMap { $0 }.joined(separator: " · "))
                        .contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityIdentifier("open-\(id)")
                bookmark(id)
                Menu {
                    Button(active ? "Stop tracking as currently reading" : "Mark as currently reading",
                        systemImage: active ? "checkmark" : "book") { setReading(id, active: !active) }
                    Button(usesDirectReader(document) ? "Open to review markup" : "Review markup", systemImage: "text.bubble") {
                        if usesDirectReader(document) { open(document) }
                        else { searchFocused = false; reviewItemID = nil; reviewDocument = document }
                    }
                    if FileManager.default.fileExists(atPath: reading.store.pdfURL(for: document).path),
                       let url = try? reading.store.workingPDFURL(for: document) { ShareLink("Export annotated PDF", item: url) }
                    if let url = readerLink(document.readerURL) { Link("Open in Reader", destination: url) }
                    Button("Remove download…", systemImage: "trash", role: .destructive) { removing = document }
                } label: { Image(systemName: "ellipsis").frame(width: 42, height: 44) }
                    .accessibilityLabel("Actions for \(remote?.title ?? document.title)").accessibilityIdentifier("actions-\(id)")
            }
            if let warning = document.preparationWarning {
                Text(warning).font(.caption).foregroundStyle(.secondary)
            }
        }.padding(.horizontal, 12).padding(.vertical, 6).background(.background)
    }

    private func remoteRow(_ entry: RemoteEntry) -> some View {
        let item = entry.item
        let kind = entry.format
        return VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .center, spacing: 4) {
                if kind == .pdf {
                    rowMetadata(title: item.title, author: item.author, summary: item.summary, kind: kind, status: readerDetails(item))
                } else {
                    Button {
                        Task { await retrieve(entry, thenOpen: true) }
                    } label: {
                        rowMetadata(title: item.title, author: item.author, summary: item.summary, kind: kind, status: readerDetails(item))
                            .contentShape(Rectangle())
                    }.buttonStyle(.plain).disabled(library.activeDownloadID != nil)
                        .accessibilityIdentifier("read-\(item.id)")
                }
                bookmark(item.id)
                if library.activeDownloadID == item.id {
                    ProgressView().frame(minWidth: 44, minHeight: 44)
                } else if kind == .article || item.canDownload {
                    Button(library.removedDocument(for: item) != nil ? "Restore" : library.downloadErrorID == item.id ? "Retry" : "Download") {
                        Task { await retrieve(entry, thenOpen: false) }
                    }.buttonStyle(.bordered).disabled(library.activeDownloadID != nil)
                        .accessibilityIdentifier(kind == .pdf ? "download-\(item.id)" : "prepare-\(item.id)")
                } else {
                    Button("Open in Reader") { unavailablePDF = item }.buttonStyle(.bordered)
                        .accessibilityIdentifier("unavailable-\(item.id)")
                }
            }
            if library.activeDownloadID == item.id {
                if kind == .pdf { downloadProgress }
                else { elapsed(from: library.downloadStarted, hint: library.articlePhase) }
            }
            if library.downloadErrorID == item.id, let error = library.downloadError {
                Text(error).font(.caption).foregroundStyle(.secondary)
                if let url = readerLink(item.readerURL) { Link("Open in Reader", destination: url).font(.caption) }
            }
        }.padding(.horizontal, 12).padding(.vertical, 6).background(.background)
    }

    private func retrieve(_ entry: RemoteEntry, thenOpen: Bool) async {
        let document: StoredDocument?
        switch entry.format {
        case .pdf: document = await library.download(entry.item)
        case .article: document = await library.prepareArticleForDirectReading(entry.item)
        case .epub: document = await library.prepareBook(entry.item)
        case .all: return
        }
        if let document {
            status = "Downloaded and ready to read."
            backup.requestBackup(store: reading.store)
            if thenOpen { open(document) }
        }
    }

    private func readerDetails(_ item: ReaderPDF?) -> String? {
        guard let item else { return nil }
        let time = nonempty(item.readingTime)
        let progress = item.readingProgress.flatMap { fraction in
            (fraction > 0 && fraction <= 1) ? "Reader " + fraction.formatted(.percent.precision(.fractionLength(0))) : nil
        }
        return nonempty([time, progress].compactMap { $0 }.joined(separator: " · "))
    }

    private func rowMetadata(title: String?, author: String?, summary: String?, kind: Format, status: String?) -> some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: kind == .epub ? "book.closed" : kind == .article ? "text.alignleft" : "doc.richtext")
                .font(.subheadline).foregroundStyle(Color.accentColor)
                .frame(width: 30, height: 32)
                .background(Color.accentColor.opacity(0.07), in: RoundedRectangle(cornerRadius: 5))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(nonempty(title) ?? "Untitled").font(.system(.headline, design: .serif)).foregroundStyle(.primary).lineLimit(2)
                Text([nonempty(author), kind == .epub ? "ePub" : kind == .article ? "Article" : "PDF", status]
                    .compactMap { $0 }.joined(separator: " · "))
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                if let summary = nonempty(summary) {
                    Text(summary).font(.footnote).foregroundStyle(.secondary).lineLimit(1)
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
    }
    private func emptyState(title: String, message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "doc.richtext").font(.system(size: 32)).foregroundStyle(.secondary)
            Text(title).font(.system(size: 25, design: .serif))
            Text(message).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }.padding(42).frame(maxWidth: .infinity).background(.background)
    }
    private var downloadProgress: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let total = library.expectedBytes, total > 0 {
                ProgressView(value: min(Double(library.receivedBytes), Double(total)), total: Double(total))
            }
            elapsed(from: library.downloadStarted, hint: library.receivedBytes > 0 ? "\(ByteCountFormatter.string(fromByteCount: library.receivedBytes, countStyle: .file)) received" : "Downloading your PDF · Large files can take a little longer.")
        }.accessibilityIdentifier("download-progress")
    }
    private func elapsed(from start: Date, hint: String) -> some View {
        TimelineView(.periodic(from: start, by: 1)) { context in
            Text("\(max(0, Int(context.date.timeIntervalSince(start))))s · \(hint)").font(.caption).foregroundStyle(.secondary)
        }
    }
    private var importProgress: some View {
        VStack(spacing: 12) { ProgressView(); Text("Importing your document"); elapsed(from: reading.importStarted, hint: "Large files can take a little longer.") }
            .padding(30).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
    }
    private var connectionSheet: some View {
        ReaderConnectionView(library: library).presentationDetents([.medium, .large])
    }
    private func unavailableSheet(_ pdf: ReaderPDF) -> some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 20) {
                Text(nonempty(pdf.title) ?? "PDF original unavailable").font(.system(size: 26, design: .serif))
                Text("Reader hasn’t provided a download link for this PDF.")
                Text("The original source may be a file on another device, a web page, or a link that is no longer accessible. Reader’s API does not report the reason for this document.").foregroundStyle(.secondary)
                if let url = readerLink(pdf.readerURL) { Link("Open in Reader", destination: url).buttonStyle(.borderedProminent) }
                Text("If you can export the PDF from Reader, use Import PDF to keep a copy here.").font(.subheadline).foregroundStyle(.secondary)
                Spacer()
            }.padding(28).navigationTitle("PDF source").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { unavailablePDF = nil } } }
        }.presentationDetents([.medium, .large])
    }
    private func nonempty(_ value: String?) -> String? {
        guard let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return value
    }
    private func readerLink(_ url: URL?) -> URL? { url?.scheme == "https" ? url : nil }
    private var readingErrorPresented: Binding<Bool> {
        Binding(get: { reading.error != nil }, set: { if !$0 { reading.error = nil } })
    }
}

private struct ReaderConnectionView: View {
    @ObservedObject var library: ReaderLibraryModel
    @Environment(\.dismiss) private var dismiss
    @State private var token = ""
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(library.connected ? "Reader is connected" : "Connect Reader").font(.system(size: 25, design: .serif))
                    Text("Your library refreshes titles, authors, and descriptions. PDFs download when you choose.").foregroundStyle(.secondary)
                }
                Section(library.connected ? "Replace access token" : "Access token") {
                    SecureField("Reader access token", text: $token).accessibilityIdentifier("reader-token")
                        .textInputAutocapitalization(.never).autocorrectionDisabled().textContentType(.password)
                    Link("Get your Reader token", destination: URL(string: "https://readwise.io/access_token")!)
                    Button(library.isConnecting ? "Connecting…" : "Connect and refresh") {
                        Task { if await library.connect(token: token) { token = ""; dismiss() } }
                    }.accessibilityIdentifier("connect-reader").disabled(token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || library.isRefreshing)
                }
                if library.isConnecting {
                    Section {
                        ProgressView()
                        TimelineView(.periodic(from: library.refreshStarted, by: 1)) { context in
                            Text("Refreshing your library · \(library.receivedCount) PDFs · \(max(0, Int(context.date.timeIntervalSince(library.refreshStarted))))s")
                        }
                    }
                }
                if let error = library.connectionError { Section { Text(error).foregroundStyle(.secondary) } }
                Section { Text("Downloaded PDFs and markup stay on this iPad even when Reader is unavailable.").font(.footnote).foregroundStyle(.secondary) }
            }.navigationTitle("Reader").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { token = ""; dismiss() }.disabled(library.isConnecting) } }
                .interactiveDismissDisabled(library.isConnecting)
        }
    }
}
