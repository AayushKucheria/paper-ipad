import XCTest
@testable import Paper

final class SectionNavigatorTests: XCTestCase {
    private let margin: CGFloat = 24

    func testNextButtonAppearsOnlyAtTheEndOfALongSection() {
        XCTAssertEqual(SectionNavigator.edgeButtons(offset: 1_000, contentHeight: 1_800, viewport: 800, margin: margin), [.next])
        XCTAssertEqual(SectionNavigator.edgeButtons(offset: 990, contentHeight: 1_800, viewport: 800, margin: margin), [.next])
    }

    func testPreviousButtonAppearsOnlyAtTheStart() {
        XCTAssertEqual(SectionNavigator.edgeButtons(offset: 0, contentHeight: 1_800, viewport: 800, margin: margin), [.previous])
    }

    func testMidSectionShowsNoButtons() {
        XCTAssertEqual(SectionNavigator.edgeButtons(offset: 500, contentHeight: 1_800, viewport: 800, margin: margin), [])
    }

    func testShortSectionShowsBothButtonsWithoutScrolling() {
        // A title page shorter than the screen can't scroll, so both ways out must be visible immediately.
        XCTAssertEqual(SectionNavigator.edgeButtons(offset: 0, contentHeight: 300, viewport: 800, margin: margin), [.previous, .next])
    }

    func testSectionTitlesCollapseMarkupWhitespace() {
        XCTAssertEqual(EPUBPublication.displayTitle("Act\n\t\t\t\tI"), "Act I")
        XCTAssertEqual(EPUBPublication.displayTitle("  Dramatis   Personae "), "Dramatis Personae")
        XCTAssertEqual(EPUBPublication.displayTitle("Imprint"), "Imprint")
    }

    func testStepsClampAtTheBookEnds() {
        var navigator = SectionNavigator(index: 0, count: 3)
        XCTAssertNil(navigator.step(.previous))
        XCTAssertEqual(navigator.index, 0)
        XCTAssertEqual(navigator.step(.next), .top)
        XCTAssertEqual(navigator.step(.next), .top)
        XCTAssertEqual(navigator.index, 2)
        XCTAssertNil(navigator.step(.next))
        XCTAssertEqual(navigator.step(.previous), .bottom)
        XCTAssertEqual(navigator.index, 1)
    }

    func testNeighboursExposeTitlesForTheIndicator() {
        let navigator = SectionNavigator(index: 1, count: 3)
        XCTAssertEqual(navigator.neighbour(.previous), 0)
        XCTAssertEqual(navigator.neighbour(.next), 2)
        XCTAssertNil(SectionNavigator(index: 0, count: 3).neighbour(.previous))
        XCTAssertNil(SectionNavigator(index: 2, count: 3).neighbour(.next))
    }

    func testResumeIndexIsClampedToTheBook() {
        XCTAssertEqual(SectionNavigator.resumeIndex(saved: 7, count: 3), 2)
        XCTAssertEqual(SectionNavigator.resumeIndex(saved: -2, count: 3), 0)
        XCTAssertEqual(SectionNavigator.resumeIndex(saved: 1, count: 3), 1)
        XCTAssertEqual(SectionNavigator.resumeIndex(saved: 1, count: 0), 0)
    }

    func testArrivalOffsetsKeepEachSectionIsolated() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let ink = DirectInkStore(directory: folder)
        try ink.save(DirectInkState(drawing: .init(), offset: 420), section: "act-1")
        try ink.save(DirectInkState(drawing: .init(), offset: 15), section: "act-2")
        XCTAssertEqual(SectionNavigator.startOffset(.saved, savedOffset: try ink.load(section: "act-1").offset), 420)
        XCTAssertEqual(SectionNavigator.startOffset(.top, savedOffset: 420), 0)
        XCTAssertEqual(SectionNavigator.startOffset(.bottom, savedOffset: 420), .greatestFiniteMagnitude)
        XCTAssertEqual(try ink.load(section: "act-2").offset, 15)
    }
}
