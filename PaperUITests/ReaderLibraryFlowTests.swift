import XCTest

@MainActor final class ReaderLibraryFlowTests: XCTestCase {
    func capture(_ name: String, app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
    func testConnectPaginateSearchDownloadAndReopenOffline() async throws {
        let _ = try await URLSession.shared.data(from: URL(string: "http://localhost:18767/reset")!)
        let app = XCUIApplication()
        app.launchEnvironment = ["PAPER_UI_TEST": "1", "PAPER_TEST_RESET": "1", "PAPER_READER_BASE_URL": "http://localhost:18767/api/v3/"]
        app.launch()
        let connect = app.buttons["reader-connection"]
        guard connect.waitForExistence(timeout: 8) else { XCTFail("The library needs a Reader connection control"); return }
        connect.tap()
        let token = app.secureTextFields["reader-token"]
        XCTAssertTrue(token.waitForExistence(timeout: 5))
        token.tap(); token.typeText("ui-test-token")
        app.buttons["connect-reader"].tap()
        XCTAssertTrue(app.staticTexts["A field guide to slow reading"].waitForExistence(timeout: 20))
        XCTAssertTrue(app.staticTexts["Thinking on paper"].waitForExistence(timeout: 10), "All catalog pages must be shown")
        capture("Reader library", app: app)
        let search = app.textFields["pdf-search"]
        XCTAssertTrue(search.exists)
        search.tap(); search.typeText("margins")
        XCTAssertTrue(app.staticTexts["A field guide to slow reading"].exists)
        XCTAssertFalse(app.staticTexts["Thinking on paper"].exists)
        app.buttons["download-guide"].tap()
        capture("Downloading a PDF", app: app)
        let close = app.buttons["QLOverlayDoneButtonAccessibilityIdentifier"]
        XCTAssertTrue(close.waitForExistence(timeout: 20), app.debugDescription)
        let markup = app.descendants(matching: .any).matching(identifier: "QLOverlayMarkupButtonAccessibilityIdentifier").firstMatch
        XCTAssertTrue(markup.waitForExistence(timeout: 25), "The downloaded PDF must finish rendering with native Markup available")
        capture("Downloaded PDF in Quick Look", app: app)
        close.tap()
        app.buttons["downloaded-tab"].tap()
        XCTAssertTrue(app.buttons["open-guide"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Downloaded"].waitForExistence(timeout: 10))
        capture("Downloaded library", app: app)
        app.terminate()
        app.launchEnvironment.removeValue(forKey: "PAPER_TEST_RESET")
        app.launchEnvironment["PAPER_READER_BASE_URL"] = "http://localhost:18768/api/v3/"
        app.launch()
        app.buttons["downloaded-tab"].tap()
        XCTAssertTrue(app.buttons["open-guide"].waitForExistence(timeout: 8))
        app.buttons["open-guide"].tap()
        XCTAssertTrue(close.waitForExistence(timeout: 15), "The retained PDF must open while the API is unreachable")
        XCTAssertTrue(markup.waitForExistence(timeout: 25), "The retained PDF must render offline")
        close.tap()
        let (data, _) = try await URLSession.shared.data(from: URL(string: "http://localhost:18767/metrics")!)
        let metrics = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Int])
        XCTAssertGreaterThanOrEqual(metrics["catalog_requests"] ?? 0, 3)
        XCTAssertEqual(metrics["pdf_requests"], 1)
        XCTAssertEqual(metrics["pdf_authorization_headers"], 0)
    }
}
