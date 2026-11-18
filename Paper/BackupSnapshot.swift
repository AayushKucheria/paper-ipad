import Foundation
import CommonCrypto
import OSLog

/// A complete, independently restorable version. Nothing prunes previous versions.
struct BackupSnapshot {
    private struct Manifest: Codable {
        let version: Int
        let createdAt: Date
        let files: [String: String]
    }
    private let allowed = ["Library", "RecentlyRemoved", "reader-catalog.json", "reader-articles.json", "reader-books.json"]
    private let manager = FileManager.default

    func create(documentsRoot: URL, destination: URL, operationID: UUID = UUID(),
                progress: @Sendable (String) -> Void = { _ in }) throws -> URL {
        let log = Logger(subsystem: "com.aayush.paper.reader", category: "Backup")
        let started = Date()
        let operation = operationID.uuidString
        progress("Checking saved files")
        let base = destination.appendingPathComponent("Paper Backups", isDirectory: true)
        // Prevent backing up the backup if someone chooses Paper's own Documents folder.
        guard !["Library", "RecentlyRemoved"].contains(where: { base.standardizedFileURL.path.hasPrefix(documentsRoot.standardizedFileURL.appendingPathComponent($0).path + "/") }) else { throw BackupError.invalidFolder }
        try manager.createDirectory(at: base, withIntermediateDirectories: true)
        let files = try collectFiles(under: documentsRoot)
        log.info("backup_hash operation=\(operation, privacy: .public) files=\(files.count) elapsed=\(Date().timeIntervalSince(started))")
        let checksums = try Dictionary(uniqueKeysWithValues: files.map { ($0, try digest(documentsRoot.appendingPathComponent($0))) })
        // A verified existing copy also avoids writing an entire unchanged library again.
        let previous = try manager.contentsOfDirectory(at: base, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]).sorted { $0.lastPathComponent > $1.lastPathComponent }
        if let latest = previous.first, let manifest = try? readManifest(latest), manifest.files == checksums {
            progress("Verifying your existing backup")
            log.info("backup_verify operation=\(operation, privacy: .public) files=\(files.count) elapsed=\(Date().timeIntervalSince(started))")
            if (try? verify(snapshot: latest, manifest: manifest)) != nil { return latest }
        }
        let name = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-") + "-" + UUID().uuidString
        let staging = base.appendingPathComponent(".incomplete-" + UUID().uuidString, isDirectory: true)
        let complete = base.appendingPathComponent(name, isDirectory: true)
        try manager.createDirectory(at: staging, withIntermediateDirectories: true)
        do {
            log.info("backup_copy operation=\(operation, privacy: .public) files=\(files.count) elapsed=\(Date().timeIntervalSince(started))")
            for (index, path) in files.enumerated() {
                if index % 10 == 0 || index == files.count - 1 { progress("Copying file \(index + 1) of \(files.count)") }
                let target = staging.appendingPathComponent(path)
                try manager.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
                try manager.copyItem(at: documentsRoot.appendingPathComponent(path), to: target)
            }
            let manifest = Manifest(version: 1, createdAt: Date(), files: checksums)
            progress("Verifying the copied files")
            log.info("backup_verify operation=\(operation, privacy: .public) files=\(files.count) elapsed=\(Date().timeIntervalSince(started))")
            try verify(snapshot: staging, manifest: manifest)
            // An atomic native save during copying must not publish a mixed version.
            progress("Checking the library stayed unchanged")
            guard try collectFiles(under: documentsRoot) == files else { throw BackupError.sourceChanged }
            for path in files {
                guard try digest(documentsRoot.appendingPathComponent(path)) == checksums[path] else { throw BackupError.sourceChanged }
            }
            progress("Finishing your verified backup")
            try JSONEncoder().encode(manifest).write(to: staging.appendingPathComponent("manifest.json"), options: .atomic)
            try manager.moveItem(at: staging, to: complete)
            return complete
        } catch {
            try? manager.removeItem(at: staging)
            throw error
        }
    }

    /// Restores only to a new folder. Live libraries cannot be overwritten by this API.
    func restore(snapshot: URL, into destination: URL) throws {
        guard !manager.fileExists(atPath: destination.path) else { throw BackupError.destinationExists }
        let manifest = try readManifest(snapshot)
        try verify(snapshot: snapshot, manifest: manifest)
        let staging = destination.deletingLastPathComponent().appendingPathComponent(".restore-" + UUID().uuidString, isDirectory: true)
        try manager.createDirectory(at: staging, withIntermediateDirectories: true)
        do {
            for path in manifest.files.keys {
                let target = staging.appendingPathComponent(path)
                try manager.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
                try manager.copyItem(at: snapshot.appendingPathComponent(path), to: target)
            }
            try verify(snapshot: staging, manifest: manifest)
            try manager.moveItem(at: staging, to: destination)
        } catch {
            try? manager.removeItem(at: staging)
            throw error
        }
    }

    private func readManifest(_ snapshot: URL) throws -> Manifest {
        let manifest = try JSONDecoder().decode(Manifest.self, from: Data(contentsOf: snapshot.appendingPathComponent("manifest.json")))
        guard manifest.version == 1 else { throw BackupError.invalidManifest }
        return manifest
    }
    private func verify(snapshot: URL, manifest: Manifest) throws {
        for (path, checksum) in manifest.files {
            let pieces = path.split(separator: "/", omittingEmptySubsequences: false)
            guard let first = pieces.first, allowed.contains(String(first)),
                  !path.hasPrefix("/"), !pieces.contains(".."), !pieces.contains("."), !pieces.contains("") else { throw BackupError.invalidManifest }
            var cursor = snapshot
            for piece in pieces {
                cursor.appendPathComponent(String(piece))
                if try cursor.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink == true { throw BackupError.invalidManifest }
            }
            guard try digest(snapshot.appendingPathComponent(path)) == checksum else { throw BackupError.corruptedCopy }
        }
    }
    private func collectFiles(under root: URL) throws -> [String] {
        var files: [String] = []
        for name in allowed {
            let url = root.appendingPathComponent(name)
            guard manager.fileExists(atPath: url.path) else { continue }
            let values = try url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            guard values.isSymbolicLink != true else { throw BackupError.invalidFolder }
            if values.isDirectory == true {
                var enumerationError: Error?
                guard let enumerator = manager.enumerator(at: url, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey], options: [], errorHandler: { _, error in enumerationError = error; return false }) else { throw CocoaError(.fileReadUnknown) }
                for case let file as URL in enumerator {
                    let attributes = try file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
                    guard attributes.isSymbolicLink != true else { throw BackupError.invalidFolder }
                    if attributes.isRegularFile == true { files.append(String(file.path.dropFirst(root.path.count + 1))) }
                }
                if let enumerationError { throw enumerationError }
            } else { files.append(name) }
        }
        return files.sorted()
    }
    private func digest(_ url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hash = CC_SHA256_CTX()
        CC_SHA256_Init(&hash)
        while let chunk = try handle.read(upToCount: 1024 * 1024), !chunk.isEmpty {
            _ = chunk.withUnsafeBytes { CC_SHA256_Update(&hash, $0.baseAddress, CC_LONG(chunk.count)) }
        }
        var bytes = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        CC_SHA256_Final(&bytes, &hash)
        return bytes.map { String(format: "%02x", $0) }.joined()
    }
}

enum BackupError: LocalizedError {
    case invalidFolder, invalidManifest, corruptedCopy, sourceChanged, destinationExists
    var errorDescription: String? {
        switch self {
        case .invalidFolder: "Choose another backup folder. Linked folders inside the library cannot be backed up."
        case .invalidManifest: "The backup index is invalid."
        case .corruptedCopy: "The copied files did not pass verification. Try backing up again."
        case .sourceChanged: "The library changed while copying. Please try again after finishing your edits."
        case .destinationExists: "Restore requires a new, empty destination. Your existing files were preserved."
        }
    }
}
