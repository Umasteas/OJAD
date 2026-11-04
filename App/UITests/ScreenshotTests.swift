import XCTest

/// Walks the main flow and keeps a screenshot of each screen as an xcresult
/// attachment. Search, conjugations and examples are offline; the run makes one
/// スズキクン analysis request against the live service.
final class ScreenshotTests: XCTestCase {
    private let app = XCUIApplication()

    override func setUp() {
        continueAfterFailure = false
        app.launch()
    }

    func testMainFlow() {
        snapshot("1-empty-search")

        let field = app.searchFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        field.tap()
        field.typeText("tabe")

        let suggestion = app.buttons.matching(identifier: "suggestion").firstMatch
        XCTAssertTrue(suggestion.waitForExistence(timeout: 10), "No suggestions appeared")
        XCTAssertTrue(suggestion.label.contains("食べる"), "First suggestion is \(suggestion.label)")
        snapshot("2-suggestions")

        suggestion.tap()
        XCTAssertTrue(app.navigationBars["食べる"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["to eat"].waitForExistence(timeout: 5), "JMdict gloss missing")
        snapshot("3-conjugations")

        let example = app.staticTexts
            .matching(NSPredicate(format: "label CONTAINS '食べ' AND (label ENDSWITH '。' OR label ENDSWITH '？' OR label ENDSWITH '！')"))
            .firstMatch
        // List rows below the fold aren't in the accessibility tree until scrolled to.
        for _ in 0..<15 where !(example.exists && example.isHittable) {
            app.swipeUp()
            RunLoop.current.run(until: Date().addingTimeInterval(1))
        }
        XCTAssertTrue(example.exists, "No offline example appeared")
        snapshot("4-examples")

        example.tap()
        XCTAssertTrue(app.navigationBars["例句"].waitForExistence(timeout: 10))
        let analyze = app.buttons["在线请求スズキクン语调分析"]
        XCTAssertTrue(analyze.waitForExistence(timeout: 5))
        analyze.tap()
        XCTAssertTrue(app.staticTexts["正在请求スズキクン分析…"].waitForNonExistence(timeout: 30))
        XCTAssertFalse(app.buttons["重试"].exists, "スズキクン analysis failed")
        snapshot("5-sentence-intonation")

        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.staticTexts["食べる・食べます"].waitForExistence(timeout: 10))
        snapshot("6-search-results")
    }

    private func snapshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
