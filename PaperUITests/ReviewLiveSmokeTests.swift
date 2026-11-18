import XCTest

/// Opt-in: uses the actual iPad Keychain and Anthropic account; never sends a Reader highlight.
@MainActor final class ReviewLiveSmokeTests:XCTestCase {
    func testBrowseUpdatedPaperOnPhysicalIPad() throws {
        guard ProcessInfo.processInfo.environment["PAPER_LIVE_BROWSE"] == "1" else { throw XCTSkip("Opt-in physical browse, no analysis or Reader writes") }
        XCUIDevice.shared.orientation = .landscapeLeft
        defer { XCUIDevice.shared.orientation = .portrait }
        let app = XCUIApplication(); app.launch()
        XCTAssertTrue(app.buttons["downloaded-tab"].waitForExistence(timeout: 20))
        app.buttons["downloaded-tab"].tap()
        var attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); attachment.name = "Physical updated Downloaded library"; attachment.lifetime = .keepAlways; add(attachment)
        app.buttons["markups-tab"].tap()
        let context = app.buttons["Review pages"].firstMatch
        if context.waitForExistence(timeout: 25) {
            attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); attachment.name = "Physical global Markups inbox"; attachment.lifetime = .keepAlways; add(attachment)
            context.tap()
            XCTAssertTrue(app.buttons["analyze-markup"].waitForExistence(timeout: 15))
            attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); attachment.name = "Physical scrolling review and page thumbnails"; attachment.lifetime = .keepAlways; add(attachment)
            app.buttons["Done"].firstMatch.tap()
        }
        app.buttons["Library actions"].tap(); app.buttons["Backups"].tap()
        XCTAssertTrue(app.buttons["Choose backup folder"].waitForExistence(timeout: 10), app.debugDescription)
        attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); attachment.name = "Physical backup setup"; attachment.lifetime = .keepAlways; add(attachment)
        app.buttons["Done"].firstMatch.tap()
        app.buttons["downloaded-tab"].tap()
    }
    func testRefreshCoverMetadataOnPhysicalIPad() throws {
        guard ProcessInfo.processInfo.environment["PAPER_LIVE_REVIEW_ID"] != nil else {throw XCTSkip("Opt-in physical Reader refresh")}
        let app=XCUIApplication();app.launch()
        XCTAssertTrue(app.buttons["library-tab"].waitForExistence(timeout:15));app.buttons["library-tab"].tap()
        app.descendants(matching:.any).matching(identifier:"refresh-library").firstMatch.tap()
        app.buttons["Refresh entire catalog"].tap()
        let progress=app.descendants(matching:.any).matching(identifier:"refresh-progress").firstMatch
        XCTAssertTrue(progress.waitForExistence(timeout:10))
        XCTAssertTrue(progress.waitForNonExistence(timeout:120))
        XCTAssertFalse(app.descendants(matching:.any).matching(identifier:"library-error").firstMatch.exists)
        let shot=XCTAttachment(screenshot:XCUIScreen.main.screenshot());shot.name="Physical white library with refreshed covers";shot.lifetime = .keepAlways;add(shot)
    }
    func testSavedMarkupAnalysisOnPhysicalIPad() throws {
        guard let id=ProcessInfo.processInfo.environment["PAPER_LIVE_REVIEW_ID"] else {throw XCTSkip("Opt-in physical iPad analysis")}
        XCUIDevice.shared.orientation = .landscapeLeft
        defer { XCUIDevice.shared.orientation = .portrait }
        let app=XCUIApplication();app.launch()
        XCTAssertTrue(app.buttons["downloaded-tab"].waitForExistence(timeout:15));app.buttons["downloaded-tab"].tap()
        let actions=app.descendants(matching:.any).matching(identifier:"actions-\(id)").firstMatch
        XCTAssertTrue(actions.waitForExistence(timeout:15));actions.tap();app.buttons["Review markup"].tap()
        let analyze=app.buttons["analyze-markup"]
        XCTAssertTrue(analyze.waitForExistence(timeout:15));analyze.tap()
        let note=app.textViews["review-note"]
        XCTAssertTrue(note.waitForExistence(timeout:150),"The selected saved pages should produce reviewable drafts using the provisioned Anthropic key")
        let shot=XCTAttachment(screenshot:XCUIScreen.main.screenshot());shot.name="Physical iPad review after Anthropic analysis";shot.lifetime = .keepAlways;add(shot)
        app.buttons["Done"].firstMatch.tap()
    }
}
