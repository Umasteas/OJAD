import XCTest
@testable import OJADKit

final class KanaTests: XCTestCase {
    func testSearchKeyFoldsWidthCaseAndKatakana() {
        XCTAssertEqual(Kana.searchKey("コーヒー"), "こーひー")
        XCTAssertEqual(Kana.searchKey("ｺｰﾋｰ"), "こーひー")
        XCTAssertEqual(Kana.searchKey("ＡＢＣ"), "abc")
        XCTAssertEqual(Kana.searchKey("ﾀﾍﾞｶﾞｯｺｳ"), "たべがっこう")
        XCTAssertEqual(Kana.searchKey("食べる"), "食べる")
    }

    func testMoraeJoinSmallKana() {
        XCTAssertEqual(Kana.morae("きょうと"), ["きょ", "う", "と"])
        XCTAssertEqual(Kana.morae("がっこう"), ["が", "っ", "こ", "う"])
        XCTAssertEqual(Kana.morae("シャツ"), ["シャ", "ツ"])
    }

    func testRomajiToHiragana() {
        XCTAssertEqual(Kana.hiragana(fromRomaji: "tabe")?.kana, "たべ")
        XCTAssertEqual(Kana.hiragana(fromRomaji: "gakkou")?.kana, "がっこう")
        XCTAssertEqual(Kana.hiragana(fromRomaji: "kyou")?.kana, "きょう")
        XCTAssertEqual(Kana.hiragana(fromRomaji: "shinbunn")?.kana, "しんぶん")
        XCTAssertEqual(Kana.hiragana(fromRomaji: "sinnbunn")?.kana, "しんぶん")
        XCTAssertEqual(Kana.hiragana(fromRomaji: "kon'ya")?.kana, "こんや")
        XCTAssertEqual(Kana.hiragana(fromRomaji: "chotto")?.kana, "ちょっと")
        XCTAssertEqual(Kana.hiragana(fromRomaji: "ko-hi-")?.kana, "こーひー")
        XCTAssertEqual(Kana.hiragana(fromRomaji: "Tsukue")?.kana, "つくえ")
    }

    func testIncompleteRomajiKeepsThePendingPart() throws {
        let tab = try XCTUnwrap(Kana.hiragana(fromRomaji: "tab"))
        XCTAssertEqual(tab.kana, "た")
        XCTAssertEqual(tab.pending, "b")
        XCTAssertEqual(Kana.hiragana(fromRomaji: "hon")?.kana, "ほ")
        XCTAssertEqual(Kana.hiragana(fromRomaji: "hon")?.pending, "n")
    }

    func testNonRomajiIsRejected() {
        XCTAssertNil(Kana.hiragana(fromRomaji: "食べる"))
        XCTAssertNil(Kana.hiragana(fromRomaji: ""))
        XCTAssertNil(Kana.hiragana(fromRomaji: "abc1"))
    }
}
