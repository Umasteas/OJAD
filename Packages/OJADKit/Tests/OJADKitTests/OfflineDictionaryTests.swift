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

    func testLookupBuildsTheSameEntryOJADShows() throws {
        let word = try XCTUnwrap(dictionary.lookup("食べる").first)
        XCTAssertEqual(word.reading, "たべる")
        XCTAssertEqual(word.accents, [2])
        XCTAssertEqual(word.wordClass, .ichidan)
        XCTAssertEqual(word.notation, "たべꜜる")

        let ojad = try JSONDecoder().decode([String: WordEntry].self, from: Fixture.data("ojad-recorded"))["食べる"]
        let entry = word.entry
        XCTAssertTrue(entry.isOffline)
        XCTAssertEqual(entry.headword, ojad?.headword)
        XCTAssertEqual(entry.forms, ojad?.forms)
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
        XCTAssertEqual(OfflineDictionary.keys(for: "hon"), ["hon", "ほん"])
        XCTAssertTrue(dictionary.lookup("gakkou").contains { $0.written == "学校" })
    }

    func testSuggestionsMatchKanaRomajiKatakanaAndKanji() {
        for typed in ["たべ", "tabe", "タベ", "ﾀﾍﾞ", "食べ"] {
            XCTAssertEqual(dictionary.suggestions(for: typed).first?.written, "食べる", typed)
        }
        XCTAssertTrue(dictionary.suggestions(for: "kire").contains { $0.written == "綺麗" })
        XCTAssertTrue(dictionary.suggestions(for: "奇麗").contains { $0.written == "綺麗" })
    }

    func testSuggestionsWhileAnIMEIsComposing() {
        // Pinyin keyboards separate syllables with spaces; Japanese ones show kana plus
        // the consonant being typed; full-width letters come from the Japanese keyboard.
        for typed in ["ta be", "ta'be", "ｔａｂｅ", "タベr"] {
            XCTAssertEqual(dictionary.suggestions(for: typed).first?.written, "食べる", typed)
        }
        for typed in ["たb", "tab"] {
            let composing = dictionary.suggestions(for: typed)
            XCTAssertTrue(composing.prefix(3).contains { $0.written == "食べる" }, typed)
            XCTAssertTrue(composing.allSatisfy { "ばびぶべぼ".contains(Array(Kana.searchKey($0.reading))[1]) }, "\(composing.map(\.reading))")
        }
    }

    func testPrecomputedPrefixesMatchAFullScan() {
        XCTAssertEqual(dictionary.metadata["prefix_top"], "20")
        for typed in ["あ", "い", "う", "お", "か", "た", "たべ", "き", "tabe", "s", "ka"] {
            for limit in [1, 10, 20] {
                XCTAssertEqual(dictionary.suggestions(for: typed, limit: limit), dictionary.suggestions(for: typed, limit: limit, precomputed: false), "\(typed) \(limit)")
            }
        }
    }

    func testOpeningAMissingOrBrokenFileThrows() throws {
        let missing = FileManager.default.temporaryDirectory.appendingPathComponent("missing-\(UUID()).sqlite")
        XCTAssertThrowsError(try OfflineDictionary(url: missing))
        let broken = FileManager.default.temporaryDirectory.appendingPathComponent("broken-\(UUID()).sqlite")
        try Data(repeating: 7, count: 4096).write(to: broken)
        defer { try? FileManager.default.removeItem(at: broken) }
        XCTAssertThrowsError(try OfflineDictionary(url: broken))
    }

    func testOpensFromAPathWithSpacesAndNonASCII() throws {
        let source = try XCTUnwrap(Bundle.module.url(forResource: "sample-dictionary", withExtension: "sqlite", subdirectory: "Fixtures"))
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("OJAD 重音 \(UUID()).app")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let copy = directory.appendingPathComponent("Dictionary.sqlite")
        try FileManager.default.copyItem(at: source, to: copy)
        XCTAssertEqual(try OfflineDictionary(url: copy).suggestions(for: "tabe").first?.written, "食べる")
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

    func testExamplesAreGroupedUnderTheSenseTheyIllustrate() throws {
        let word = try XCTUnwrap(dictionary.lookup("食べる").first)
        let senses = dictionary.senses(for: word)
        XCTAssertEqual(senses.map(\.number), [1, 2])
        XCTAssertEqual(senses.first?.gloss, "to eat")

        let examples = dictionary.examples(for: word)
        XCTAssertGreaterThanOrEqual(examples.count, 2)
        XCTAssertLessThanOrEqual(examples.count, 10)
        XCTAssertTrue(examples.allSatisfy { $0.english != nil && $0.source == .tatoeba })

        let groups = SenseExamples.group(examples, senses: senses)
        XCTAssertEqual(groups.map(\.sense?.number), [1, 2])
        for group in groups {
            XCTAssertFalse(group.examples.isEmpty, "sense \(group.sense?.number ?? 0)")
            XCTAssertLessThanOrEqual(group.examples.count, 2)
        }
    }

    func testGroupingKeepsSensesWithoutExamplesAndPutsUnknownSensesLast() {
        let senses = [WordSense(number: 1, gloss: "a"), WordSense(number: 2, gloss: "b")]
        let examples = [
            ExampleSentence(id: 1, japanese: "一", english: nil, chinese: nil, sense: nil, basis: .unassigned),
            ExampleSentence(id: 2, japanese: "二", english: nil, chinese: nil, sense: 1, basis: .tagged),
            ExampleSentence(id: ExampleSentence.kfttIDBase, japanese: "三", english: nil, chinese: nil, sense: 1, basis: .text),
        ]
        let groups = SenseExamples.group(examples, senses: senses)
        XCTAssertEqual(groups.map(\.sense?.number), [1, 2, nil])
        XCTAssertEqual(groups.map { $0.examples.map(\.id) }, [[2, ExampleSentence.kfttIDBase], [], [1]])
        XCTAssertEqual(examples[2].source, .kftt)
    }

    func testMetadataNamesTheSources() {
        XCTAssertEqual(dictionary.metadata["schema"], "4")
        XCTAssertEqual(dictionary.wordCount, 645)
        XCTAssertNotNil(dictionary.metadata["jmdict"])
        XCTAssertNotNil(dictionary.metadata["wiktionary"])
        XCTAssertNotNil(dictionary.metadata["cedict"])
        XCTAssertEqual(dictionary.metadata["words"].flatMap(Int.init), 645)
    }

    // MARK: Chinese

    func testSensesCarryChineseWhereASourceHasIt() throws {
        let taberu = try XCTUnwrap(dictionary.lookup("食べる").first)
        let senses = dictionary.senses(for: taberu)
        XCTAssertEqual(senses.first?.chinese, "吃；吃喝，饮食")
        XCTAssertEqual(senses.first?.chineseSource, .wiktionary)

        let mouse = try XCTUnwrap(dictionary.lookup("マウス").first)
        XCTAssertEqual(dictionary.senses(for: mouse).map(\.chinese), [nil, "鼠标，滑鼠"])

        let collision = try XCTUnwrap(dictionary.lookup("衝突").first)
        XCTAssertEqual(dictionary.senses(for: collision).first?.chineseSource, .cedict)
    }

    func testExamplesSayWhenTheChineseCameThroughEnglish() throws {
        let word = try XCTUnwrap(dictionary.lookup("治る").first)
        let examples = dictionary.examples(for: word).filter { $0.chinese != nil }
        XCTAssertEqual(examples.map(\.chineseViaEnglish).sorted { !$0 && $1 }, [false, true])

        let school = try XCTUnwrap(dictionary.lookup("学校").first)
        XCTAssertTrue(dictionary.examples(for: school).allSatisfy { $0.chinese != nil && !$0.chineseViaEnglish })
    }

    func testChineseFindsTheJapaneseWord() {
        let matches = dictionary.glossSuggestions(for: "吃")
        XCTAssertEqual(matches.first?.word.written, "食べる")
        XCTAssertEqual(matches.first?.kind, .exact)
        XCTAssertEqual(matches.first?.language, .chinese)
        XCTAssertEqual(matches.first?.gloss, "吃；吃喝，饮食")
        XCTAssertFalse(matches.first?.viaEnglish ?? true)
        // Words that reach 吃 only through CC-CEDICT's English come after every word that lists it.
        XCTAssertEqual(matches.map(\.viaEnglish), matches.map(\.viaEnglish).sorted { !$0 && $1 })
        XCTAssertTrue(matches.contains(where: \.viaEnglish))

        XCTAssertEqual(dictionary.glossSuggestions(for: "电影").first?.word.written, "映画")
    }

    func testTraditionalChineseIsFoldedToSimplified() {
        XCTAssertEqual(dictionary.simplified("電影學"), "电影学")
        XCTAssertEqual(dictionary.glossSuggestions(for: "電影").first?.word.written, "映画")
    }

    func testEnglishFindsTheJapaneseWord() {
        let eat = dictionary.glossSuggestions(for: "eat")
        XCTAssertEqual(eat.first?.word.written, "食べる")
        XCTAssertEqual(eat.first?.language, .english)
        XCTAssertEqual(eat.first?.gloss, "to eat")
        XCTAssertEqual(dictionary.glossSuggestions(for: "To Eat").map(\.word.id), eat.map(\.word.id))
        XCTAssertEqual(dictionary.glossSuggestions(for: "movie").first?.word.written, "映画")
    }

    func testGlossMatchesRankExactThenPrefixThenContains() {
        let matches = dictionary.glossSuggestions(for: "电", limit: 30).filter { !$0.viaEnglish }
        XCTAssertFalse(matches.isEmpty)
        XCTAssertEqual(matches.map(\.kind), matches.map(\.kind).sorted())
        XCTAssertTrue(matches.contains { $0.word.written == "映画" && $0.kind == .prefix })

        let film = dictionary.glossSuggestions(for: "film", limit: 30)
        XCTAssertEqual(film.filter { !$0.viaEnglish }.map(\.kind), film.filter { !$0.viaEnglish }.map(\.kind).sorted())
        XCTAssertEqual(Set(film.map(\.id)).count, film.count)

        // The word's own first meaning beats a more frequent word's twentieth.
        XCTAssertEqual(dictionary.glossSuggestions(for: "dog").first?.word.written, "犬")
        XCTAssertEqual(dictionary.glossSuggestions(for: "water").first?.word.written, "水")
    }

    func testEnglishContainsMatchesWholeWordsOnly() {
        for match in dictionary.glossSuggestions(for: "ice", limit: 50) where match.kind == .contains {
            XCTAssertNotNil(match.gloss.range(of: #"\bice\b"#, options: [.regularExpression, .caseInsensitive]), match.gloss)
        }
    }

    func testSearchSuggestionsMixSpellingsAndMeanings() {
        XCTAssertEqual(dictionary.searchSuggestions(for: "吃").first, .meaning(dictionary.glossSuggestions(for: "吃")[0]))
        XCTAssertEqual(dictionary.searchSuggestions(for: "eat").first?.word.written, "食べる")
        XCTAssertEqual(dictionary.searchSuggestions(for: "tabe").first, .word(dictionary.suggestions(for: "tabe")[0]))
        XCTAssertEqual(dictionary.searchSuggestions(for: "学校").first, .word(dictionary.lookup("学校")[0]))

        let mixed = dictionary.searchSuggestions(for: "go")
        XCTAssertLessThanOrEqual(mixed.count, 12)
        XCTAssertEqual(Set(mixed.map(\.id)).count, mixed.count)
        let firstMeaning = mixed.firstIndex { if case .meaning = $0 { true } else { false } }
        XCTAssertNotNil(firstMeaning)
        XCTAssertTrue(mixed.prefix(firstMeaning ?? 0).allSatisfy { $0.word.reading == "ご" })
    }

    func testGlossSearchIgnoresKanaAndJunk() {
        XCTAssertTrue(dictionary.glossSuggestions(for: "たべる").isEmpty)
        XCTAssertTrue(dictionary.glossSuggestions(for: "食べ").isEmpty)
        XCTAssertTrue(dictionary.glossSuggestions(for: "  ").isEmpty)
        XCTAssertTrue(dictionary.glossSuggestions(for: "%_").isEmpty)
        XCTAssertEqual(dictionary.glossSuggestions(for: "吃", limit: 3).count, 3)
    }
}
