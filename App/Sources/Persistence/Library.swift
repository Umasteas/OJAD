import Foundation
import Observation
import OJADKit
import SwiftData

/// Everything the UI asks for goes through here: cached lookups, search history
/// and favorites. Network requests happen only on a cache miss or explicit refresh.
@MainActor
@Observable
final class Library {
    @ObservationIgnored private let context: ModelContext
    @ObservationIgnored private let ojad: OJADClient
    @ObservationIgnored private let tatoeba: TatoebaClient
    @ObservationIgnored private let now: () -> Date

    init(
        context: ModelContext,
        ojad: OJADClient = OJADClient(),
        tatoeba: TatoebaClient = TatoebaClient(),
        now: @escaping () -> Date = Date.init
    ) {
        self.context = context
        self.ojad = ojad
        self.tatoeba = tatoeba
        self.now = now
    }

    // MARK: Lookups

    /// Searches OJAD and records the query in history.
    func search(_ query: String, refresh: Bool = false) async throws -> [WordEntry] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let entries = try await cached("word:\(query)", refresh: refresh) { [ojad] in
            try await ojad.searchWord(query)
        }
        recordHistory(query: query, entries: entries)
        return entries
    }

    func exampleSentences(for entry: WordEntry, refresh: Bool = false) async throws -> [ExampleSentence] {
        let term = entry.exampleSearchTerm
        return try await cached("examples:\(term)", refresh: refresh) { [tatoeba] in
            try await tatoeba.exampleSentences(containing: term)
        }
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
        favorite(id: entry.id) != nil
    }

    func toggleFavorite(_ entry: WordEntry) throws {
        if let existing = favorite(id: entry.id) {
            context.delete(existing)
        } else {
            context.insert(FavoriteWord(
                wordID: entry.id,
                headword: entry.headword,
                reading: entry.dictionaryReading?.notation ?? "",
                entryData: try JSONEncoder().encode(entry),
                addedAt: now()
            ))
        }
        try context.save()
    }

    private func favorite(id: Int) -> FavoriteWord? {
        let descriptor = FetchDescriptor<FavoriteWord>(predicate: #Predicate { $0.wordID == id })
        return try? context.fetch(descriptor).first
    }

    // MARK: Cache

    /// Empty results are not cached, so a typo or a transient site hiccup isn't sticky.
    private func cached<Value: Codable>(
        _ key: String,
        refresh: Bool,
        fetch: () async throws -> Value
    ) async throws -> Value {
        let descriptor = FetchDescriptor<CachedResponse>(predicate: #Predicate { $0.key == key })
        let existing = try? context.fetch(descriptor).first
        if !refresh, let existing, let value = try? JSONDecoder().decode(Value.self, from: existing.payload) {
            return value
        }

        let value = try await fetch()
        if let empty = value as? any Collection, empty.isEmpty {
            return value
        }
        let payload = try JSONEncoder().encode(value)
        if let existing {
            existing.payload = payload
            existing.fetchedAt = now()
        } else {
            context.insert(CachedResponse(key: key, payload: payload, fetchedAt: now()))
        }
        try? context.save()
        return value
    }
}

extension WordEntry {
    var dictionaryReading: AccentedReading? { forms.first?.readings.first }

    /// `静か[な]` is OJAD notation, not text that appears in sentences.
    var exampleSearchTerm: String { lemma.replacingOccurrences(of: "[な]", with: "") }
}
