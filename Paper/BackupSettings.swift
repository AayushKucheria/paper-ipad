import SwiftUI
import UniformTypeIdentifiers
import OSLog

@MainActor final class BackupCoordinator: ObservableObject {
    static let shared = BackupCoordinator()
    @Published private(set) var isBackingUp = false
    @Published private(set) var started = Date()
    @Published private(set) var phase = ""
    private var activeOperation: UUID?
    @Published private(set) var errorMessage: String?
    @Published private(set) var destinationName: String?
    @Published private(set) var lastBackup: Date?
    private let defaults = UserDefaults.standard
    private var queuedStore: DocumentStore?
    private let bookmarkKey = "backup.folder.bookmark"

    private init() {
        destinationName = defaults.string(forKey: "backup.folder.name")
        lastBackup = defaults.object(forKey: "backup.lastSuccess") as? Date
    }
    func chooseFolder(_ url: URL, store: DocumentStore) {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        do {
            let bookmark = try url.bookmarkData(options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil)
            defaults.set(bookmark, forKey: bookmarkKey)
            destinationName = url.lastPathComponent
            defaults.set(destinationName, forKey: "backup.folder.name")
            lastBackup = nil
            defaults.removeObject(forKey: "backup.lastSuccess")
            requestBackup(store: store)
        } catch { errorMessage = "Folder access could not be saved. Choose the folder again. \(error.localizedDescription)" }
    }
    func requestBackup(store: DocumentStore) {
        guard let bookmark = defaults.data(forKey: bookmarkKey) else { return }
        guard !isBackingUp else { queuedStore = store; return }
        isBackingUp = true
        errorMessage = nil
        started = Date()
        phase = "Opening your backup folder"
        let operationID = UUID()
        activeOperation = operationID
        let operation = operationID.uuidString
        let operationStarted = started
        let log = Logger(subsystem: "com.aayush.paper.reader", category: "Backup")
        log.info("backup_start operation=\(operation, privacy: .public) elapsed=0")
        Task {
            do {
                let result = try await Task.detached(priority: .utility) { () -> (Date, Data?) in
                    var stale = false
                    let folder = try URL(resolvingBookmarkData: bookmark, options: [], relativeTo: nil, bookmarkDataIsStale: &stale)
                    let accessing = folder.startAccessingSecurityScopedResource()
                    defer { if accessing { folder.stopAccessingSecurityScopedResource() } }
                    var coordinationError: NSError?
                    var operation: Result<URL, Error>?
                    NSFileCoordinator().coordinate(readingItemAt: store.root.deletingLastPathComponent(), options: [],
                                                   writingItemAt: folder, options: .forMerging, error: &coordinationError) { source, destination in
                        operation = Result {
                            try BackupSnapshot().create(documentsRoot: source, destination: destination, operationID: operationID) { phase in
                                Task { @MainActor in
                                    if self.activeOperation == operationID && self.isBackingUp { self.phase = phase }
                                }
                            }
                        }
                    }
                    if let coordinationError { throw coordinationError }
                    guard let operation else { throw CocoaError(.fileWriteUnknown) }
                    _ = try operation.get()
                    let renewed = stale ? try folder.bookmarkData(options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil) : nil
                    return (Date(), renewed)
                }.value
                phase = "Backup verified"
                log.info("backup_complete operation=\(operation, privacy: .public) elapsed=\(Date().timeIntervalSince(operationStarted))")
                lastBackup = result.0
                defaults.set(result.0, forKey: "backup.lastSuccess")
                if let renewed = result.1 { defaults.set(renewed, forKey: bookmarkKey) }
            } catch {
                phase = "Backup needs attention"
                log.error("backup_failure operation=\(operation, privacy: .public) elapsed=\(Date().timeIntervalSince(operationStarted))")
                errorMessage = "Backup did not finish. Your local library and earlier backups are safe. \(error.localizedDescription)"
            }
            isBackingUp = false
            activeOperation = nil
            if let pending = queuedStore { queuedStore = nil; requestBackup(store: pending) }
        }
    }
}

struct BackupSettingsView: View {
    let store: DocumentStore
    @ObservedObject private var backup = BackupCoordinator.shared
    @Environment(\.dismiss) private var dismiss
    @State private var choosingFolder = false
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Label("Keep your handwriting safe", systemImage: "externaldrive.badge.checkmark")
                    Text("Save dated copies of your original PDFs, annotated PDFs, article pages and review notes to a folder in Files. Choose Dropbox, iCloud Drive or another provider you have enabled in Files.")
                }
                Section("Backup folder") {
                    if let name = backup.destinationName { LabeledContent("Folder", value: name) }
                    Button(backup.destinationName == nil ? "Choose backup folder" : "Change backup folder") { choosingFolder = true }
                    if let date = backup.lastBackup {
                        LabeledContent("Last verified copy") { Text(date, format: .dateTime.month().day().hour().minute()) }
                    } else { Text("No verified backup yet").foregroundStyle(.secondary) }
                    if backup.isBackingUp {
                        HStack(spacing: 12) {
                            ProgressView()
                            VStack(alignment: .leading, spacing: 5) {
                                Text(backup.phase).font(.subheadline)
                                TimelineView(.periodic(from: backup.started, by: 1)) { context in
                                    Text("\(max(0, Int(context.date.timeIntervalSince(backup.started))))s elapsed").font(.caption).foregroundStyle(.secondary)
                                }
                                Text("Keep Paper open until verification completes. Large libraries can take a few minutes.").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    if let error = backup.errorMessage { Text(error).foregroundStyle(.red) }
                    if backup.destinationName != nil {
                        Button("Back up now") { backup.requestBackup(store: store) }.disabled(backup.isBackingUp)
                    }
                }
                Section {
                    Text("After you choose a folder, Paper backs up when you save markup and return to the app. Keep Paper open until the copy is verified. Your cloud provider controls uploading; check its status in Files.")
                    Text("Each changed backup keeps a complete version. Earlier versions are retained, so the folder will grow. Paper never deletes your old backups automatically. API keys are excluded.")
                }
            }
            .navigationTitle("Backups")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .sheet(isPresented: $choosingFolder) {
                BackupFolderPicker { url in backup.chooseFolder(url, store: store) }
            }
        }
    }
}

private struct BackupFolderPicker: UIViewControllerRepresentable {
    let onChoose: (URL) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(onChoose: onChoose) }
    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.folder], asCopy: false)
        picker.delegate = context.coordinator
        picker.allowsMultipleSelection = false
        return picker
    }
    func updateUIViewController(_ controller: UIDocumentPickerViewController, context: Context) {}
    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onChoose: (URL) -> Void
        init(onChoose: @escaping (URL) -> Void) { self.onChoose = onChoose }
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            if let url = urls.first { onChoose(url) }
        }
    }
}
