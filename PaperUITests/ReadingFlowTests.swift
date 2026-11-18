import XCTest

final class ReadingFlowTests: XCTestCase {
    func testStartsDownloadedAndOffersGlobalMarkups() {
        let app = XCUIApplication()
        app.launchEnvironment = ["PAPER_UI_TEST": "1", "PAPER_TEST_RESET": "1"]
        app.launch()
        let downloaded = app.buttons["downloaded-tab"]
        XCTAssertTrue(downloaded.waitForExistence(timeout: 10))
        XCTAssertTrue(downloaded.isSelected, "Paper should start with downloaded reading material")
        let markups = app.buttons["markups-tab"]
        XCTAssertTrue(markups.exists, "Pending markup needs its own library-wide inbox")
        if markups.exists {
            markups.tap()
            XCTAssertTrue(app.staticTexts["Your markup will appear here"].waitForExistence(timeout: 5))
        }
    }
    private func darkPixelsInWritingArea(_ screenshot: XCUIScreenshot) -> Int {
        let image = screenshot.image.cgImage!
        let width = image.width, height = image.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let context = CGContext(data: &pixels, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        var count = 0
        for y in Int(Double(height) * 0.50)..<Int(Double(height) * 0.68) {
            for x in Int(Double(width) * 0.25)..<Int(Double(width) * 0.75) {
                let offset = (y * width + x) * 4
                if pixels[offset] < 80 && pixels[offset + 1] < 80 && pixels[offset + 2] < 80 { count += 1 }
            }
        }
        return count
    }
    func testNativeMarkupIsVisibleAndSurvivesRelaunch() {
        let app = XCUIApplication()
        app.launchEnvironment = ["PAPER_UI_TEST": "1", "PAPER_TEST_RESET": "1"]
        app.launch()
        if app.buttons["sample"].waitForExistence(timeout: 4) { app.buttons["sample"].tap() }
        let markup = app.descendants(matching: .any).matching(identifier: "QLOverlayMarkupButtonAccessibilityIdentifier").firstMatch
        XCTAssertTrue(markup.waitForExistence(timeout: 25), app.debugDescription)
        markup.tap()
        let before = darkPixelsInWritingArea(app.screenshot())
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.35, dy: 0.55))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.65, dy: 0.60))
        start.press(forDuration: 0.1, thenDragTo: end)
        XCTAssertGreaterThan(darkPixelsInWritingArea(app.screenshot()), before + 50, "Native Markup must render ink on the page.")
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.lifetime = .keepAlways; add(shot)
        markup.tap()
        let close = app.buttons["QLOverlayDoneButtonAccessibilityIdentifier"]
        XCTAssertTrue(close.waitForExistence(timeout: 10), app.debugDescription)
        close.tap()
        XCTAssertTrue(app.navigationBars["Paper"].waitForExistence(timeout: 10))
        app.terminate()
        app.launchEnvironment.removeValue(forKey: "PAPER_TEST_RESET")
        app.launch()
        app.buttons["downloaded-tab"].tap()
        let saved = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "open-")).firstMatch
        XCTAssertTrue(saved.waitForExistence(timeout: 8))
        saved.tap()
        XCTAssertTrue(markup.waitForExistence(timeout: 25), app.debugDescription)
        XCTAssertGreaterThan(darkPixelsInWritingArea(app.screenshot()), before + 50, "Saved Markup must render after relaunch.")
    }
}
