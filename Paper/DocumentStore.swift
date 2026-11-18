import Foundation
import PDFKit

struct StoredDocument: Codable, Identifiable, Equatable {
    enum Format: String, Codable { case article, epub }

    let id: UUID
    let title: String
    var readerID: String? = nil
    var author: String? = nil
    var summary: String? = nil
    var readerURL: URL? = nil
    var sourceURL: URL? = nil
    var preparationWarning: String? = nil
    var format: Format? = nil
}

enum LibraryError: LocalizedError {
    case invalidPDF
    var errorDescription: String? { "This file could not be opened as a PDF. Choose an unlocked PDF and try again." }
}

struct DocumentStore {
    let root: URL
    func importReaderPDF(at source: URL, metadata: ReaderPDF) throws -> StoredDocument {
        // Reader refreshes must never replace locally annotated documents.
        if let retained = try documents().first(where: { $0.readerID == metadata.id }) { return retained }
        var coordinationError: NSError?
        var result: Result<StoredDocument, Error>?
        NSFileCoordinator().coordinate(readingItemAt: source, options: [], error: &coordinationError) { readable in
            result = Result {
                let data = try Data(contentsOf: readable)
                guard let pdf = PDFDocument(data: data), !pdf.isLocked, pdf.pageCount > 0 else { throw LibraryError.invalidPDF }
                let title = metadata.title?.trimmingCharacters(in: .whitespacesAndNewlines)
                let document = StoredDocument(
                    id: UUID(), title: title.flatMap { $0.isEmpty ? nil : $0 } ?? "Untitled PDF",
                    readerID: metadata.id, author: metadata.author, summary: metadata.summary,
                    readerURL: metadata.readerURL, sourceURL: metadata.sourceURL
                )
                let folder = pdfURL(for: document).deletingLastPathComponent()
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                do {
                    try data.write(to: pdfURL(for: document), options: .atomic)
                    // Publish metadata last: incomplete downloads never become library entries.
                    try JSONEncoder().encode(document).write(to: folder.appendingPathComponent("document.json"), options: .atomic)
                } catch {
                    try? FileManager.default.removeItem(at: folder)
                    throw error
                }
                return document
            }
        }
        if let coordinationError { throw coordinationError }
        guard let result else { throw CocoaError(.fileReadUnknown) }
        return try result.get()
    }
    func importPDF(at source: URL) throws -> StoredDocument {
        // Coordinate reads from Files providers before copying into our own storage.
        var coordinationError: NSError?
        var result: Result<StoredDocument, Error>?
        NSFileCoordinator().coordinate(readingItemAt: source, options: [], error: &coordinationError) { readable in
            result = Result {
                guard let pdf = PDFDocument(url: readable), !pdf.isLocked, pdf.pageCount > 0 else { throw LibraryError.invalidPDF }
                let doc = StoredDocument(id: UUID(), title: source.deletingPathExtension().lastPathComponent)
                let folder = pdfURL(for: doc).deletingLastPathComponent()
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                do {
                    try FileManager.default.copyItem(at: readable, to: pdfURL(for: doc))
                    try JSONEncoder().encode(doc).write(to: folder.appendingPathComponent("document.json"), options: .atomic)
                } catch {
                    try? FileManager.default.removeItem(at: folder)
                    throw error
                }
                return doc
            }
        }
        if let coordinationError { throw coordinationError }
        guard let result else { throw CocoaError(.fileReadUnknown) }
        return try result.get()
    }
    func documents() throws -> [StoredDocument] {
        guard FileManager.default.fileExists(atPath: root.path) else { return [] }
        return try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])
            .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
            .filter { FileManager.default.fileExists(atPath: $0.appendingPathComponent("document.json").path) }
            .map { try JSONDecoder().decode(StoredDocument.self, from: Data(contentsOf: $0.appendingPathComponent("document.json"))) }
            .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }
    func workingPDFURL(for document: StoredDocument) throws -> URL {
        let url = pdfURL(for: document).deletingLastPathComponent().appendingPathComponent("reading.pdf")
        if !FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.copyItem(at: pdfURL(for: document), to: url)
        }
        guard let pdf = PDFDocument(url: url), !pdf.isLocked, pdf.pageCount > 0 else { throw LibraryError.invalidPDF }
        return url
    }
    func saveEditedCopy(at url: URL, document: StoredDocument) throws {
        let data = try Data(contentsOf: url)
        guard let pdf = PDFDocument(data: data), !pdf.isLocked, pdf.pageCount > 0 else { throw LibraryError.invalidPDF }
        try data.write(to: workingPDFURL(for: document), options: .atomic)
    }
    func pdfURL(for document: StoredDocument) -> URL {
        root.appendingPathComponent(document.id.uuidString).appendingPathComponent("source.pdf")
    }
}


