import XCTest

/// Opt-in real-account check. Values come from a private xctestrun file, never source.
@MainActor final class ReaderLiveSmokeTests: XCTestCase {
    func testInstalledLibraryAndRealPDFDownload() throws {
        let environment = ProcessInfo.processInfo.environment
        guard let title = environment["PAPER_LIVE_PDF_TITLE"],
              let id = environment["PAPER_LIVE_PDF_ID"],
              let count = environment["PAPER_LIVE_PDF_COUNT"] else {
            throw XCTSkip("Run explicitly with private real-account verification configuration")
        }
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.buttons["reader-connection"].waitForExistence(timeout: 15))
        let total = app.staticTexts["pdf-count"]
        let ready = NSPredicate(format: "label == %@", "\(count) PDFs")
        expectation(for: ready, evaluatedWith: total)
        waitForExpectations(timeout: 90)
        XCTAssertEqual(app.buttons["reader-connection"].label, "Reader connected")
        let search = app.textFields["pdf-search"]
        search.tap(); search.typeText(title)
        let open = app.buttons["open-\(id)"]
        if open.waitForExistence(timeout: 2) { open.tap() }
        else {
            let download = app.buttons["download-\(id)"]
            XCTAssertTrue(download.waitForExistence(timeout: 10))
            download.tap()
        }
        let close = app.buttons["QLOverlayDoneButtonAccessibilityIdentifier"]
        XCTAssertTrue(close.waitForExistence(timeout: 60), "The real Reader PDF must download and open in Quick Look")
        let markup = app.descendants(matching: .any).matching(identifier: "QLOverlayMarkupButtonAccessibilityIdentifier").firstMatch
        XCTAssertTrue(markup.waitForExistence(timeout: 30), "The real PDF must finish rendering")
        let pdf = XCTAttachment(screenshot: app.screenshot()); pdf.name = "Real Reader PDF in Quick Look"; pdf.lifetime = .keepAlways; add(pdf)
        close.tap()
        app.buttons["downloaded-tab"].tap()
        XCTAssertTrue(open.waitForExistence(timeout: 10))
        open.tap()
        XCTAssertTrue(close.waitForExistence(timeout: 15))
        close.tap()
        if app.buttons["Clear search"].exists { app.buttons["Clear search"].tap() }
        app.buttons["library-tab"].tap()
        let library = XCTAttachment(screenshot: app.screenshot()); library.name = "Installed Reader library"; library.lifetime = .keepAlways; add(library)
    }
}
