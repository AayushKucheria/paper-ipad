import SwiftUI
import UniformTypeIdentifiers

@main struct PaperApp: App {
    var body: some Scene { WindowGroup { ReadingView() } }
}

struct ReadingView: View {
    @StateObject private var model = ReadingModel()
    @State private var showImporter = false
    @State private var status = "Saved on this iPad"
    var body: some View {
        NavigationStack {
            Group {
                if model.documents.isEmpty {
                    VStack(alignment: .leading, spacing: 24) {
                        Image(systemName: "doc.richtext").font(.system(size: 42)).foregroundStyle(.secondary)
                        Text("Bring a PDF.\nMake room for your thoughts.").font(.system(size: 36, design: .serif))
                        Text("Read, write, and return to your notes.\nYour PDFs stay on this iPad.").foregroundStyle(.secondary)
                        Button("Choose PDF", systemImage: "folder") { showImporter = true }.buttonStyle(.borderedProminent)
                        Button("Try a sample PDF") { model.openSample() }.accessibilityIdentifier("sample")
                    }.frame(maxWidth: 520, alignment: .leading).padding(32).frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color(uiColor: .systemGroupedBackground))
                } else {
                    List {
                        Section {
                            ForEach(model.documents) { doc in
                                Button { model.select(doc) } label: {
                                    Label(doc.title, systemImage: "doc.richtext").padding(.vertical, 10)
                                }.accessibilityIdentifier("document-\(doc.id)")
                            }
                        } header: { Text("On this iPad") } footer: {
                            Text("Open a PDF and tap Markup to write. Finish with Done to save your changes. An untouched original is kept separately.")
                        }
                    }
                }
            }
            .navigationTitle("Paper")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Open PDF", systemImage: "folder") { showImporter = true }
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                Text(status).font(.caption).foregroundStyle(.secondary).padding(.vertical, 5)
                    .frame(maxWidth: .infinity).background(.regularMaterial)
            }
            .overlay {
                if model.importing {
                    VStack(spacing: 12) {
                        ProgressView()
                        Text("Opening your PDF")
                        TimelineView(.periodic(from: model.importStarted, by: 1)) { context in
                            Text("\(Int(context.date.timeIntervalSince(model.importStarted)))s · Large PDFs can take a little longer.").font(.caption).foregroundStyle(.secondary)
                        }
                    }.padding(32).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
                }
            }
            .disabled(model.importing)
            .fileImporter(isPresented: $showImporter, allowedContentTypes: [.pdf]) { result in
                switch result {
                case .success(let url): model.importPDF(url)
                case .failure(let error): model.error = error.localizedDescription
                }
            }
            .fullScreenCover(item: $model.selected) { doc in
                if let url = model.previewURL {
                    NativePDFPreview(document: doc, url: url, store: model.store,
                                     onSave: { status = "Saved on this iPad" },
                                     onError: { model.error = $0 },
                                     onClose: { model.selected = nil })
                        .ignoresSafeArea()
                        .alert("Couldn’t save your PDF", isPresented: errorPresented) {
                            Button("OK") { model.error = nil }
                        } message: { Text(model.error ?? "") }
                }
            }
            .alert("Something needs attention", isPresented: errorPresented) {
                Button("OK") { model.error = nil }
            } message: { Text(model.error ?? "") }
        }.tint(Color(red: 0.20, green: 0.31, blue: 0.25))
    }
    private var errorPresented: Binding<Bool> {
        Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })
    }
}
