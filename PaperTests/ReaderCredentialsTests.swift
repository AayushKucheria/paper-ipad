import XCTest
@testable import Paper

final class ReaderCredentialsTests: XCTestCase {
    var credentials: ReaderCredentials!
    var root: URL!
    override func setUpWithError() throws {
        credentials = ReaderCredentials(service: "app.paper.test.\(UUID().uuidString)")
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws {
        try credentials.remove()
        try FileManager.default.removeItem(at: root)
    }
    func testTokenReplacementAndInvalidSaveRetainPriorToken() throws {
        XCTAssertNil(try credentials.read())
        try credentials.save("obvious-fake-token-one")
        XCTAssertEqual(try credentials.read(), "obvious-fake-token-one")
        try credentials.save("obvious-fake-token-two")
        XCTAssertEqual(try credentials.read(), "obvious-fake-token-two")
        XCTAssertThrowsError(try credentials.save(" \n"))
        XCTAssertEqual(try credentials.read(), "obvious-fake-token-two")
        try credentials.remove()
        XCTAssertNil(try credentials.read())
    }
    func testProvisionConsumesFileOnlyAfterSuccessfulSave() throws {
        let url = root.appendingPathComponent("reader-token.txt")
        XCTAssertFalse(try credentials.consumeProvisionedToken(at: url))
        try Data("  obvious-fake-provision-token\n".utf8).write(to: url)
        XCTAssertTrue(try credentials.consumeProvisionedToken(at: url))
        XCTAssertEqual(try credentials.read(), "obvious-fake-provision-token")
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
        try Data("  \n".utf8).write(to: url)
        XCTAssertThrowsError(try credentials.consumeProvisionedToken(at: url))
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        XCTAssertEqual(try credentials.read(), "obvious-fake-provision-token")
    }
}
