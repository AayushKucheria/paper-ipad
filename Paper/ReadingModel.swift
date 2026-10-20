import SwiftUI
import PDFKit
import OSLog

@MainActor final class ReadingModel: ObservableObject {
    @Published var documents: [StoredDocument] = []
    @Published var selected: StoredDocument?
    var previewURL: URL?
    @Published var importing = false
    @Published var importStarted = Date()
    @Published var error: String?
    let store: DocumentStore
    private let log = Logger(subsystem: "com.aayush.paper.reader", category: "Import")
    init() {
        let root = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("Library", isDirectory: true)
        store = DocumentStore(root: root)
        do {
            documents = try store.documents()
            if let id = UserDefaults.standard.string(forKey: "lastDocument") {
                if let doc = documents.first(where: { $0.id.uuidString == id }) { select(doc) }
            }
        } catch { self.error = error.localizedDescription }
    }
    func select(_ document: StoredDocument) {
        do {
            previewURL = try store.workingPDFURL(for: document)
            selected = document
            UserDefaults.standard.set(document.id.uuidString, forKey: "lastDocument")
        } catch { self.error = error.localizedDescription }
    }
    func importPDF(_ url: URL) {
        guard !importing else { return }
        importing = true
        importStarted = Date()
        log.info("import started elapsed=0")
        let store = store
        Task {
            do {
                let document = try await Task.detached(priority: .userInitiated) {
                    let access = url.startAccessingSecurityScopedResource()
                    defer { if access { url.stopAccessingSecurityScopedResource() } }
                    return try store.importPDF(at: url)
                }.value
                documents = try store.documents()
                select(document)
                log.info("import completed elapsed=\(Date().timeIntervalSince(self.importStarted))")
            } catch {
                self.error = error.localizedDescription
                log.error("import failed elapsed=\(Date().timeIntervalSince(self.importStarted))")
            }
            importing = false
        }
    }
    func openSample() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("A page for your thoughts.pdf")
        do {
            let data = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 612, height: 792)).pdfData { context in
                for page in 1...2 {
                    context.beginPage()
                    let title = page == 1 ? "A page for your thoughts" : "Room to keep thinking"
                    (title as NSString).draw(in: CGRect(x: 60, y: 80, width: 492, height: 100), withAttributes: [.font: UIFont.systemFont(ofSize: 30, weight: .medium), .foregroundColor: UIColor.black])
                    let text = "This is a sample PDF for trying your Pencil. Circle a word, underline a sentence, or write in the space below.\n\nUse your fingers to scroll and zoom. Tap Markup to bring up Apple’s drawing tools. Finish with Done to save your changes.\n\nYour marks are saved on this iPad. Close the app and come back to find them here."
                    let style = NSMutableParagraphStyle(); style.lineSpacing = 8
                    (text as NSString).draw(in: CGRect(x: 60, y: 175, width: 492, height: 400), withAttributes: [.font: UIFont.systemFont(ofSize: 18), .foregroundColor: UIColor.darkGray, .paragraphStyle: style])
                    ("\(page) / 2" as NSString).draw(at: CGPoint(x: 285, y: 740), withAttributes: [.font: UIFont.systemFont(ofSize: 12), .foregroundColor: UIColor.gray])
                }
            }
            try data.write(to: url, options: .atomic)
            importPDF(url)
        } catch { self.error = error.localizedDescription }
    }
}
