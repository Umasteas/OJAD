import Foundation
import Observation
import OJADKit
import SwiftData

/// Lookups, history recording and favorite toggling. List screens read history and
/// favorites straight from the store with `@Query`.
///
/// Words come from the bundled offline dictionary. OJAD, Tatoeba and スズキクン are
/// only asked when the user taps an online action; their answers are cached.
@MainActor
@Observable
final class Library {
    @ObservationIgnored let dictionary: OfflineDictionary?
    /// Shown on the About screen so problems on the phone can be reported without logs.
    private(set) var diagnostics: DictionaryDiagnostics
    @ObservationIgnored private let context: ModelContext
    @ObservationIgnored private let ojad: OJADClient
    @ObservationIgnored private let tatoeba: TatoebaClient
    @ObservationIgnored private let now: () -> Date

    init(
        context: ModelContext,
        dictionary: BundledDictionary = .shared,
        ojad: OJADClient = OJADClient(),
        tatoeba: TatoebaClient = TatoebaClient(),
        now: @escaping () -> Date = Date.init
    ) {
        self.context = context
        self.dictionary = dictionary.dictionary
        self.diagnostics = dictionary.diagnostics
        self.ojad = ojad
        self.tatoeba = tatoeba
        self.now = now
    }

    // MARK: Lookups

    /// Runs off the main thread; callers debounce.
    func suggestions(for text: String, limit: Int = 10) async -> [DictionaryWord] {
        guard let dictionary else { return [] }
        let clock = ContinuousClock()
        let start = clock.now
        let words = await Task.detached(priority: .userInitiated) {
            dictionary.suggestions(for: text, limit: limit)
        }.value
        diagnostics.lastSuggestion = .init(query: text, duration: start.duration(to: clock.now), results: words.count)
        return words
    }

