import Foundation

/// One row of the bundled dictionary (`scripts/dictionary/build.py`).
public struct DictionaryWord: Sendable, Hashable, Identifiable {
    public let id: Int
    public let written: String
    public let reading: String
    /// Accent nuclei of the dictionary form, most common first; 0 = 平板.
    public let accents: [Int]
    public let wordClass: WordClass
    /// Higher is more frequent.
    public let rank: Int
    /// Short English gloss from JMdict.
    public let gloss: String?

    public init(id: Int, written: String, reading: String, accents: [Int], wordClass: WordClass, rank: Int, gloss: String?) {
        self.id = id
        self.written = written
        self.reading = reading
        self.accents = accents
        self.wordClass = wordClass
        self.rank = rank
        self.gloss = gloss
    }

    /// The reading with `ꜜ` after each accent nucleus, one per accent (`たべꜜる`, `いꜜい・いい`).
    public var notation: String {
        accents.map { Conjugator.pattern(reading, nucleus: $0).notation }.joined(separator: "・")
    }

    /// The OJAD-shaped entry: headword and conjugation table derived offline.
    public var entry: WordEntry {
        WordEntry(
            id: WordEntry.offlineIDBase + id,
            headword: Conjugator.headword(written: written, reading: reading, wordClass: wordClass),
            category: wordClass.category,
            forms: Conjugator.forms(reading: reading, accents: accents, wordClass: wordClass)
        )
    }
}

extension WordEntry {
    /// Offline entries use ids above every OJAD word id, so both can share storage.
    public static let offlineIDBase = 1_000_000

    public var isOffline: Bool { id >= Self.offlineIDBase }
}

/// The bundled, read-only pitch-accent dictionary (Kanjium accents + JMdict words,
/// glosses and Tatoeba examples).
public final class OfflineDictionary: @unchecked Sendable {
    private let database: SQLiteDatabase
    private let lock = NSLock()
    public let metadata: [String: String]

    public init(url: URL) throws {
        database = try SQLiteDatabase(readOnly: url)
        metadata = Dictionary(
            try database.query("SELECT key, value FROM meta") { ($0.text(0) ?? "", $0.text(1) ?? "") },
            uniquingKeysWith: { first, _ in first }
        )
    }

    /// Words starting with what the user typed (kanji, kana or romaji), exact matches
    /// first, then by frequency.
    public func suggestions(for text: String, limit: Int = 10) -> [DictionaryWord] {
        search(keys: Self.keys(for: text), prefix: true, limit: limit)
    }

    /// Words whose spelling or reading is exactly `text`; if there are none, words
    /// starting with it.
    public func lookup(_ text: String, limit: Int = 30) -> [DictionaryWord] {
        let keys = Self.keys(for: text)
        let exact = search(keys: keys, prefix: false, limit: limit)
        return exact.isEmpty ? search(keys: keys, prefix: true, limit: limit) : exact
    }

    public func word(id: Int) -> DictionaryWord? {
        locked {
            try? database.query("SELECT \(Self.columns) FROM words w WHERE w.id = ?", [.int(id)], Self.word).first
        }
    }

    public func word(for entry: WordEntry) -> DictionaryWord? {
        entry.isOffline ? word(id: entry.id - WordEntry.offlineIDBase) : nil
    }

    /// Tatoeba sentences JMdict lists for this word, with their English translation.
    public func examples(for word: DictionaryWord) -> [ExampleSentence] {
        let rows = locked {
            try? database.query(
                "SELECT tatoeba_id, japanese, english FROM examples WHERE word_id = ? ORDER BY position",
                [.int(word.id)]
            ) { row in
                ExampleSentence(
                    id: row.int(0), text: row.text(1) ?? "", owner: nil, license: "CC BY 2.0 FR",
                    translations: row.text(2).map { [.init(id: 0, text: $0, lang: "eng", script: nil, owner: nil)] } ?? []
                )
            }
        }
        return rows ?? []
    }

    // MARK: Query

    private static let columns = "w.id, w.written, w.reading, w.accents, w.class, w.rank, w.gloss"

    /// The typed text as a dictionary key, plus its hiragana when typed as romaji.
    static func keys(for text: String) -> [String] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        var keys = [Kana.searchKey(trimmed)]
        if let romaji = Kana.hiragana(fromRomaji: trimmed) {
            // A final `n` is usually ん (`shinbun`), but may start the next syllable.
            if romaji.pending == "n" { keys.append(romaji.kana + "ん") }
            if !romaji.kana.isEmpty { keys.append(romaji.kana) }
        }
        var seen = Set<String>()
        return keys.filter { seen.insert($0).inserted }
    }

    private func search(keys: [String], prefix: Bool, limit: Int) -> [DictionaryWord] {
        guard !keys.isEmpty, limit > 0 else { return [] }
        let sql = """
            SELECT \(Self.columns), MAX(k.key = ?1) AS exact
            FROM keys k JOIN words w ON w.id = k.word_id
            WHERE \(prefix ? "k.key >= ?1 AND k.key < ?2" : "k.key = ?1")
            GROUP BY w.id
            ORDER BY exact DESC, w.rank DESC, w.id
            LIMIT ?3
            """
        var found: [(word: DictionaryWord, exact: Bool)] = []
        locked {
            for key in keys {
                let rows = (try? database.query(sql, [.text(key), .text(key + "\u{10FFFF}"), .int(limit)]) { row in
                    (Self.word(row), row.int(7) == 1)
                }) ?? []
                for row in rows where !found.contains(where: { $0.word.id == row.0.id }) {
                    found.append(row)
                }
            }
        }
        return found
            .sorted { ($0.exact ? 1 : 0, $0.word.rank, -$0.word.id) > ($1.exact ? 1 : 0, $1.word.rank, -$1.word.id) }
            .prefix(limit)
            .map(\.word)
    }

    private static func word(_ row: SQLiteDatabase.Row) -> DictionaryWord {
        DictionaryWord(
            id: row.int(0),
            written: row.text(1) ?? "",
            reading: row.text(2) ?? "",
            accents: (row.text(3) ?? "0").split(separator: ",").compactMap { Int($0) },
            wordClass: WordClass(rawValue: row.text(4) ?? "") ?? .noun,
            rank: row.int(5),
            gloss: row.text(6)
        )
    }

    private func locked<T>(_ body: () throws -> T) rethrows -> T {
        lock.lock()
        defer { lock.unlock() }
        return try body()
    }
}
