import XCTest
import CryptoKit
import PencilKit
@testable import Paper

final class DirectInkTests: XCTestCase {
    func testStrokeAndPositionSurviveReloadAndStayWithSection() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let ink = DirectInkStore(directory: directory)
        let drawing = testInkDrawing()
        try ink.save(.init(drawing: drawing, offset: 860), section: "chapter/one")

        let reopened = DirectInkStore(directory: directory)
        XCTAssertEqual(try reopened.load(section: "chapter/one").drawing.strokes.first?.ink.inkType, .marker)
        XCTAssertEqual(try reopened.load(section: "chapter/one").offset, 860)
        XCTAssertTrue(try reopened.load(section: "chapter/two").drawing.strokes.isEmpty)
        XCTAssertTrue(reopened.hasInk)
        try reopened.save(.init(offset: 860), section: "chapter/one")
        XCTAssertFalse(reopened.hasInk)
    }
}

extension DirectInkTests {
    func testOpeningLegacyInkCreatesPencilKitFileAndKeepsLegacyBytes() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let store = DirectInkStore(directory: directory)
        let section = "chapter/legacy"
        let legacy = Data(#"{"strokes":[{"points":[[25,920],[175,934]]},{"points":[[50,950]]}],"offset":860}"#.utf8)
        let legacyURL = directory.appendingPathComponent("direct-ink-\(SHA256.hash(data: Data(section.utf8)).map { String(format: "%02x", $0) }.joined()).json")
        try legacy.write(to: legacyURL)

        XCTAssertTrue(store.hasInk)
        let migrated = try store.load(section: section)
        XCTAssertEqual(migrated.offset, 860)
        XCTAssertEqual(migrated.drawing.strokes.count, 2)
        XCTAssertEqual(migrated.drawing.strokes.first?.path.first?.location, CGPoint(x: 25, y: 920))
        XCTAssertEqual(migrated.drawing.strokes.first?.path.last?.location, CGPoint(x: 175, y: 934))
        XCTAssertEqual(migrated.drawing.strokes.last?.path.first?.location, CGPoint(x: 50, y: 950))
        XCTAssertEqual(try store.load(section: section).drawing.strokes.count, 2)
        try store.save(.init(offset: 860), section: section)
        XCTAssertTrue(try store.load(section: section).drawing.strokes.isEmpty)
        XCTAssertFalse(store.hasInk)
        let files = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        XCTAssertEqual(files.filter { $0.hasPrefix("pencil-ink-") }.count, 1)
        XCTAssertEqual(try Data(contentsOf: legacyURL), legacy)
    }
}

func testInkDrawing() -> PKDrawing {
    let points = [CGPoint(x: 25, y: 920), CGPoint(x: 175, y: 934)].enumerated().map { index, location in
        PKStrokePoint(location: location, timeOffset: Double(index) / 120,
                      size: CGSize(width: 10, height: 10), opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2)
    }
    return PKDrawing(strokes: [PKStroke(ink: PKInk(.marker, color: .systemYellow),
                                        path: PKStrokePath(controlPoints: points, creationDate: .now))])
}

extension DirectInkTests {
    @MainActor
    func testReopenCopiedReleaseArticleBeforeAddingInk() async throws {
        guard let path = ProcessInfo.processInfo.environment["PAPER_LEGACY_ARTICLE_DIR"] else {
            throw XCTSkip("Set TEST_RUNNER_PAPER_LEGACY_ARTICLE_DIR to a private copy of a marked release article.")
        }
        let source = URL(fileURLWithPath: path, isDirectory: true)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.copyItem(at: source, to: directory)
        let legacyFile = try XCTUnwrap(FileManager.default.contentsOfDirectory(atPath: directory.path)
            .first { $0.hasPrefix("direct-ink-") })
        let legacyURL = directory.appendingPathComponent(legacyFile)
        let legacy = try Data(contentsOf: legacyURL)
        struct ReleaseState: Decodable {
            struct Stroke: Decodable { let points: [CGPoint] }
            let strokes: [Stroke]
            let offset: CGFloat
        }
        let release = try JSONDecoder().decode(ReleaseState.self, from: legacy)

        let store = DirectInkStore(directory: directory)
        let controller = DirectInkController(ink: store)
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.rootViewController = controller
        window.isHidden = false
        defer { window.isHidden = true }
        let ready = expectation(description: "Migrated artwork becomes visible")
        ready.assertForOverFulfill = false
        controller.onState = { if $0 { ready.fulfill() } }
        controller.open(DirectReadingSection(id: "article", title: "Release article",
            fileURL: directory.appendingPathComponent("reading.html"), readAccessURL: directory, baseURL: nil))
        await fulfillment(of: [ready], timeout: 15)

        let migrated = try store.load(section: "article")
        XCTAssertEqual(migrated.drawing.strokes.count, release.strokes.count)
        XCTAssertEqual(migrated.offset, release.offset)
        for (stroke, original) in zip(migrated.drawing.strokes, release.strokes) {
            XCTAssertEqual(stroke.path.first?.location, original.points.first)
        }
        let capture = try await controller.capture(chapter: 0)
        XCTAssertFalse(capture.sourceText.isEmpty)
        XCTAssertNotNil(UIImage(data: capture.jpeg))
        XCTAssertEqual(try Data(contentsOf: legacyURL), legacy)
    }
}