    /// Looks the query up offline (OJAD if the dictionary is missing) and records it in history.
    func search(_ query: String) async throws -> [WordEntry] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let dictionary else { return try await searchOnline(query) }
        let clock = ContinuousClock()
        let start = clock.now
        let entries = await Task.detached(priority: .userInitiated) {
            dictionary.lookup(query).map(\.entry)
        }.value
        diagnostics.lastSearch = .init(query: query, duration: start.duration(to: clock.now), results: entries.count)
        recordHistory(query: query, entries: entries)
        return entries
    }

    /// Times a fixed set of queries, for the About screen's self-test.
    func runSelfTest() async {
        guard let dictionary else { return }
        diagnostics.selfTest = await Task.detached(priority: .userInitiated) {
            let clock = ContinuousClock()
            func time(_ query: String, _ run: () -> Int) -> DictionaryDiagnostics.Timing {
                let start = clock.now
                let results = run()
                return .init(query: query, duration: start.duration(to: clock.now), results: results)
            }
            return ["あ", "tabe", "たb", "食"].map { query in time(query) { dictionary.suggestions(for: query).count } }
                + [time("食べる") { dictionary.lookup("食べる").map(\.entry).count }]
        }.value
    }

    /// Searches OJAD itself; the reference when an offline table looks wrong.
    func searchOnline(_ query: String, refresh: Bool = false) async throws -> [WordEntry] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let entries = try await cached("word:\(query)", refresh: refresh) { [ojad] in
            try await ojad.searchWord(query)
        }
        recordHistory(query: query, entries: entries)
        return entries
    }

    /// The offline dictionary row behind an entry (also for entries saved from OJAD)
    /// and its examples.
    func offlineDetails(for entry: WordEntry) async -> (word: DictionaryWord?, examples: [ExampleSentence]) {
        guard let dictionary else { return (nil, []) }
        return await Task.detached(priority: .userInitiated) {
            let word = Self.dictionaryWord(for: entry, in: dictionary)
            return (word, word.map { dictionary.examples(for: $0) } ?? [])
        }.value
    }

    nonisolated static func dictionaryWord(for entry: WordEntry, in dictionary: OfflineDictionary) -> DictionaryWord? {
        if entry.isOffline { return dictionary.word(for: entry) }
        let reading = entry.dictionaryReading?.notation
        return dictionary.lookup(entry.exampleSearchTerm).first {
            $0.entry.headword == entry.headword && $0.entry.dictionaryReading?.notation == reading
        }
    }

    /// Tatoeba's live search, which also has Chinese translations.
    func onlineExamples(for entry: WordEntry, refresh: Bool = false) async throws -> [ExampleSentence] {
        let term = entry.exampleSearchTerm
        return try await cached("examples:\(term)", refresh: refresh) { [tatoeba] in
            try await tatoeba.exampleSentences(containing: term)
        }
    }

    func cachedAnalysis(of sentence: String) -> SentenceAnalysis? {
        cachedValue("phrasing:\(sentence)")
    }

    func analysis(of sentence: String, refresh: Bool = false) async throws -> SentenceAnalysis {
        try await cached("phrasing:\(sentence)", refresh: refresh) { [ojad] in
            try await ojad.analyzeSentence(sentence)
        }
    }

    func clearCache() throws {
        try context.delete(model: CachedResponse.self)
        try context.save()
    }

    // MARK: History

    func clearHistory() throws {
        try context.delete(model: HistoryEntry.self)
        try context.save()
    }

    func removeHistory(_ item: HistoryEntry) throws {
        context.delete(item)
        try context.save()
    }

    private func recordHistory(query: String, entries: [WordEntry]) {
        guard !query.isEmpty else { return }
        let summary = entries.first.map { "\($0.headword)　\($0.dictionaryReading?.notation ?? "")" } ?? ""
        let descriptor = FetchDescriptor<HistoryEntry>(predicate: #Predicate { $0.query == query })
        if let existing = try? context.fetch(descriptor).first {
            existing.lastSearchedAt = now()
            existing.summary = summary
        } else {
            context.insert(HistoryEntry(query: query, lastSearchedAt: now(), summary: summary))
        }
        try? context.save()
    }

    // MARK: Favorites

    func isFavorite(_ entry: WordEntry) -> Bool {
        favorite(for: entry) != nil
    }

    func toggleFavorite(_ entry: WordEntry) throws {
        if let existing = favorite(for: entry) {
            context.delete(existing)
        } else {
            context.insert(FavoriteWord(
                wordID: entry.id,
                headword: entry.headword,
                reading: entry.favoriteReading,
                entryData: try JSONEncoder().encode(entry),
                addedAt: now()
            ))
        }
        try context.save()
    }

    /// Favorites saved from OJAD have OJAD's word id, so offline entries match them by
    /// headword and accented reading instead.
    private func favorite(for entry: WordEntry) -> FavoriteWord? {
        let descriptor = FetchDescriptor<FavoriteWord>(predicate: FavoriteWord.matching(entry))
        return try? context.fetch(descriptor).first
    }

    // MARK: Cache

    private func cachedValue<Value: Codable>(_ key: String) -> Value? {
        let descriptor = FetchDescriptor<CachedResponse>(predicate: #Predicate { $0.key == key })
        guard let existing = try? context.fetch(descriptor).first else { return nil }
        return try? JSONDecoder().decode(Value.self, from: existing.payload)
    }

    /// Empty results are not cached, so a typo or a transient site hiccup isn't sticky.
    private func cached<Value: Codable>(
        _ key: String,
        refresh: Bool,
        fetch: () async throws -> Value
    ) async throws -> Value {
        if !refresh, let value: Value = cachedValue(key) {
            return value
        }

        let value = try await fetch()
        if let empty = value as? any Collection, empty.isEmpty {
            return value
        }
        let payload = try JSONEncoder().encode(value)
        let descriptor = FetchDescriptor<CachedResponse>(predicate: #Predicate { $0.key == key })
        if let existing = try? context.fetch(descriptor).first {
            existing.payload = payload
            existing.fetchedAt = now()
        } else {
            context.insert(CachedResponse(key: key, payload: payload, fetchedAt: now()))
        }
        try? context.save()
        return value
    }
}

/// `Dictionary.sqlite`, generated by `scripts/dictionary/build.py` at build time and
/// opened once per launch.
struct BundledDictionary: Sendable {
    let dictionary: OfflineDictionary?
    let diagnostics: DictionaryDiagnostics

    static let shared = BundledDictionary.open(Bundle.main.url(forResource: "Dictionary", withExtension: "sqlite"))

    /// Online-only, as if the app shipped without a dictionary.
    static let onlineOnly = BundledDictionary(dictionary: nil, diagnostics: DictionaryDiagnostics(state: .missing))

    static func open(_ url: URL?) -> BundledDictionary {
        guard let url else { return .onlineOnly }
        let clock = ContinuousClock()
        let start = clock.now
        do {
            let dictionary = try OfflineDictionary(url: url)
            var diagnostics = DictionaryDiagnostics(state: .loaded)
            diagnostics.words = dictionary.wordCount
            diagnostics.version = dictionary.metadata["jmdict"]
            diagnostics.fileSize = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            diagnostics.openDuration = start.duration(to: clock.now)
            // Page the index in before the first keystroke.
            Task.detached(priority: .utility) { dictionary.warmUp() }
            return BundledDictionary(dictionary: dictionary, diagnostics: diagnostics)
        } catch {
            return BundledDictionary(dictionary: nil, diagnostics: DictionaryDiagnostics(state: .failed("\(error)")))
        }
    }
}

extension Duration {
    var millisecondsText: String {
        String(format: "%.1f ms", Double(components.seconds) * 1000 + Double(components.attoseconds) / 1e15)
    }
}

struct DictionaryDiagnostics: Sendable {
    enum State: Sendable, Equatable {
        case loaded
        /// Not in the app bundle.
        case missing
        case failed(String)
    }

    struct Timing: Sendable {
        let query: String
        let duration: Duration
        let results: Int

        var milliseconds: String { duration.millisecondsText }
    }

    var state: State
    var words = 0
    var version: String?
    var fileSize = 0
    var openDuration: Duration = .zero
    var lastSuggestion: Timing?
    var lastSearch: Timing?
    var selfTest: [Timing] = []
}

extension FavoriteWord {
    static func matching(_ entry: WordEntry) -> Predicate<FavoriteWord> {
        let id = entry.id
        let headword = entry.headword
        let reading = entry.favoriteReading
        return #Predicate { $0.wordID == id || ($0.headword == headword && $0.reading == reading) }
    }
}

extension WordEntry {
    var dictionaryReading: AccentedReading? { forms.first?.readings.first }

    var favoriteReading: String { dictionaryReading?.notation ?? "" }

    /// `静か[な]` is OJAD notation, not text that appears in sentences.
    var exampleSearchTerm: String { lemma.replacingOccurrences(of: "[な]", with: "") }
}
