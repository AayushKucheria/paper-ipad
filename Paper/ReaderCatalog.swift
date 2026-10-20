import Foundation

struct ReaderSnapshot: Codable, Equatable {
    let documents: [ReaderPDF]
    let syncedAt: Date
}

/// Catalog replacement never touches the independently retained document folders.
struct ReaderCatalog {
    let url: URL
    func load() throws -> ReaderSnapshot? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try JSONDecoder().decode(ReaderSnapshot.self, from: Data(contentsOf: url))
    }
    @discardableResult func save(_ documents: [ReaderPDF], syncedAt: Date) throws -> ReaderSnapshot {
        let snapshot = ReaderSnapshot(documents: documents, syncedAt: syncedAt)
        let data = try JSONEncoder().encode(snapshot)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
        return snapshot
    }
}