extension DocumentStore {
    private var removedRoot: URL { root.deletingLastPathComponent().appendingPathComponent("RecentlyRemoved", isDirectory: true) }
    func removedDocuments() throws -> [StoredDocument] { try DocumentStore(root: removedRoot).documents() }
    func removeDownload(_ document: StoredDocument) throws {
        try FileManager.default.createDirectory(at: removedRoot, withIntermediateDirectories: true)
        try FileManager.default.moveItem(at: pdfURL(for: document).deletingLastPathComponent(),
            to: removedRoot.appendingPathComponent(document.id.uuidString))
    }
    func restoreDownload(_ document: StoredDocument) throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try FileManager.default.moveItem(at: removedRoot.appendingPathComponent(document.id.uuidString),
            to: pdfURL(for: document).deletingLastPathComponent())
    }
    func permanentlyDelete(_ document: StoredDocument) throws {
        try FileManager.default.removeItem(at: removedRoot.appendingPathComponent(document.id.uuidString))
    }
    func reviewURL(for document: StoredDocument) -> URL { pdfURL(for: document).deletingLastPathComponent().appendingPathComponent("review.json") }
}

extension DocumentStore {
    func directReadingSections(for document: StoredDocument) throws -> [DirectReadingSection] {
        let folder = pdfURL(for: document).deletingLastPathComponent()
        if document.format == .epub {
            let publication = try JSONDecoder().decode(EPUBPublication.self, from: Data(contentsOf: folder.appendingPathComponent("publication.json")))
            let resources = folder.appendingPathComponent("publication", isDirectory: true)
            return publication.chapters.map { chapter in
                DirectReadingSection(id: chapter.path, title: chapter.title, fileURL: resources.appendingPathComponent(chapter.path),
                                     readAccessURL: resources, baseURL: nil)
            }
        }
        let reading = folder.appendingPathComponent("reading.html")
        if FileManager.default.fileExists(atPath: reading.path) {
            return [DirectReadingSection(id: "article", title: document.title, fileURL: reading,
                                         readAccessURL: folder, baseURL: nil)]
        }
        let source = folder.appendingPathComponent("source.html")
        if FileManager.default.fileExists(atPath: source.path) {
            return [DirectReadingSection(id: "article", title: document.title, fileURL: source,
                                         readAccessURL: folder, baseURL: document.sourceURL)]
        }
        return []
    }

    func importEPUB(at source: URL, metadata: ReaderPDF? = nil) throws -> StoredDocument {
        if let metadata, let retained = try documents().first(where: { $0.readerID == metadata.id }) { return retained }
        var coordinationError: NSError?
        var result: Result<StoredDocument, Error>?
        NSFileCoordinator().coordinate(readingItemAt: source, options: [], error: &coordinationError) { readable in
            result = Result {
                let size = try readable.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                guard size <= EPUBArchive.maxArchiveBytes else { throw EPUBError.sizeLimit }
                let original = try Data(contentsOf: readable, options: .mappedIfSafe)
                let id = UUID()
                let folder = root.appendingPathComponent(id.uuidString, isDirectory: true)
                let resources = folder.appendingPathComponent("publication", isDirectory: true)
                try FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)
                do {
                    try EPUBArchive.extract(original, to: resources)
                    let publication = try EPUBPublication.open(in: resources)
                    let title = metadata?.title?.trimmingCharacters(in: .whitespacesAndNewlines)
                    let document = StoredDocument(id: id,
                        title: title.flatMap { $0.isEmpty ? nil : $0 } ?? publication.title ?? source.deletingPathExtension().lastPathComponent,
                        readerID: metadata?.id, author: metadata?.author ?? publication.author, summary: metadata?.summary,
                        readerURL: metadata?.readerURL, sourceURL: metadata?.sourceURL, format: .epub)
                    try original.write(to: folder.appendingPathComponent("source.epub"), options: .atomic)
                    try JSONEncoder().encode(publication).write(to: folder.appendingPathComponent("publication.json"), options: .atomic)
                    try JSONEncoder().encode(document).write(to: folder.appendingPathComponent("document.json"), options: .atomic)
                    return document
                } catch {
                    try? FileManager.default.removeItem(at: folder)
                    throw error
                }
            }
        }
        if let coordinationError { throw coordinationError }
        guard let result else { throw CocoaError(.fileReadUnknown) }
        return try result.get()
    }

    func importDirectArticle(metadata: ReaderPDF, originalHTML: String, readingHTML: String, sourceText: String, missingFigures: Int) throws -> StoredDocument {
        if let retained = try documents().first(where: { $0.readerID == metadata.id }) { return retained }
        let title = metadata.title?.trimmingCharacters(in: .whitespacesAndNewlines)
        let warning = missingFigures == 0 ? nil : "\(missingFigures) \(missingFigures == 1 ? "figure was" : "figures were") unavailable. Their positions are marked in the article."
        let document = StoredDocument(id: UUID(), title: title.flatMap { $0.isEmpty ? nil : $0 } ?? "Untitled article",
                                      readerID: metadata.id, author: metadata.author, summary: metadata.summary,
                                      readerURL: metadata.readerURL, sourceURL: metadata.sourceURL,
                                      preparationWarning: warning, format: .article)
        let folder = pdfURL(for: document).deletingLastPathComponent()
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        do {
            try Data(originalHTML.utf8).write(to: folder.appendingPathComponent("source.html"), options: .atomic)
            try Data(readingHTML.utf8).write(to: folder.appendingPathComponent("reading.html"), options: .atomic)
            try Data(sourceText.utf8).write(to: folder.appendingPathComponent("source.txt"), options: .atomic)
            try JSONEncoder().encode(document).write(to: folder.appendingPathComponent("document.json"), options: .atomic)
            return document
        } catch {
            try? FileManager.default.removeItem(at: folder)
            throw error
        }
    }
}
