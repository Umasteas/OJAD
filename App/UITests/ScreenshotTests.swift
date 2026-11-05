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
        // Default: everyday forms open, the rest folded.
        XCTAssertTrue(app.staticTexts["〜ます形"].exists, "常用形 should start expanded")
        XCTAssertTrue(group("其他活用形").exists)
        snapshot("3-conjugations")

        app.buttons["全部展开"].tap()
        XCTAssertTrue(app.buttons["全部收起"].waitForExistence(timeout: 5))
        snapshot("3b-conjugations-all-expanded")
        app.buttons["全部收起"].tap()
        XCTAssertTrue(app.buttons["全部展开"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["〜ます形"].exists, "全部收起 should fold 常用形 too")
        snapshot("3c-conjugations-collapsed")
        group("常用形").tap()
        XCTAssertTrue(app.staticTexts["〜ます形"].waitForExistence(timeout: 5))

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

        // A second query, so history has a row to remove and one to clear.
        app.tabBars.buttons["查询"].tap()
        let searchField = app.searchFields.firstMatch
        searchField.tap()
        searchField.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 6) + "gakkou\n")
        XCTAssertTrue(app.staticTexts["学校"].waitForExistence(timeout: 10))

        app.tabBars.buttons["历史"].tap()
        let removeTaberu = app.buttons["删除「食べる」"]
        XCTAssertTrue(removeTaberu.waitForExistence(timeout: 5), "No ✕ on the history row")
        XCTAssertGreaterThanOrEqual(removeTaberu.frame.width, 44)
        XCTAssertGreaterThanOrEqual(removeTaberu.frame.height, 44)
        snapshot("8-history")
        removeTaberu.tap()
        XCTAssertTrue(removeTaberu.waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.buttons["删除「gakkou」"].exists, "✕ removed more than its own row")

        app.buttons["全部清除"].tap()
        let confirm = app.buttons["清除全部记录"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5), "No confirmation before clearing")
        snapshot("9-history-confirm-clear")
        confirm.tap()
        XCTAssertTrue(app.staticTexts["没有查询记录"].waitForExistence(timeout: 5))
    }

    /// A conjugation group's disclosure row (its label also lists the folded forms).
    private func group(_ title: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH %@", title)).firstMatch
    }

    private func snapshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
