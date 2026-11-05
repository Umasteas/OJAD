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

/// The bundled, read-only pitch-accent dictionary (Kanjium accents, JMdict words and
/// senses, Tatoeba and KFTT examples).
public final class OfflineDictionary: @unchecked Sendable {
    private let database: SQLiteDatabase
    private let lock = NSLock()
    public let metadata: [String: String]
    /// Busy prefixes have their top words precomputed (schema 2+); 0 when absent.
    private let precomputedTop: Int

    public init(url: URL) throws {
        database = try SQLiteDatabase(readOnly: url)
        metadata = Dictionary(
            try database.query("SELECT key, value FROM meta") { ($0.text(0) ?? "", $0.text(1) ?? "") },
            uniquingKeysWith: { first, _ in first }
        )
        precomputedTop = metadata["prefix_top"].flatMap(Int.init) ?? 0
    }

    public var wordCount: Int { metadata["words"].flatMap(Int.init) ?? 0 }

    /// Words starting with what the user typed (kanji, kana, romaji, or text an IME is
    /// still composing), exact matches first, then by frequency.
    public func suggestions(for text: String, limit: Int = 10) -> [DictionaryWord] {
        suggestions(for: text, limit: limit, precomputed: true)
    }

    /// `precomputed: false` runs the same query without the precomputed table, to check the two agree.
    func suggestions(for text: String, limit: Int, precomputed: Bool) -> [DictionaryWord] {
        // Only the typed text itself ranks exact matches first; `たb` shouldn't put 度 (たび) above 食べる.
        let typed = Set(Self.keys(for: text))
        var found: [DictionaryWord] = []
        for keys in Self.suggestionKeys(for: text) where found.isEmpty {
            found = search(keys: keys, prefix: true, limit: limit, exactKeys: typed, precomputed: precomputed)
        }
        return found
    }

    /// Words whose spelling or reading is exactly `text`; if there are none, words
    /// starting with it.
    public func lookup(_ text: String, limit: Int = 30) -> [DictionaryWord] {
        let keys = Self.keys(for: text)
        let exact = search(keys: keys, prefix: false, limit: limit, exactKeys: Set(keys))
        return exact.isEmpty ? suggestions(for: text, limit: limit) : exact
    }

    public func word(id: Int) -> DictionaryWord? {
        locked {
            try? database.query("SELECT \(Self.columns) FROM words w WHERE w.id = ?", [.int(id)], Self.word).first
        }
    }

    public func word(for entry: WordEntry) -> DictionaryWord? {
        entry.isOffline ? word(id: entry.id - WordEntry.offlineIDBase) : nil
    }

    /// The word's JMdict senses that apply to its spelling and reading, in JMdict order.
    public func senses(for word: DictionaryWord) -> [WordSense] {
        let rows = locked {
            try? database.query(
                "SELECT number, gloss FROM senses WHERE word_id = ? ORDER BY number", [.int(word.id)]
            ) { WordSense(number: $0.int(0), gloss: $0.text(1) ?? "") }
        }
        return rows ?? []
    }

    /// Corpus sentences for this word (Tatoeba, KFTT), at most two per sense.
    public func examples(for word: DictionaryWord) -> [ExampleSentence] {
        let rows = locked {
            try? database.query(
                """
                SELECT s.id, s.japanese, s.english, s.chinese, e.sense, e.basis
                FROM examples e JOIN sentences s ON s.id = e.sentence_id
                WHERE e.word_id = ? ORDER BY e.position
                """,
                [.int(word.id)]
            ) { row in
                ExampleSentence(
                    id: row.int(0), japanese: row.text(1) ?? "", english: row.text(2), chinese: row.text(3),
                    sense: row.isNull(4) ? nil : row.int(4),
                    basis: ExampleSentence.Basis(rawValue: row.text(5) ?? "") ?? .unassigned
                )
            }
        }
        return rows ?? []
    }

