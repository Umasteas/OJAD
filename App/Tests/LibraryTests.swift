import Foundation
import OJADKit
import SwiftData
import XCTest
@testable import OJAD

@MainActor
final class LibraryTests: XCTestCase {
    private var container: ModelContainer!
    private var clock: Date!

    override func setUp() async throws {
        container = try AppSchema.container(inMemory: true)
        clock = Date(timeIntervalSince1970: 1_800_000_000)
    }

    /// Uses the dictionary bundled in the app (`BundledDictionary.shared`) unless told otherwise.
    private func makeLibrary(dictionary: BundledDictionary = .shared) -> Library {
        Library(context: container.mainContext, dictionary: dictionary, now: { [unowned self] in self.clock })
    }

    private func history() throws -> [HistoryEntry] {
        try container.mainContext.fetch(FetchDescriptor<HistoryEntry>(sortBy: [SortDescriptor(\.lastSearchedAt, order: .reverse)]))
    }

    func testHistoryKeepsOneEntryPerQuery() async throws {
        let library = makeLibrary()

        let first = try await library.search("学校")
        clock = clock.addingTimeInterval(60)
        let second = try await library.search(" 学校 ")

        XCTAssertEqual(first, second)
        XCTAssertEqual(first.first?.headword, "学校")
        let entries = try history()
        XCTAssertEqual(entries.map(\.query), ["学校"])
        XCTAssertEqual(entries.first?.lastSearchedAt, clock)
        XCTAssertEqual(entries.first?.summary, "学校　がっこう")
    }

    func testSearchesWithoutResultsAreStillRecorded() async throws {
        let library = makeLibrary()
        let entries = try await library.search("zzqqxx")
        XCTAssertTrue(entries.isEmpty)
        XCTAssertEqual(try history().map(\.summary), [""])
    }

    func testFavoriteToggleSurvivesANewLibraryOnTheSameStore() async throws {
        let results = try await makeLibrary().search("学校")
        let entry = try XCTUnwrap(results.first)

        try makeLibrary().toggleFavorite(entry)
        XCTAssertTrue(makeLibrary().isFavorite(entry))
        let stored = try container.mainContext.fetch(FetchDescriptor<FavoriteWord>())
        XCTAssertEqual(stored.map(\.reading), ["がっこう"])
        XCTAssertEqual(stored.first?.entry, entry)

        try makeLibrary().toggleFavorite(entry)
        XCTAssertFalse(makeLibrary().isFavorite(entry))
    }

    func testRemovingOneHistoryEntryKeepsTheOthersAndFavorites() async throws {
        let library = makeLibrary()
        let entries = try await library.search("学校")
        try library.toggleFavorite(try XCTUnwrap(entries.first))
        clock = clock.addingTimeInterval(60)
        _ = try await library.search("がっこ")

        let newest = try XCTUnwrap(try history().first)
        XCTAssertEqual(newest.query, "がっこ")
        try library.removeHistory(newest)

        XCTAssertEqual(try history().map(\.query), ["学校"])
        XCTAssertEqual(try container.mainContext.fetch(FetchDescriptor<FavoriteWord>()).count, 1)
    }

    func testClearHistoryKeepsFavorites() async throws {
        let library = makeLibrary()
        let entries = try await library.search("学校")
        try library.toggleFavorite(try XCTUnwrap(entries.first))
        try library.clearHistory()
        XCTAssertEqual(try history().count, 0)
        XCTAssertEqual(try container.mainContext.fetch(FetchDescriptor<FavoriteWord>()).count, 1)
    }

    func testClearHistoryRemovesEveryEntry() async throws {
        let library = makeLibrary()
        _ = try await library.search("学校")
        try library.clearHistory()
        XCTAssertEqual(try history().count, 0)
    }

    // MARK: Offline

    private func offlineLibrary() throws -> Library {
        XCTAssertEqual(BundledDictionary.shared.diagnostics.state, .loaded, "Dictionary.sqlite missing from the app bundle")
        return makeLibrary()
    }

    func testOfflineSearchIsRecorded() async throws {
        let library = try offlineLibrary()
        let entries = try await library.search("食べる")

        XCTAssertEqual(entries.first?.headword, "食べる・食べます")
        XCTAssertEqual(entries.first?.forms.first { $0.kind == "te" }?.readings.map(\.notation), ["たꜜべて"])
        XCTAssertTrue(entries.first?.isOffline ?? false)
        XCTAssertEqual(try history().first?.summary, "食べる・食べます　たべꜜる")
    }

    func testSuggestionsAcceptRomaji() async throws {
        let library = try offlineLibrary()
        let suggestions = await library.suggestions(for: "tabe")
        XCTAssertEqual(suggestions.first?.word.written, "食べる")
        XCTAssertLessThanOrEqual(suggestions.count, 12)
        XCTAssertEqual(library.diagnostics.lastSuggestion?.query, "tabe")
        XCTAssertEqual(library.diagnostics.lastSuggestion?.results, suggestions.count)
        let empty = await library.suggestions(for: "")
        XCTAssertTrue(empty.isEmpty)
    }

