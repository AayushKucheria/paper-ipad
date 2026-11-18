import XCTest
@testable import Paper

final class EPUBImportTests: XCTestCase {
    func testImportsSpineOrderAndRetainsOriginalAndResources() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let book = folder.appendingPathComponent("draft.epub")
        let original = try XCTUnwrap(Data(base64Encoded: Self.fixture, options: .ignoreUnknownCharacters))
        try original.write(to: book)

        let store = DocumentStore(root: folder.appendingPathComponent("Library"))
        let document = try store.importEPUB(at: book)
        XCTAssertEqual(document.title, "Ways of Reading")
        XCTAssertEqual(document.author, "A. Writer")
        XCTAssertEqual(document.format, .epub)
        let sections = try store.directReadingSections(for: document)
        XCTAssertEqual(sections.map(\.id), ["OPS/text/b.xhtml", "OPS/text/a.xhtml"])
        XCTAssertEqual(sections.map(\.title), ["Second in the file", "First in the file"])
        XCTAssertTrue(try String(contentsOf: sections[0].fileURL, encoding: .utf8).contains("../img/pic.svg"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: sections[0].readAccessURL.appendingPathComponent("OPS/img/pic.svg").path))
        let originalURL = store.pdfURL(for: document).deletingLastPathComponent().appendingPathComponent("source.epub")
        XCTAssertEqual(try Data(contentsOf: originalURL), original)
        try store.removeDownload(document)
        try store.restoreDownload(document)
        XCTAssertEqual(try store.directReadingSections(for: document).map(\.id), sections.map(\.id))
    }

    func testInvalidArchiveDoesNotPublishPartialDocument() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let bad = folder.appendingPathComponent("bad.epub")
        try Data("bad zip".utf8).write(to: bad)
        let store = DocumentStore(root: folder.appendingPathComponent("Library"))
        XCTAssertThrowsError(try store.importEPUB(at: bad))
        XCTAssertTrue(try store.documents().isEmpty)
    }

    func testRejectsArchivePathOutsidePublication() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let destination = root.appendingPathComponent("publication")
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        let bytes = try XCTUnwrap(Data(base64Encoded: Self.escapingFixture))
        XCTAssertThrowsError(try EPUBArchive.extract(bytes, to: destination))
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("escaped.xhtml").path))
    }

    private static let escapingFixture = "UEsDBBQAAAAAAHKzcl0846ZBBwAAAAcAAAAQAAAALi4vZXNjYXBlZC54aHRtbDxodG1sLz5QSwECFAMUAAAAAABys3JdPOOmQQcAAAAHAAAAEAAAAAAAAAAAAAAAgAEAAAAALi4vZXNjYXBlZC54aHRtbFBLBQYAAAAAAQABAD4AAAA1AAAAAAA="
    private static let fixture = """
    UEsDBBQAAAAAAIqycl1vYassFAAAABQAAAAIAAAAbWltZXR5cGVhcHBsaWNhdGlvbi9lcHViK3ppcFBLAwQUAAAACACKsnJdA1bD
    qmQAAACKAAAAFgAAAE1FVEEtSU5GL2NvbnRhaW5lci54bWxNjDEOQiEQBa/yQ6/0Gz5X0MQTIC6RCPsIuyQe38TiazfFzIQMsVSF
    5/buTXR3awohaVWS1FnJMmGwPJBXZzH6anRkLoYJWKmN9YdbWa2dRrLn7i7Xm78DrzNGcT4G/+f74xM/UEsDBBQAAAAIAIqycl3p
    A17H7AAAANMBAAAMAAAAT1BTL2Jvb2sub3BmnZHLbsQgDEV/BbGtime6qRSRSP2FbmbtgJNYDQkCt8n8fWlmMo9tl9x7fJDBRnRf
    2JNawzjlWg8isQJYlsWwj52ZUw9vh8M7zLHTF6jy7sbF7zRujHdAIwWaJMPRHEE3NpCgR8HGelcJy0jNCc9ZzZ36JPQ89RZuzR/j
    EqHMqfkw6pRYKG39nlq4CwNO3FGWxhYsKPa1Rq2GRF2thVYBNOsgYdQqkGd8lXOkgsQ4skPheYKtfin7aHiQtE+S9n+SyG7XcOih
    HE3+6Z8tHMqbQ4n3abivlCNPdPEVSVFuqna/4yHDbfLKw/Unm19QSwMEFAAAAAgAirJyXevgywWFAAAApwAAABAAAABPUFMvdGV4
    dC9hLnhodG1sJY1LDsMgDAWvYnEArKqrVA7LXKAnyIeCVQgI3JLevonYPWlG88hLDHDEsNdReZH8QGyt6XbXqTi8DcOAx+UoQ97O
    myFhCdZMXKoA7yDewouDJeyAsGtL2n6GsnnOMQcLS0pvTZgNcXRQyzoqrfHcmHnV9esUzEFGNbH7FKvw7PQCXufmD1BLAwQUAAAA
    CACKsnJdY5dZBIYAAACoAAAAEAAAAE9QUy90ZXh0L2IueGh0bWwljUEOgzAMBL9i5QGxqp6ojI/9AC8A4iZRExKB29DfF8RtpRnN
    UtCcYM9p2XoTVOsDsbVm292W1eOt6zrcT8cwBRkdk0ZNwoPMZXEQF9Ag8IpJCC9CeHlTcT+mysOYaxKYSnlbwsoUs4dtnXtjLR4b
    a5zt9vUGxqS9eUb/WcXg0bkKeL7zH1BLAwQUAAAACACKsnJdZms6RlQAAABfAAAADwAAAE9QUy9pbWcvcGljLnN2Z7MpLktXqMjN
    ySu2VcooKSmw0tcvLy/XKzfWyy9K1zcyMDDQB6pQUijLTC13yq+wVTJQMFAwBCElO5vkzKLknFSFIlslUyWF5AoIVQmi9O1sQPrs
    AFBLAQIUAxQAAAAAAIqycl1vYassFAAAABQAAAAIAAAAAAAAAAAAAACAAQAAAABtaW1ldHlwZVBLAQIUAxQAAAAIAIqycl0DVsOq
    ZAAAAIoAAAAWAAAAAAAAAAAAAACAAToAAABNRVRBLUlORi9jb250YWluZXIueG1sUEsBAhQDFAAAAAgAirJyXekDXsfsAAAA0wEA
    AAwAAAAAAAAAAAAAAIAB0gAAAE9QUy9ib29rLm9wZlBLAQIUAxQAAAAIAIqycl3r4MsFhQAAAKcAAAAQAAAAAAAAAAAAAACAAegB
    AABPUFMvdGV4dC9hLnhodG1sUEsBAhQDFAAAAAgAirJyXWOXWQSGAAAAqAAAABAAAAAAAAAAAAAAAIABmwIAAE9QUy90ZXh0L2Iu
    eGh0bWxQSwECFAMUAAAACACKsnJdZms6RlQAAABfAAAADwAAAAAAAAAAAAAAgAFPAwAAT1BTL2ltZy9waWMuc3ZnUEsFBgAAAAAG
    AAYAbQEAANADAAAAAA==
    """
}
