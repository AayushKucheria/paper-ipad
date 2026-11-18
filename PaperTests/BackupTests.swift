import XCTest
@testable import Paper

final class BackupTests: XCTestCase {
    private var root: URL!
    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: root) }
    private func write(_ text: String, _ path: String, under directory: URL) throws {
        let url = directory.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
    }
    func testSnapshotRestoresAnnotatedCopyMetadataAndReviewWithoutCredentials() throws {
        let source = root.appendingPathComponent("Documents")
        let files = ["Library/id/source.pdf", "Library/id/reading.pdf", "Library/id/document.json", "Library/id/review.json", "Library/id/analysis.json", "Library/article/source.html", "Library/article/source.txt", "RecentlyRemoved/old/reading.pdf", "reader-catalog.json", "reader-articles.json"]
        for path in files { try write("contents: \(path)", path, under: source) }
        try write("secret", ".env", under: source)
        try write("secret", "tmp/reader-token.txt", under: source)
        let backup = try BackupSnapshot().create(documentsRoot: source, destination: root.appendingPathComponent("Cloud"))
        let restored = root.appendingPathComponent("Restored")
        try BackupSnapshot().restore(snapshot: backup, into: restored)
        for path in files { XCTAssertEqual(try Data(contentsOf: restored.appendingPathComponent(path)), try Data(contentsOf: source.appendingPathComponent(path))) }
        XCTAssertFalse(FileManager.default.fileExists(atPath: restored.appendingPathComponent(".env").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: restored.appendingPathComponent("tmp").path))
    }
    func testNewVersionsRetainOldCopyAndCorruptionCannotRestore() throws {
        let source = root.appendingPathComponent("Documents"), destination = root.appendingPathComponent("Cloud")
        try write("first", "Library/id/reading.pdf", under: source)
        let first = try BackupSnapshot().create(documentsRoot: source, destination: destination)
        try write("second", "Library/id/reading.pdf", under: source)
        let second = try BackupSnapshot().create(documentsRoot: source, destination: destination)
        XCTAssertNotEqual(first, second)
        let restored = root.appendingPathComponent("Restored")
        try BackupSnapshot().restore(snapshot: first, into: restored)
        XCTAssertEqual(String(data: try Data(contentsOf: restored.appendingPathComponent("Library/id/reading.pdf")), encoding: .utf8), "first")
        try write("corrupted", "Library/id/reading.pdf", under: second)
        let failedRestore = root.appendingPathComponent("BadRestore")
        XCTAssertThrowsError(try BackupSnapshot().restore(snapshot: second, into: failedRestore))
        XCTAssertFalse(FileManager.default.fileExists(atPath: failedRestore.path))
        XCTAssertThrowsError(try BackupSnapshot().restore(snapshot: first, into: restored))
    }
    func testFailedNewBackupKeepsPreviousVersionAndDoesNotFollowSymlinks() throws {
        let source = root.appendingPathComponent("Documents"), destination = root.appendingPathComponent("Cloud")
        try write("kept", "Library/id/reading.pdf", under: source)
        let good = try BackupSnapshot().create(documentsRoot: source, destination: destination)
        let secret = root.appendingPathComponent("secret.txt")
        try Data("private".utf8).write(to: secret)
        try FileManager.default.createSymbolicLink(at: source.appendingPathComponent("Library/id/linked.txt"), withDestinationURL: secret)
        XCTAssertThrowsError(try BackupSnapshot().create(documentsRoot: source, destination: destination))
        let versions = try FileManager.default.contentsOfDirectory(at: destination.appendingPathComponent("Paper Backups"), includingPropertiesForKeys: nil)
        XCTAssertEqual(versions, [good])
        let restored = root.appendingPathComponent("Restored")
        try BackupSnapshot().restore(snapshot: good, into: restored)
        XCTAssertEqual(String(data: try Data(contentsOf: restored.appendingPathComponent("Library/id/reading.pdf")), encoding: .utf8), "kept")
    }

}
