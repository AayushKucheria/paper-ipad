import Foundation
import PDFKit

struct StoredDocument: Codable, Identifiable, Equatable {
    let id: UUID
    let title: String
}

enum LibraryError: LocalizedError {
    case invalidPDF
    var errorDescription: String? { "This file could not be opened as a PDF. Choose an unlocked PDF and try again." }
}

struct DocumentStore {
    let root: URL
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
        return try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
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