    func testChineseAndEnglishFindTheJapaneseWord() async throws {
        let library = try offlineLibrary()
        for typed in ["吃", "eat", "To eat"] {
            let suggestions = await library.suggestions(for: typed)
            guard case .meaning(let match)? = suggestions.first else {
                return XCTFail("\(typed): \(suggestions.map(\.word.written))")
            }
            XCTAssertEqual(match.word.written, "食べる", typed)
            XCTAssertFalse(match.gloss.isEmpty, typed)
        }
        let movie = await library.suggestions(for: "電影")
        XCTAssertEqual(movie.first?.word.written, "映画")
    }

    func testTheBundledDictionaryIsInTheAppAndOpens() {
        let bundled = BundledDictionary.shared
        XCTAssertNotNil(Bundle.main.url(forResource: "Dictionary", withExtension: "sqlite"))
        XCTAssertNotNil(bundled.dictionary)
        XCTAssertEqual(bundled.diagnostics.state, .loaded)
        XCTAssertGreaterThan(bundled.diagnostics.words, 100_000)
        XCTAssertGreaterThan(bundled.diagnostics.fileSize, 10_000_000)
        XCTAssertEqual(bundled.dictionary?.metadata["schema"], "4")
    }

    func testAMissingOrBrokenDictionaryIsReportedAndSearchSaysSo() async throws {
        XCTAssertEqual(BundledDictionary.open(nil).diagnostics.state, .missing)
        let broken = FileManager.default.temporaryDirectory.appendingPathComponent("broken-\(UUID()).sqlite")
        try Data(repeating: 1, count: 4096).write(to: broken)
        defer { try? FileManager.default.removeItem(at: broken) }
        guard case .failed = BundledDictionary.open(broken).diagnostics.state else {
            return XCTFail("A broken file should report failed")
        }

        let library = makeLibrary(dictionary: .missing)
        let suggestions = await library.suggestions(for: "tabe")
        XCTAssertTrue(suggestions.isEmpty)
        do {
            _ = try await library.search("学校")
            XCTFail("Search without a dictionary should throw")
        } catch {
            XCTAssertTrue(error is DictionaryUnavailable)
            XCTAssertTrue(error.userMessage.contains("词典状态"))
        }
    }

    /// Perceived latency budget: typing and opening a word should feel instant.
    func testLookupsStayFastOnTheFullDictionary() async throws {
        let library = try offlineLibrary()
        BundledDictionary.shared.dictionary?.warmUp()
        let clock = ContinuousClock()
        for typed in ["あ", "か", "し", "s", "tabe", "たb", "食", "ta be", "吃", "電影", "eat", "water", "老师"] {
            let start = clock.now
            let words = await library.suggestions(for: typed)
            let elapsed = start.duration(to: clock.now)
            XCTAssertFalse(words.isEmpty, typed)
            XCTAssertLessThan(elapsed, .milliseconds(50), "\(typed): \(elapsed)")
        }
        let start = clock.now
        let entries = try await library.search("食べる")
        let details = await library.details(for: try XCTUnwrap(entries.first))
        let elapsed = start.duration(to: clock.now)
        XCTAssertFalse(details.examples.isEmpty)
        XCTAssertEqual(details.word?.gloss, "to eat")
        XCTAssertLessThan(elapsed, .milliseconds(50), "search + details: \(elapsed)")
    }

    /// Favorites saved by the former online version carry OJAD's word id.
    func testFavoritesSavedFromOJADStayFavorites() async throws {
        let found = try await makeLibrary().search("学校")
        let recorded = try XCTUnwrap(found.first)
        let saved = WordEntry(id: 4867, headword: recorded.headword, category: recorded.category, forms: recorded.forms)
        try makeLibrary().toggleFavorite(saved)

        let library = try offlineLibrary()
        let results = try await library.search("学校")
        let offline = try XCTUnwrap(results.first { $0.headword == "学校" })
        XCTAssertNotEqual(offline.id, saved.id)
        XCTAssertTrue(library.isFavorite(offline))

        try library.toggleFavorite(offline)
        XCTAssertEqual(try container.mainContext.fetch(FetchDescriptor<FavoriteWord>()).count, 0)
    }

    func testExamplesAreGroupedBySenseForOfflineAndSavedOJADEntries() async throws {
        let library = try offlineLibrary()
        let results = try await library.search("食べる")
        let offline = try XCTUnwrap(results.first)
        let details = await library.details(for: offline)
        XCTAssertEqual(details.senses.first?.gloss, "to eat")
        XCTAssertGreaterThanOrEqual(details.examples.count, 2)
        let groups = SenseExamples.group(details.examples, senses: details.senses)
        XCTAssertFalse(groups.first?.examples.isEmpty ?? true, "sense 1 of 食べる has examples")

        let fromOJAD = WordEntry(id: 1238, headword: offline.headword, category: .verb, forms: offline.forms)
        let fromOJADDetails = await library.details(for: fromOJAD)
        XCTAssertEqual(fromOJADDetails.examples, details.examples)
        XCTAssertEqual(fromOJADDetails.senses, details.senses)
    }
}
