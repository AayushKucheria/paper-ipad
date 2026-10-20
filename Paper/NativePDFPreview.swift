import SwiftUI
import QuickLook
import OSLog

struct NativePDFPreview: UIViewControllerRepresentable {
    let document: StoredDocument
    let url: URL
    let store: DocumentStore
    let onSave: () -> Void
    let onError: (String) -> Void
    let onClose: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeUIViewController(context: Context) -> Presenter {
        let preview = QLPreviewController()
        preview.dataSource = context.coordinator
        preview.delegate = context.coordinator
        preview.modalPresentationStyle = .fullScreen
        preview.overrideUserInterfaceStyle = .light
        return Presenter(preview: preview)
    }
    func updateUIViewController(_ controller: Presenter, context: Context) {}

    // Present Quick Look modally so it owns its navigation and Markup controls.
    final class Presenter: UIViewController {
        let preview: QLPreviewController
        private var didPresent = false
        init(preview: QLPreviewController) { self.preview = preview; super.init(nibName: nil, bundle: nil) }
        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
        override func viewDidLoad() { super.viewDidLoad(); view.backgroundColor = .systemBackground }
        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            guard !didPresent else { return }
            didPresent = true
            present(preview, animated: false)
        }
    }

    final class Item: NSObject, QLPreviewItem {
        let previewItemURL: URL?
        let previewItemTitle: String?
        init(url: URL, title: String) { previewItemURL = url; previewItemTitle = title }
    }
    final class Coordinator: NSObject, QLPreviewControllerDataSource, QLPreviewControllerDelegate {
        let parent: NativePDFPreview
        let item: Item
        let log = Logger(subsystem: "com.aayush.paper.reader", category: "Markup")
        init(_ parent: NativePDFPreview) {
            self.parent = parent
            item = Item(url: parent.url, title: parent.document.title)
        }
        func numberOfPreviewItems(in controller: QLPreviewController) -> Int { 1 }
        func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem { item }
        func previewController(_ controller: QLPreviewController, editingModeFor previewItem: QLPreviewItem) -> QLPreviewItemEditingMode { .updateContents }
        func previewController(_ controller: QLPreviewController, didUpdateContentsOf previewItem: QLPreviewItem) {
            log.info("native markup saved elapsed=0")
            parent.onSave()
        }
        func previewController(_ controller: QLPreviewController, didSaveEditedCopyOf previewItem: QLPreviewItem, at modifiedContentsURL: URL) {
            let start = Date()
            log.info("save edited copy started elapsed=0")
            do {
                try parent.store.saveEditedCopy(at: modifiedContentsURL, document: parent.document)
                log.info("save edited copy completed elapsed=\(Date().timeIntervalSince(start))")
                parent.onSave()
            } catch {
                log.error("save edited copy failed elapsed=\(Date().timeIntervalSince(start))")
                parent.onError("Your edited PDF couldn’t be saved. Use Share in the preview to keep a copy. \(error.localizedDescription)")
            }
        }
        func previewControllerDidDismiss(_ controller: QLPreviewController) { parent.onClose() }
    }
}
