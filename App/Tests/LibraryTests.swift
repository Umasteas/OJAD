import Foundation
import OJADKit
import SwiftData
import XCTest
@testable import OJAD

@MainActor
final class LibraryTests: XCTestCase {
    private var container: ModelContainer!
    private var transport: CountingTransport!
    private var clock: Date!

    override func setUp() async throws {
        container = try AppSchema.container(inMemory: true)
        transport = CountingTransport()
        clock = Date(timeIntervalSince1970: 1_800_000_000)
    }

    /// Online-only unless given the bundled dictionary (`BundledDictionary.shared`).
    private func makeLibrary(dictionary: BundledDictionary = .onlineOnly) -> Library {
        let transport = transport!
        return Library(
            context: container.mainContext,
            dictionary: dictionary,
            ojad: OJADClient(transport: { try await transport.respond(to: $0) }),
            tatoeba: TatoebaClient(transport: { try await transport.respond(to: $0) }),
            now: { [unowned self] in self.clock }
        )
    }

    private func history() throws -> [HistoryEntry] {
        try container.mainContext.fetch(FetchDescriptor<HistoryEntry>(sortBy: [SortDescriptor(\.lastSearchedAt, order: .reverse)]))
    }

    func testRepeatedSearchIsServedFromCacheAndHistoryKeepsOneEntryPerQuery() async throws {
        let library = makeLibrary()

        let first = try await library.search("学校")
        clock = clock.addingTimeInterval(60)
        let second = try await library.search(" 学校 ")

        XCTAssertEqual(first, second)
        XCTAssertEqual(first.first?.headword, "学校")
        XCTAssertEqual(transport.count, 1)
        let entries = try history()
        XCTAssertEqual(entries.map(\.query), ["学校"])
        XCTAssertEqual(entries.first?.lastSearchedAt, clock)
        XCTAssertEqual(entries.first?.summary, "学校　がっこう")
    }

    func testRefreshBypassesTheCache() async throws {
        let library = makeLibrary()
        _ = try await library.searchOnline("学校")
        _ = try await library.searchOnline("学校", refresh: true)
        XCTAssertEqual(transport.count, 2)
    }

