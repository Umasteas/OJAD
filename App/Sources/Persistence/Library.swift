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
    @ObservationIgnored private let context: ModelContext
    @ObservationIgnored private let ojad: OJADClient
    @ObservationIgnored private let tatoeba: TatoebaClient
    @ObservationIgnored private let now: () -> Date

    init(
        context: ModelContext,
        dictionary: OfflineDictionary? = .bundled,
        ojad: OJADClient = OJADClient(),
        tatoeba: TatoebaClient = TatoebaClient(),
        now: @escaping () -> Date = Date.init
    ) {
        self.context = context
        self.dictionary = dictionary
        self.ojad = ojad
        self.tatoeba = tatoeba
        self.now = now
    }

    // MARK: Lookups

    func suggestions(for text: String, limit: Int = 10) -> [DictionaryWord] {
        dictionary?.suggestions(for: text, limit: limit) ?? []
    }

    /// Looks the query up offline (OJAD if the dictionary is missing) and records it in history.
    func search(_ query: String) async throws -> [WordEntry] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let dictionary else { return try await searchOnline(query) }
        let entries = dictionary.lookup(query).map(\.entry)
        recordHistory(query: query, entries: entries)
        return entries
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

    /// The offline dictionary row behind an entry, also for entries saved from OJAD.
    func dictionaryWord(for entry: WordEntry) -> DictionaryWord? {
        guard let dictionary else { return nil }
        if entry.isOffline { return dictionary.word(for: entry) }
        let reading = entry.dictionaryReading?.notation
        return dictionary.lookup(entry.exampleSearchTerm).first {
            $0.entry.headword == entry.headword && $0.entry.dictionaryReading?.notation == reading
        }
    }

    func offlineExamples(for entry: WordEntry) -> [ExampleSentence] {
        guard let dictionary, let word = dictionaryWord(for: entry) else { return [] }
        return dictionary.examples(for: word)
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

extension OfflineDictionary {
    /// `Dictionary.sqlite`, generated by `scripts/dictionary/build.py` at build time.
    static let bundled: OfflineDictionary? = Bundle.main
        .url(forResource: "Dictionary", withExtension: "sqlite")
        .flatMap { try? OfflineDictionary(url: $0) }
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
