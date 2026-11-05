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
        // Default: everyday forms open, the rest folded.
        XCTAssertTrue(app.staticTexts["〜ます形"].exists, "常用形 should start expanded")
        assertHeadline(contains: ["食べる，たべꜜる", "食べます，たべまꜜす"])
        snapshot("3-conjugations")

        app.buttons["全部展开"].tap()
        XCTAssertTrue(app.buttons["全部收起"].waitForExistence(timeout: 5))
        snapshot("3b-conjugations-all-expanded")
        app.buttons["全部收起"].tap()
        XCTAssertTrue(app.buttons["全部展开"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["〜ます形"].exists, "全部收起 should fold 常用形 too")
        XCTAssertTrue(group("其他活用形").exists)
        XCTAssertTrue(group("使役・受身・可能").exists)
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

        // A noun with two accent variants, and an adjective with two readings of its forms.
        openFromSuggestion(typing: "eiga", word: "映画")
        assertHeadline(contains: ["映画，えꜜいが，えいが"])
        snapshot("10-headline-noun-variants")
        openFromSuggestion(typing: "tsumetai", word: "冷たい")
        assertHeadline(contains: ["冷たい，", "冷たいです，"])
        snapshot("11-headline-adjective")
    }

    private func openFromSuggestion(typing romaji: String, word: String) {
        app.tabBars.buttons["查询"].tap()
        for _ in 0..<3 where !(app.searchFields.firstMatch.exists && app.searchFields.firstMatch.isHittable) {
            let back = app.navigationBars.buttons.element(boundBy: 0)
            guard back.exists else { break }
            back.tap()
        }
        let field = app.searchFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 10) + romaji)
        let suggestion = app.buttons
            .matching(NSPredicate(format: "identifier == 'suggestion' AND label CONTAINS %@", word))
            .firstMatch
        XCTAssertTrue(suggestion.waitForExistence(timeout: 10), "No suggestion for \(word)")
        suggestion.tap()
        XCTAssertTrue(app.navigationBars[word].waitForExistence(timeout: 10))
    }

    /// The headline's accessibility label lists each part with its pitch notation.
    private func assertHeadline(contains parts: [String], file: StaticString = #filePath, line: UInt = #line) {
        let headline = app.descendants(matching: .any)["headline"]
        XCTAssertTrue(headline.waitForExistence(timeout: 5), "No headline", file: file, line: line)
        for part in parts {
            XCTAssertTrue(headline.label.contains(part), "Headline is \(headline.label)", file: file, line: line)
        }
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