    func testEmptyResultsAreNotCachedButStillRecorded() async throws {
        transport.html = OJADPage.noResult
        let library = makeLibrary()

        _ = try await library.search("がっこ")
        _ = try await library.search("がっこ")

        XCTAssertEqual(transport.count, 2)
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

    func testClearHistoryRemovesEveryEntry() async throws {
        let library = makeLibrary()
        _ = try await library.search("学校")
        try library.clearHistory()
        XCTAssertEqual(try history().count, 0)
    }

    func testExampleSentencesSearchTheLemmaWithoutOJADNotation() async throws {
        let library = makeLibrary()
        let entry = WordEntry(id: 1, headword: "静か[な]・静かです", category: .naAdjective, forms: [])
        transport.json = #"{"data":[{"id":7,"text":"静かな部屋ですね。","owner":"x","license":"CC BY 2.0 FR","translations":[]}],"paging":{}}"#

        let sentences = try await library.onlineExamples(for: entry)
        _ = try await library.onlineExamples(for: entry)

        XCTAssertEqual(sentences.map(\.text), ["静かな部屋ですね。"])
        XCTAssertEqual(transport.count, 1)
        let q = transport.lastURL.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false) }?
            .queryItems?.first { $0.name == "q" }?.value
        XCTAssertEqual(q, "\"静か\"")
    }

    // MARK: Offline

    private func offlineLibrary() throws -> Library {
        XCTAssertEqual(BundledDictionary.shared.diagnostics.state, .loaded, "Dictionary.sqlite missing from the app bundle")
        return makeLibrary(dictionary: .shared)
    }

    func testOfflineSearchNeedsNoNetworkAndIsRecorded() async throws {
        let library = try offlineLibrary()
        let entries = try await library.search("食べる")

        XCTAssertEqual(entries.first?.headword, "食べる・食べます")
        XCTAssertEqual(entries.first?.forms.first { $0.kind == "te" }?.readings.map(\.notation), ["たꜜべて"])
        XCTAssertTrue(entries.first?.isOffline ?? false)
        XCTAssertEqual(try history().first?.summary, "食べる・食べます　たべꜜる")
        XCTAssertEqual(transport.count, 0)
    }

    func testSuggestionsAcceptRomaji() async throws {
        let library = try offlineLibrary()
        let suggestions = await library.suggestions(for: "tabe")
        XCTAssertEqual(suggestions.first?.written, "食べる")
        XCTAssertLessThanOrEqual(suggestions.count, 10)
        XCTAssertEqual(library.diagnostics.lastSuggestion?.query, "tabe")
        XCTAssertEqual(library.diagnostics.lastSuggestion?.results, suggestions.count)
        let empty = await library.suggestions(for: "")
        XCTAssertTrue(empty.isEmpty)
    }

    func testTheBundledDictionaryIsInTheAppAndOpens() {
        let bundled = BundledDictionary.shared
        XCTAssertNotNil(Bundle.main.url(forResource: "Dictionary", withExtension: "sqlite"))
        XCTAssertNotNil(bundled.dictionary)
        XCTAssertEqual(bundled.diagnostics.state, .loaded)
        XCTAssertGreaterThan(bundled.diagnostics.words, 100_000)
        XCTAssertGreaterThan(bundled.diagnostics.fileSize, 10_000_000)
        XCTAssertEqual(bundled.dictionary?.metadata["schema"], "2")
    }

    func testAMissingOrBrokenDictionaryIsReportedAndSearchGoesOnline() async throws {
        XCTAssertEqual(BundledDictionary.open(nil).diagnostics.state, .missing)
        let broken = FileManager.default.temporaryDirectory.appendingPathComponent("broken-\(UUID()).sqlite")
        try Data(repeating: 1, count: 4096).write(to: broken)
        defer { try? FileManager.default.removeItem(at: broken) }
        guard case .failed = BundledDictionary.open(broken).diagnostics.state else {
            return XCTFail("A broken file should report failed")
        }

        let library = makeLibrary(dictionary: .onlineOnly)
        let suggestions = await library.suggestions(for: "tabe")
        XCTAssertTrue(suggestions.isEmpty)
        _ = try await library.search("学校")
        XCTAssertEqual(transport.count, 1)
    }

    /// Perceived latency budget: typing and opening a word should feel instant.
    func testLookupsStayFastOnTheFullDictionary() async throws {
        let library = try offlineLibrary()
        BundledDictionary.shared.dictionary?.warmUp()
        let clock = ContinuousClock()
        for typed in ["あ", "か", "し", "s", "tabe", "たb", "食", "ta be"] {
            let start = clock.now
            let words = await library.suggestions(for: typed)
            let elapsed = start.duration(to: clock.now)
            XCTAssertFalse(words.isEmpty, typed)
            XCTAssertLessThan(elapsed, .milliseconds(50), "\(typed): \(elapsed)")
        }
        let start = clock.now
        let entries = try await library.search("食べる")
        let details = await library.offlineDetails(for: try XCTUnwrap(entries.first))
        let elapsed = start.duration(to: clock.now)
        XCTAssertFalse(details.examples.isEmpty)
        XCTAssertEqual(details.word?.gloss, "to eat")
        XCTAssertLessThan(elapsed, .milliseconds(50), "search + details: \(elapsed)")
    }

    func testFavoritesSavedFromOJADStayFavoritesOffline() async throws {
        let online = try await makeLibrary().searchOnline("学校")
        let saved = try XCTUnwrap(online.first)
        try makeLibrary().toggleFavorite(saved)

        let library = try offlineLibrary()
        let results = try await library.search("学校")
        let offline = try XCTUnwrap(results.first { $0.headword == "学校" })
        XCTAssertNotEqual(offline.id, saved.id)
        XCTAssertTrue(library.isFavorite(offline))

        try library.toggleFavorite(offline)
        XCTAssertEqual(try container.mainContext.fetch(FetchDescriptor<FavoriteWord>()).count, 0)
    }

    func testOfflineExamplesForOfflineAndSavedOJADEntries() async throws {
        let library = try offlineLibrary()
        let results = try await library.search("食べる")
        let offline = try XCTUnwrap(results.first)
        let examples = await library.offlineDetails(for: offline).examples
        XCTAssertFalse(examples.isEmpty)

        let fromOJAD = WordEntry(id: 1238, headword: offline.headword, category: .verb, forms: offline.forms)
        let fromOJADExamples = await library.offlineDetails(for: fromOJAD).examples
        XCTAssertEqual(fromOJADExamples, examples)
        XCTAssertEqual(transport.count, 0)
    }
}

/// Answers OJAD requests with `html` and Tatoeba requests with `json`.
private final class CountingTransport: @unchecked Sendable {
    var html = OJADPage.gakkou
    var json = #"{"data":[],"paging":{}}"#
    private(set) var count = 0
    private(set) var lastURL: URL?

    func respond(to request: URLRequest) async throws -> (Data, URLResponse) {
        count += 1
        lastURL = request.url
        let body = request.url?.host == "api.tatoeba.org" ? json : html
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        return (Data(body.utf8), response)
    }
}

private enum OJADPage {
    static let gakkou = """
    <div id="search_result"><table id="word_table">
    <thead><tr><th class="midashi"><p>名詞</p></th><th class="jisho katsuyo_jisho_js"><p>辞書形</p></th></tr></thead>
    <tbody><tr id="word_4867">
    <td class="midashi"><p class="midashi_word">学校</p></td>
    <td class="katsuyo katsuyo_jisho_js"><div class="katsuyo_proc">
    <script type="text/javascript">set_accent_curve_word('katsuyo_48785',4,[0,1,1,1],1);</script>
    <p><span class="katsuyo_accent"><span class="accented_word">\
    <span class="mola_-4"><span class="inner"><span class="char">が</span></span></span>\
    <span class=" accent_plain mola_-3"><span class="inner"><span class="char">っ</span></span></span>\
    <span class=" accent_plain mola_-2"><span class="inner"><span class="char">こ</span></span></span>\
    <span class=" accent_plain mola_-1"><span class="inner"><span class="char">う</span></span></span>\
    </span></span></p></div></td>
    </tr></tbody></table></div>
    """

    static let noResult = #"<div id="search_result"><div id="search_result_message"></div></div>"#
}
