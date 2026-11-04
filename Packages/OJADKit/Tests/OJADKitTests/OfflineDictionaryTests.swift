import XCTest
@testable import OJADKit

/// Runs against `Fixtures/sample-dictionary.sqlite`, built by `scripts/dictionary/build.py`
/// from the pinned sources filtered to `scripts/dictionary/sample-words.txt`.
final class OfflineDictionaryTests: XCTestCase {
    private var dictionary: OfflineDictionary!

    override func setUpWithError() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "sample-dictionary", withExtension: "sqlite", subdirectory: "Fixtures"))
        dictionary = try OfflineDictionary(url: url)
    }

    func testLookupBuildsTheSameEntryOJADShows() async throws {
        let word = try XCTUnwrap(dictionary.lookup("食べる").first)
        XCTAssertEqual(word.reading, "たべる")
        XCTAssertEqual(word.accents, [2])
        XCTAssertEqual(word.wordClass, .ichidan)
        XCTAssertEqual(word.notation, "たべꜜる")

        let ojad = try await OJADClient.fixture(FixtureTransport(fixture: "search-taberu")).searchWord("食べる")
        let entry = word.entry
        XCTAssertTrue(entry.isOffline)
        XCTAssertEqual(entry.headword, ojad.first?.headword)
        XCTAssertEqual(entry.forms, ojad.first?.forms)
        XCTAssertEqual(dictionary.word(for: entry), word)
    }

    func testLookupByReadingFindsEveryWordWithThatReading() {
        let words = dictionary.lookup("きる")
        XCTAssertTrue(words.contains { $0.written == "切る" })
        XCTAssertTrue(words.contains { $0.written == "着る" })
        XCTAssertTrue(words.allSatisfy { $0.reading == "きる" })
    }

    func testLookupFallsBackToPrefixMatches() {
        XCTAssertTrue(dictionary.lookup("たべ").contains { $0.written == "食べる" })
        XCTAssertTrue(dictionary.lookup("zzqqxx").isEmpty)
    }

    func testRomajiLookupTreatsAFinalNAsN() {
        XCTAssertEqual(OfflineDictionary.keys(for: "hon"), ["hon", "ほん", "ほ"])
        XCTAssertTrue(dictionary.lookup("gakkou").contains { $0.written == "学校" })
    }

    func testSuggestionsMatchKanaRomajiKatakanaAndKanji() {
        for typed in ["たべ", "tabe", "タベ", "ﾀﾍﾞ", "食べ"] {
            XCTAssertEqual(dictionary.suggestions(for: typed).first?.written, "食べる", typed)
        }
        XCTAssertTrue(dictionary.suggestions(for: "kire").contains { $0.written == "綺麗" })
        XCTAssertTrue(dictionary.suggestions(for: "奇麗").contains { $0.written == "綺麗" })
    }

    func testSuggestionsPutExactMatchesFirstThenFrequentWords() {
        let suggestions = dictionary.suggestions(for: "い", limit: 50)
        let ranks = suggestions.drop { $0.reading == "い" || $0.written == "い" }.map(\.rank)
        XCTAssertEqual(ranks, ranks.sorted(by: >))
    }

    func testSuggestionsRespectTheLimit() {
        XCTAssertEqual(dictionary.suggestions(for: "た", limit: 10).count, 10)
        XCTAssertEqual(dictionary.suggestions(for: "た", limit: 3).count, 3)
        XCTAssertTrue(dictionary.suggestions(for: "  ").isEmpty)
    }

    func testSuruVerbsAreDerivedFromNouns() throws {
        let word = try XCTUnwrap(dictionary.lookup("勉強する").first)
        XCTAssertEqual(word.wordClass, .suru)
        XCTAssertEqual(word.entry.headword, "勉強する・勉強します")
        XCTAssertEqual(word.entry.forms.first { $0.kind == "masu" }?.readings.map(\.notation), ["べんきょうしまꜜす"])
    }

    func testExamplesComeWithTheirEnglishTranslation() throws {
        let word = try XCTUnwrap(dictionary.lookup("食べる").first)
        let examples = dictionary.examples(for: word)
        XCTAssertFalse(examples.isEmpty)
        XCTAssertLessThanOrEqual(examples.count, 6)
        let first = try XCTUnwrap(examples.first)
        XCTAssertEqual(first.license, "CC BY 2.0 FR")
        XCTAssertEqual(first.preferredTranslation?.lang, "eng")
        XCTAssertTrue(first.url.absoluteString.hasPrefix("https://tatoeba.org/sentences/show/"))
    }

    func testMetadataNamesTheSources() {
        XCTAssertEqual(dictionary.metadata["schema"], "1")
        XCTAssertNotNil(dictionary.metadata["jmdict"])
        XCTAssertEqual(dictionary.metadata["words"].flatMap(Int.init), 630)
    }
}
