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
    @State private var downloaded = false
    @State private var query = ""
    @State private var showImporter = false
    @State private var showConnection = false
    @State private var unavailablePDF: ReaderPDF?
    @State private var status = "Your downloaded PDFs and markup stay on this iPad."
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
                VStack(alignment: .leading, spacing: 14) {
                    Text(downloaded ? "Downloaded" : "Your Reader library")
                        .font(.system(size: 34, design: .serif)).accessibilityAddTraits(.isHeader)
                    Text(downloaded ? "Ready to read offline, with your markup kept on this iPad." : "Browse your PDFs. Download the ones you want to read.")
                        .font(.subheadline).foregroundStyle(.secondary)
                    HStack(spacing: 8) {
                        tab("Library", selected: !downloaded, id: "library-tab") { downloaded = false }
                        tab("Downloaded", selected: downloaded, id: "downloaded-tab") { downloaded = true }
                        Spacer()
                        Text("\(shownPDFCount) \(shownPDFCount == 1 ? "PDF" : "PDFs")")
                            .font(.caption).foregroundStyle(.secondary).accessibilityIdentifier("pdf-count")
                    }.padding(.top, 6)
                    HStack {
                        Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                        TextField("Search title, author, or description", text: $query)
                            .focused($searchFocused)
                            .accessibilityIdentifier("pdf-search")
                            .textInputAutocapitalization(.never).autocorrectionDisabled()
                        if !query.isEmpty { Button { query = "" } label: { Image(systemName: "xmark.circle.fill") }.accessibilityLabel("Clear search") }
                    }.padding(12).background(.background, in: RoundedRectangle(cornerRadius: 12))
                    if library.isRefreshing {
                        HStack(spacing: 12) {
                            ProgressView()
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Checking for updated PDFs").font(.subheadline)
                                elapsed(from: library.refreshStarted, hint: "\(library.receivedCount) found · Large libraries can take a minute.")
                            }
                        }.accessibilityIdentifier("refresh-progress")
                    } else if !downloaded, library.connected {
                        HStack {
                            Button("Check for updates", systemImage: "arrow.clockwise") { Task { await library.refresh() } }
                            Menu { Button("Refresh entire catalog") { Task { await library.refresh(full: true) } } } label: { Image(systemName:"ellipsis") }.accessibilityLabel("Refresh options")
                                .font(.subheadline).accessibilityIdentifier("refresh-library")
                            Spacer()
                            if let date = library.lastSynced {
                                Text("Updated \(date.formatted(date: .omitted, time: .shortened))").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    if let error = library.error {
                        HStack(alignment: .top) {
                            Text(error).font(.subheadline).foregroundStyle(.secondary)
                            Spacer()
                            Button("Retry") { Task { await library.refresh() } }.disabled(library.isRefreshing)
                        }.accessibilityIdentifier("library-error")
                    }
                }.padding(.horizontal, 26).padding(.vertical, 24)
                ScrollView {
                    LazyVStack(spacing: 1) {
                        if downloaded { downloadedRows } else { libraryRows }
                    }.background(Color(uiColor: .separator).opacity(0.15))
                        .clipShape(RoundedRectangle(cornerRadius: 14)).padding(.horizontal, 26).padding(.bottom, 24)
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
                        } label: { Image(systemName:"ellipsis.circle") }.accessibilityLabel("Library actions")
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Import PDF", systemImage: "folder") { showImporter = true }.disabled(reading.importing)
                    }
                }
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    Text(status).font(.caption).foregroundStyle(.secondary).padding(.vertical, 7)
                        .frame(maxWidth: .infinity).background(.regularMaterial)
                }
                .overlay { if reading.importing { importProgress } }
                .fileImporter(isPresented: $showImporter, allowedContentTypes: [.pdf]) { result in
                    switch result {
                    case .success(let url): reading.importPDF(url)
                    case .failure(let error): reading.error = error.localizedDescription
                    }
                }
                .fullScreenCover(item: $reviewDocument) { document in
                    ReviewView(model: ReviewModel(document:document,store:reading.store,readerCredentials:readerCredentials,aiCredentials:aiCredentials,readerBaseURL:readerBaseURL,anthropicEndpoint:analysisEndpoint))
                }
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
                } message: { Text("The PDF, markup, and review drafts can be restored from Recently Removed. Storage is freed only when you permanently delete them.") }
                .sheet(isPresented: $showConnection) { connectionSheet }
                .sheet(item: $unavailablePDF) { pdf in unavailableSheet(pdf) }
                .fullScreenCover(item: $reading.selected) { document in
                    if let url = reading.previewURL {
                        NativePDFPreview(document: document, url: url, store: reading.store,
                            onSave: { status = "Saved on this iPad" },
                            onError: { reading.error = $0 },
                            onClose: { reading.selected = nil; library.reloadDownloads() })
                            .ignoresSafeArea()
                            .alert("Couldn’t save your PDF", isPresented: readingErrorPresented) {
                                Button("OK") { reading.error = nil }
                            } message: { Text(reading.error ?? "") }
                    }
                }
                .alert("Couldn’t open your PDF", isPresented: readingErrorPresented) {
                    Button("OK") { reading.error = nil }
                } message: { Text(reading.error ?? "") }
                .onChange(of: reading.documents) { _, _ in library.reloadDownloads() }
                .task { await library.start() }
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
    private var shownPDFCount: Int { downloaded ? library.filteredDownloads(query:query).count : library.filteredPDFs(query:query).count }
    private func tab(_ title: String, selected: Bool, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { Text(title).font(.subheadline.weight(.medium)).padding(.horizontal, 16).padding(.vertical, 10)
            .foregroundStyle(selected ? Color.white : Color.accentColor)
            .background(selected ? Color.accentColor : Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 10))
        }.buttonStyle(.plain).accessibilityIdentifier(id).accessibilityAddTraits(selected ? .isSelected : [])
    }
    @ViewBuilder private var libraryRows: some View {
        let records = library.filteredPDFs(query: query)
        if records.isEmpty {
            emptyState(title: query.isEmpty ? (library.connected ? "Your PDF library" : "Connect your Reader library") : "No matching PDFs",
                message: query.isEmpty ? (library.connected ? "Refresh to look for PDFs saved in Reader." : "Bring your Reader PDFs here, then download the ones you want to read.") : "Try another title, author, or description.")
            if !library.connected && query.isEmpty {
                Button("Connect Reader") { showConnection = true }.buttonStyle(.borderedProminent).padding()
                Button("Try a sample PDF") { reading.openSample() }.accessibilityIdentifier("sample").padding(.bottom, 24)
            }
        } else {
            ForEach(records) { pdf in
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .top, spacing: 20) {
                        DocumentCover(local:library.localDocument(for:pdf),store:reading.store,remote:pdf.imageURL)
                        metadata(title: pdf.title, author: pdf.author, summary: pdf.summary)
                        Spacer(minLength: 0)
                        if let local = library.localDocument(for: pdf) {
                            Button("Open") { searchFocused=false;reading.select(local) }.buttonStyle(.bordered).accessibilityIdentifier("open-\(pdf.id)")
                        } else if library.activeDownloadID == pdf.id {
                            ProgressView().padding(12).accessibilityLabel("Downloading PDF")
                        } else if pdf.canDownload {
                            Button(library.removedDocument(for:pdf) != nil ? "Restore" : library.downloadErrorID == pdf.id ? "Retry" : "Download") {
                                Task { if let document = await library.download(pdf) { searchFocused=false;reading.select(document) } }
                            }.buttonStyle(.bordered).disabled(library.activeDownloadID != nil)
                                .accessibilityIdentifier("download-\(pdf.id)")
                        } else {
                            Button("Open in Reader") { unavailablePDF = pdf }.buttonStyle(.bordered)
                                .accessibilityIdentifier("unavailable-\(pdf.id)")
                        }
                    }
                    if library.activeDownloadID == pdf.id { downloadProgress }
                    if library.downloadErrorID == pdf.id, let error = library.downloadError {
                        Text(error).font(.caption).foregroundStyle(.secondary)
                        if let url = readerLink(pdf.readerURL) { Link("Open in Reader", destination: url).font(.caption) }
                    }
                }.padding(22).frame(maxWidth: .infinity, alignment: .leading).background(.background)
            }
        }
    }
    @ViewBuilder private var downloadedRows: some View {
        let records = library.filteredDownloads(query: query)
        if records.isEmpty {
            emptyState(title: query.isEmpty ? "Keep a PDF here" : "No matching PDFs",
                message: query.isEmpty ? "Download a PDF from Library, or import one from Files. It will stay here with your markup." : "Try another title, author, or description.")
        } else {
            ForEach(records) { document in
                let remote = library.pdfs.first { $0.id == document.readerID }
                HStack(alignment: .top, spacing: 20) {
                    DocumentCover(local:document,store:reading.store,remote:remote?.imageURL)
                    metadata(title: remote?.title ?? document.title, author: remote?.author ?? document.author, summary: remote?.summary ?? document.summary)
                    Spacer(minLength: 0)
                    Button("Open") { searchFocused=false;reading.select(document) }.buttonStyle(.bordered)
                        .accessibilityIdentifier("open-\(document.readerID ?? document.id.uuidString)")
                    Menu {
                        Button("Review markup",systemImage:"text.bubble") { searchFocused=false;reviewDocument=document }
                        if let url=try? reading.store.workingPDFURL(for:document) { ShareLink("Export annotated PDF",item:url) }
                        Button("Remove download…",systemImage:"trash",role:.destructive) { removing=document }
                    } label: { Image(systemName:"ellipsis").padding(10) }.accessibilityLabel("Actions for \(remote?.title ?? document.title)").accessibilityIdentifier("actions-\(document.readerID ?? document.id.uuidString)")
                }.padding(22).frame(maxWidth: .infinity, alignment: .leading).background(.background)
            }
        }
    }
    private func metadata(title: String?, author: String?, summary: String?) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(nonempty(title) ?? "Untitled PDF").font(.system(size: 21, design: .serif)).foregroundStyle(.primary).lineLimit(4)
            Text(nonempty(author) ?? "Author unavailable").font(.subheadline).foregroundStyle(.secondary)
            Text(nonempty(summary) ?? "No description provided.").font(.subheadline).foregroundStyle(.secondary).lineLimit(3)
        }.frame(maxWidth: .infinity, alignment: .leading)
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
        VStack(spacing: 12) { ProgressView(); Text("Opening your PDF"); elapsed(from: reading.importStarted, hint: "Large PDFs can take a little longer.") }
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