    /// Reads the whole key index and the busiest prefixes once, so the first real
    /// query doesn't wait for storage. Safe to call from any thread.
    public func warmUp() {
        locked {
            _ = try? database.query("SELECT count(*) FROM keys") { $0.int(0) }
            _ = try? database.query("SELECT count(*) FROM words") { $0.int(0) }
        }
        _ = suggestions(for: "あ")
    }

    // MARK: Query

    private static let columns = "w.id, w.written, w.reading, w.accents, w.class, w.rank, w.gloss"

    /// Spellings the typed text may stand for: the text itself (also without the
    /// spaces a pinyin IME puts between syllables) and its hiragana if it's romaji.
    static func keys(for text: String) -> [String] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        let compact = trimmed.filter { !$0.isWhitespace }
        var keys = [Kana.searchKey(trimmed), Kana.searchKey(compact)]
        if let romaji = Kana.hiragana(fromRomaji: compact) {
            // A final `n` is usually ん (`shinbun`), but may start the next syllable.
            if romaji.pending == "n" { keys.append(romaji.kana + "ん") }
            if romaji.pending.isEmpty, !romaji.kana.isEmpty { keys.append(romaji.kana) }
        }
        return unique(keys)
    }

    /// Key groups to try in order until one has matches. An unfinished romaji syllable
    /// expands to the kana it can still become (`tab` → たば, たび, たぶ, たべ, たぼ…),
    /// and only if none of those match falls back to the finished part (`た`).
    static func suggestionKeys(for text: String) -> [[String]] {
        var groups = [keys(for: text)]
        let compact = text.filter { !$0.isWhitespace }
        if let romaji = Kana.hiragana(fromRomaji: compact), !romaji.pending.isEmpty {
            groups[0] += Kana.completions(ofPending: romaji.pending).map { romaji.kana + $0 }
            if !romaji.kana.isEmpty { groups.append([romaji.kana]) }
        }
        return groups.map(unique).filter { !$0.isEmpty }
    }

    private static func unique(_ keys: [String]) -> [String] {
        var seen = Set<String>()
        return keys.filter { seen.insert($0).inserted }
    }

    private static let exactSQL = """
        SELECT \(columns), 1 FROM keys k JOIN words w ON w.id = k.word_id
        WHERE k.key = ?1 ORDER BY w.rank DESC, w.id LIMIT ?3
        """

    private static let prefixSQL = """
        SELECT \(columns), MAX(k.key = ?1) AS exact
        FROM keys k JOIN words w ON w.id = k.word_id
        WHERE k.key >= ?1 AND k.key < ?2
        GROUP BY w.id
        ORDER BY exact DESC, w.rank DESC, w.id
        LIMIT ?3
        """

    private static let precomputedSQL = """
        SELECT \(columns), p.exact FROM prefixes p JOIN words w ON w.id = p.word_id
        WHERE p.prefix = ?1 ORDER BY p.position LIMIT ?3
        """

    private func search(
        keys: [String], prefix: Bool, limit: Int, exactKeys: Set<String>, precomputed: Bool = true
    ) -> [DictionaryWord] {
        guard !keys.isEmpty, limit > 0 else { return [] }
        var found: [(word: DictionaryWord, exact: Bool)] = []
        locked {
            for key in keys {
                let values: [SQLiteDatabase.Value] = [.text(key), .text(key + "\u{10FFFF}"), .int(limit)]
                func rows(_ sql: String) -> [(DictionaryWord, Bool)] {
                    (try? database.query(sql, values) { row in (Self.word(row), row.int(7) == 1) }) ?? []
                }
                var matches: [(DictionaryWord, Bool)] = []
                if !prefix {
                    matches = rows(Self.exactSQL)
                } else {
                    // Prefixes without precomputed rows match few keys, so scanning them is cheap.
                    if precomputed, limit <= precomputedTop { matches = rows(Self.precomputedSQL) }
                    if matches.isEmpty { matches = rows(Self.prefixSQL) }
                }
                let countsExact = exactKeys.contains(key)
                for (word, exact) in matches where !found.contains(where: { $0.word.id == word.id }) {
                    found.append((word, exact && countsExact))
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
