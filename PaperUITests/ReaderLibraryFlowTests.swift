import XCTest

@MainActor final class ReaderLibraryFlowTests: XCTestCase {
    func capture(_ name: String, app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
    func testAnalyzeReviewSendPersistAndRestoreDownload() async throws {
        XCUIDevice.shared.orientation = .landscapeLeft
        defer { XCUIDevice.shared.orientation = .portrait }
        _ = try await URLSession.shared.data(from: URL(string: "http://localhost:18767/reset")!)
        let app=XCUIApplication()
        app.launchEnvironment=["PAPER_UI_TEST":"1","PAPER_TEST_RESET":"1","PAPER_READER_BASE_URL":"http://localhost:18767/api/v3/"]
        app.launch()
        app.buttons["reader-connection"].tap()
        let token=app.secureTextFields["reader-token"]
        XCTAssertTrue(token.waitForExistence(timeout:5));token.tap();token.typeText("ui-test-token")
        app.buttons["connect-reader"].tap()
        XCTAssertTrue(app.buttons["download-guide"].waitForExistence(timeout:15));app.buttons["download-guide"].tap()
        let close=app.buttons["QLOverlayDoneButtonAccessibilityIdentifier"]
        XCTAssertTrue(close.waitForExistence(timeout:25))
        XCTAssertTrue(app.descendants(matching:.any).matching(identifier:"QLOverlayMarkupButtonAccessibilityIdentifier").firstMatch.waitForExistence(timeout:25))
        close.tap()
        XCTAssertTrue(app.navigationBars["Paper"].waitForExistence(timeout:10))
        app.buttons["downloaded-tab"].tap()
        let actions=app.descendants(matching:.any).matching(identifier:"actions-guide").firstMatch
        XCTAssertTrue(actions.waitForExistence(timeout:10),app.debugDescription)
        actions.tap();app.buttons["Review markup"].tap()
        XCTAssertTrue(app.buttons["analyze-markup"].waitForExistence(timeout:10))
        capture("Landscape PDF and review",app:app)
        app.buttons["AI settings"].tap()
        let key=app.secureTextFields["anthropic-key"]
        XCTAssertTrue(key.waitForExistence(timeout:5));key.tap();key.typeText("fake-anthropic-key")
        app.buttons["save-anthropic-key"].tap()
        app.buttons["analyze-markup"].tap()
        let quote=app.textViews["review-quote"]
        XCTAssertTrue(quote.waitForExistence(timeout:20),app.debugDescription)
        let note=app.textViews["review-note"]
        note.tap();note.typeText(" — reviewed")
        let drafts=app.scrollViews["review-drafts"]
        drafts.swipeUp()
        let send=app.buttons["send-review"]
        if !send.isHittable { drafts.swipeUp() }
        send.tap()
        XCTAssertTrue(app.staticTexts["Sent to Reader"].waitForExistence(timeout:10),app.debugDescription)
        capture("Reviewed markup sent",app:app)
        app.buttons["Done"].firstMatch.tap()
        app.terminate();app.launchEnvironment.removeValue(forKey:"PAPER_TEST_RESET");app.launch()
        app.buttons["downloaded-tab"].tap();app.descendants(matching:.any).matching(identifier:"actions-guide").firstMatch.tap();app.buttons["Review markup"].tap()
        XCTAssertTrue(app.staticTexts["Sent to Reader"].waitForExistence(timeout:10))
        XCTAssertFalse(app.buttons["send-review"].exists)
        app.buttons["Done"].firstMatch.tap()
        let(beforeData,_)=try await URLSession.shared.data(from:URL(string:"http://localhost:18767/metrics")!)
        let beforeRestore=try XCTUnwrap(JSONSerialization.jsonObject(with:beforeData) as? [String:Int])
        app.descendants(matching:.any).matching(identifier:"actions-guide").firstMatch.tap();app.buttons["Remove download…"].tap();app.buttons["Move to Recently Removed"].tap()
        XCTAssertTrue(app.buttons["open-guide"].waitForNonExistence(timeout:5))
        app.buttons["Library actions"].tap();app.buttons["Recently Removed"].tap()
        let restore=app.buttons.matching(NSPredicate(format:"identifier BEGINSWITH %@","restore-")).firstMatch
        XCTAssertTrue(restore.waitForExistence(timeout:5));restore.tap();app.buttons["Done"].firstMatch.tap()
        XCTAssertTrue(app.buttons["open-guide"].waitForExistence(timeout:5))
        let(data,_)=try await URLSession.shared.data(from:URL(string:"http://localhost:18767/metrics")!)
        let counts=try XCTUnwrap(JSONSerialization.jsonObject(with:data) as? [String:Int])
        XCTAssertEqual(counts["analysis_requests"],1);XCTAssertEqual(counts["highlight_posts"],1);XCTAssertEqual(counts["pdf_requests"],beforeRestore["pdf_requests"],"Restoring a download must reuse the retained local PDF")
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
