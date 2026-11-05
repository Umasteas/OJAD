import XCTest
@testable import OJADKit

final class HeadlineTests: XCTestCase {
    private func entry(_ written: String, _ reading: String, _ accents: [Int], _ wordClass: WordClass) -> WordEntry {
        WordEntry(
            id: 1,
            headword: Conjugator.headword(written: written, reading: reading, wordClass: wordClass),
            category: wordClass.category,
            forms: Conjugator.forms(reading: reading, accents: accents, wordClass: wordClass)
        )
    }

    private func notations(_ entry: WordEntry) -> [String] {
        entry.headlineForms.map { "\($0.written) " + $0.readings.map(\.notation).joined(separator: "/") }
    }

    func testVerbsShowTheDictionaryAndMasuFormsWithTheirAccents() {
        XCTAssertEqual(notations(entry("治る", "なおる", [2], .godanR)), ["治る なおꜜる", "治ります なおりまꜜす"])
        XCTAssertEqual(notations(entry("食べる", "たべる", [2], .ichidan)), ["食べる たべꜜる", "食べます たべまꜜす"])
    }

    func testAdjectivesShowTheDictionaryAndDesuForms() {
        XCTAssertEqual(notations(entry("高い", "たかい", [2], .iAdjective)), ["高い たかꜜい", "高いです たかꜜいです"])
        XCTAssertEqual(notations(entry("静か", "しずか", [1], .naAdjective)), ["静か[な] しꜜずかな", "静かです しꜜずかです"])
    }

    func testNounsShowOneFormAndEveryAccentVariant() {
        let gakkou = entry("学校", "がっこう", [0], .noun)
        XCTAssertEqual(notations(gakkou), ["学校 がっこう"])
        let variants = entry("昨日", "きのう", [2, 0], .noun)
        XCTAssertEqual(variants.headlineForms.count, 1)
        XCTAssertEqual(variants.headlineForms[0].readings.count, 2)
    }

    func testKanaOnlyWordsAreFlagged() {
        XCTAssertEqual(entry("する", "する", [0], .suru).headlineForms.map(\.isKanaOnly), [true, true])
        XCTAssertFalse(entry("治る", "なおる", [2], .godanR).headlineForms[0].isKanaOnly)
    }

    func testEntriesWithoutAMatchingFormStillListTheHeadword() {
        let bare = WordEntry(id: 2, headword: "治る・治ります", category: .verb, forms: [])
        XCTAssertEqual(bare.headlineForms.map(\.written), ["治る", "治ります"])
        XCTAssertTrue(bare.headlineForms.allSatisfy { $0.readings.isEmpty })
    }
}
