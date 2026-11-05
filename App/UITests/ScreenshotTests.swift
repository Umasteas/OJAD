import XCTest

/// Walks the main flow and keeps a screenshot of each screen as an xcresult
/// attachment. Everything is offline.
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

        let senseHeader = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH '①' OR label BEGINSWITH '②'")).firstMatch
        XCTAssertTrue(senseHeader.exists, "Examples aren't grouped under numbered senses")
        let online = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS '在线'")).firstMatch
        XCTAssertFalse(online.exists, "Online feature still shown: \(online.label)")
        for _ in 0..<3 { app.swipeUp() }
        snapshot("5-more-senses")

        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.staticTexts["食べる・食べます"].waitForExistence(timeout: 10))
        snapshot("6-search-results")

        app.tabBars.buttons["关于"].tap()
        let selfTest = app.buttons["运行自检"]
        for _ in 0..<6 where !(selfTest.exists && selfTest.isHittable) {
            app.swipeUp()
        }
        let state = app.descendants(matching: .any)["dictionary-state"]
        XCTAssertTrue(state.exists, "No dictionary status row")
        XCTAssertTrue(state.label.contains("已加载") || "\(state.value ?? "")".contains("已加载"), "Dictionary status: \(state.label)")
        selfTest.tap()
        XCTAssertTrue(selfTest.waitForExistence(timeout: 10))
        snapshot("7-dictionary-status")
    }

    private func snapshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
