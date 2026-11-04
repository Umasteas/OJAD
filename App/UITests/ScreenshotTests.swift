import XCTest

/// Walks the main flow against the live services and keeps a screenshot of each
/// screen as an xcresult attachment. Makes one OJAD search, one Tatoeba query and
/// one スズキクン analysis per run.
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
        field.typeText("食べる\n")

        let row = app.staticTexts["食べる・食べます"]
        XCTAssertTrue(row.waitForExistence(timeout: 30), "OJAD search result did not appear")
        snapshot("2-search-results")

        row.tap()
        XCTAssertTrue(app.navigationBars["食べる"].waitForExistence(timeout: 10))
        snapshot("3-conjugations")

        let example = app.staticTexts
            .matching(NSPredicate(format: "label CONTAINS '食べる' AND (label ENDSWITH '。' OR label ENDSWITH '？' OR label ENDSWITH '！')"))
            .firstMatch
        // List rows below the fold aren't in the accessibility tree until scrolled to.
        for _ in 0..<15 where !(example.exists && example.isHittable) {
            app.swipeUp()
            RunLoop.current.run(until: Date().addingTimeInterval(1.5))
        }
        XCTAssertTrue(example.exists, "No Tatoeba example appeared")
        snapshot("4-examples")

        example.tap()
        XCTAssertTrue(app.navigationBars["例句"].waitForExistence(timeout: 10))
        let analyzing = app.staticTexts["正在请求スズキクン分析…"]
        let deadline = Date().addingTimeInterval(30)
        while analyzing.exists, Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.5))
        }
        snapshot("5-sentence-intonation")
    }

    private func snapshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
