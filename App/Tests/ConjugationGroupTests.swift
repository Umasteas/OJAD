import OJADKit
import XCTest
@testable import OJAD

final class ConjugationGroupTests: XCTestCase {
    private func entry(_ category: WordCategory, kinds: [String]) -> WordEntry {
        WordEntry(
            id: 1, headword: "x", category: category,
            forms: kinds.map { ConjugatedForm(kind: $0, label: $0, readings: []) }
        )
    }

    func testVerbFormsSplitIntoEverydayOtherAndDerived() {
        let kinds = ["jisho", "masu", "te", "ta", "nai", "nakatta", "ba", "shieki", "ukemi", "meirei", "kano", "ishi"]
        let groups = ConjugationGroup.groups(for: entry(.verb, kinds: kinds))

        XCTAssertEqual(groups.map(\.kind), [.common, .more, .derived])
        XCTAssertEqual(groups.map { $0.forms.map(\.kind) }, [
            ["jisho", "masu", "te", "ta", "nai"],
            ["nakatta", "ba", "meirei", "ishi"],
            ["shieki", "ukemi", "kano"],
        ])
        XCTAssertEqual(groups.flatMap(\.forms).count, kinds.count, "every form appears exactly once")
    }

    func testAdjectivesHaveNoDerivedGroup() {
        let kinds = ["jisho", "masu", "te", "ta", "nai", "nakatta", "ba", "shieki", "ukemi"]
        let groups = ConjugationGroup.groups(for: entry(.iAdjective, kinds: kinds))
        XCTAssertEqual(groups.map(\.kind), [.common, .more])
        XCTAssertEqual(groups[1].forms.map(\.kind), ["nakatta", "ba", "shieki", "ukemi"])
    }

    func testNounsAndUnknownColumns() {
        XCTAssertEqual(ConjugationGroup.groups(for: entry(.noun, kinds: ["jisho"])).map(\.kind), [.common])
        let odd = ConjugationGroup.groups(for: entry(.verb, kinds: ["jisho", "something"]))
        XCTAssertEqual(odd.map { $0.forms.map(\.kind) }, [["jisho"], ["something"]])
    }

    func testOnlyEverydayFormsStartExpanded() {
        XCTAssertEqual(ConjugationGroup.defaultExpanded, [.common])
    }
}