extension DirectInkTests {
    @MainActor
    func testScrolledChapterCaptureAlignsInkAndKeepsChaptersSeparate() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        func chapter(_ name: String, text: String) throws -> DirectReadingSection {
            let url = directory.appendingPathComponent(name + ".html")
            try """
                <html><head></head><body>
                <div style="height:850px"></div><p>\(text)</p><div style="height:1800px"></div>
                </body></html>
                """.write(to: url, atomically: true, encoding: .utf8)
            return DirectReadingSection(id: name, title: name, fileURL: url, readAccessURL: directory, baseURL: nil)
        }
        let first = try chapter("first", text: "First chapter source sentence")
        let second = try chapter("second", text: "Second chapter source sentence")
        let store = DirectInkStore(directory: directory)
        try store.save(.init(drawing: testInkDrawing(), offset: 860), section: first.id)
        try store.save(.init(offset: 860), section: second.id)

        let controller = DirectInkController(ink: store)
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.rootViewController = controller
        window.isHidden = false
        defer { window.isHidden = true }

        func open(_ section: DirectReadingSection, withVisibleInk visible: Bool) async {
            let ready = expectation(description: "\(section.id) chapter ready")
            ready.assertForOverFulfill = false
            controller.onState = { if $0 == visible { ready.fulfill() } }
            controller.open(section)
            await fulfillment(of: [ready], timeout: 10)
            controller.onState = nil
        }

        await open(first, withVisibleInk: true)
        let marked = try await controller.capture(chapter: 0)
        XCTAssertEqual(marked.number, 2)
        XCTAssertTrue(marked.sourceText.contains("First chapter source sentence") == true)
        XCTAssertTrue(try containsYellowInk(marked.jpeg), "The highlight should be drawn near x 100, y 67 in the scrolled viewport")

        await open(second, withVisibleInk: false)
        let clean = try await controller.capture(chapter: 1)
        XCTAssertEqual(clean.number, 100_002)
        XCTAssertTrue(clean.sourceText.contains("Second chapter source sentence") == true)
        XCTAssertFalse(try containsYellowInk(clean.jpeg))

        await open(first, withVisibleInk: true)
        let reopened = try await controller.capture(chapter: 0)
        XCTAssertEqual(reopened.number, marked.number)
        XCTAssertTrue(try containsYellowInk(reopened.jpeg))
    }

    private func containsYellowInk(_ jpeg: Data) throws -> Bool {
        let image = try XCTUnwrap(UIImage(data: jpeg)?.cgImage)
        let scale = CGFloat(image.width) / 820
        let sample = CGRect(x: 80, y: 58, width: 40, height: 20)
            .applying(CGAffineTransform(scaleX: scale, y: scale))
        let crop = try XCTUnwrap(image.cropping(to: sample))
        let context = try XCTUnwrap(CGContext(data: nil, width: crop.width, height: crop.height,
            bitsPerComponent: 8, bytesPerRow: crop.width * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue))
        context.draw(crop, in: CGRect(x: 0, y: 0, width: crop.width, height: crop.height))
        let bytes = try XCTUnwrap(context.data).assumingMemoryBound(to: UInt8.self)
        return (0..<(crop.width * crop.height)).contains { pixel in
            let i = pixel * 4
            return bytes[i] > 200 && bytes[i + 1] > 165 && bytes[i + 2] < 170
        }
    }
}
