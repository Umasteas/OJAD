import Foundation

/// A word found by its meaning: Chinese (`吃`) or English (`eat`) typed into the search box.
public struct GlossMatch: Sendable, Hashable, Identifiable {
    public enum Language: Sendable, Hashable {
        case chinese, english
    }

    /// How the typed text matched one of the word's glosses, best first.
    public enum Kind: Int, Sendable, Hashable, Comparable {
        case exact, prefix, contains

        public static func < (lhs: Kind, rhs: Kind) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    public let word: DictionaryWord
    public let language: Language
    public let kind: Kind
    /// The gloss to show next to the word: the matched sense's Chinese, or its English.
    public let gloss: String
    /// Matched only through CC-CEDICT's English (search-only, never shown as a translation).
    public let viaEnglish: Bool

    public var id: Int { word.id }
}

extension OfflineDictionary {
    /// Words whose Chinese or English glosses match `text`: exact glosses first, then glosses
    /// starting with it, then glosses containing it, and last words that match only through
    /// CC-CEDICT's English. Within each, the word's main meaning before its others (`eat` is
    /// 食べる's first sense but やる's twentieth), then frequency. Empty for text that is
    /// neither Chinese nor English (kana goes through `suggestions(for:)`).
    public func glossSuggestions(for text: String, limit: Int = 10) -> [GlossMatch] {
        guard let (term, language) = glossTerm(for: text), limit > 0 else { return [] }
        var own: [GlossMatch] = []
        var pivots: [GlossMatch] = []
        locked {
            var kinds: [GlossMatch.Kind] = [.exact]
            if language == .chinese || term.count >= 2 { kinds.append(.prefix) }
            for kind in kinds {
                for match in indexed(term, language: language, kind: kind, limit: limit) {
                    if match.viaEnglish { pivots.append(match) } else { own.append(match) }
                }
            }
            if own.count < limit, language == .chinese || term.count >= 3 {
                own += containing(term, language: language, limit: limit)
            }
        }
        var seen = Set<Int>()
        return (own + pivots).filter { seen.insert($0.word.id).inserted }.prefix(limit).map { $0 }
    }

    /// The normalized search term, as `chinese.py` stores it: Chinese folded to Simplified,
    /// English lowercased without a leading `to`/`a`/`the`.
    func glossTerm(for text: String) -> (String, GlossMatch.Language)? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let scalars = trimmed.unicodeScalars
        if scalars.contains(where: Self.isHan), !scalars.contains(where: Self.isKana) {
            return (simplified(trimmed.filter { !$0.isWhitespace }), .chinese)
        }
        guard scalars.allSatisfy({ $0.isASCII && (CharacterSet.letters.contains($0) || " '-".unicodeScalars.contains($0)) })
        else { return nil }
        var words = trimmed.lowercased().split(separator: " ").map(String.init)
        if words.count > 1, ["to", "a", "an", "the"].contains(words[0]) { words.removeFirst() }
        return (words.joined(separator: " "), .english)
    }

    /// Traditional characters folded one by one (`學` → `学`), from OpenCC's table in the dictionary.
    func simplified(_ text: String) -> String {
        String(text.map { traditionalToSimplified[$0] ?? $0 })
    }

    static func traditionalTable(_ database: SQLiteDatabase) -> [Character: Character] {
        let pairs = (try? database.query("SELECT traditional, simplified FROM t2s") { row in
            (row.text(0) ?? "", row.text(1) ?? "")
        }) ?? []
        var table: [Character: Character] = [:]
        for (traditional, simplified) in pairs where traditional.count == 1 && simplified.count == 1 {
            table[traditional.first!] = simplified.first!
        }
        return table
    }

    private static func isHan(_ scalar: Unicode.Scalar) -> Bool {
        (0x3400...0x9FFF).contains(scalar.value) || (0xF900...0xFAFF).contains(scalar.value)
    }

    private static func isKana(_ scalar: Unicode.Scalar) -> Bool {
        (0x3040...0x30FF).contains(scalar.value)
    }

    // MARK: Queries (caller holds the lock)

    private static func indexedSQL(_ condition: String) -> String {
        """
        SELECT \(columns), MIN(\(score)) AS score, g.tier, s.gloss, s.chinese
        FROM glosses g JOIN words w ON w.id = g.word_id
        LEFT JOIN senses s ON s.word_id = g.word_id AND s.number = g.sense
        WHERE \(condition)
        GROUP BY w.id
        ORDER BY score, w.rank DESC, w.id
        LIMIT ?3
        """
    }

    /// Lower is better: a word's own glosses before CC-CEDICT pivots, a sense's first meaning
    /// in the word's first sense before the rest, then senses 1, 2 and the others.
    private static let score = """
        (g.tier = 2) * 100 + (COALESCE(g.sense, 1) > 1 OR g.position > 0) * 10 + MIN(COALESCE(g.sense, 1), 3)
        """

    private static let exactSQL = indexedSQL("g.term = ?1")
    private static let prefixSQL = indexedSQL("g.term > ?1 AND g.term < ?2")

    private func indexed(_ term: String, language: GlossMatch.Language, kind: GlossMatch.Kind, limit: Int) -> [GlossMatch] {
        let sql = kind == .exact ? Self.exactSQL : Self.prefixSQL
        let values: [SQLiteDatabase.Value] = [.text(term), .text(term + "\u{10FFFF}"), .int(limit)]
        let rows = try? database.query(sql, values) { row -> GlossMatch in
            let word = Self.word(row)
            let tier = row.int(Self.extraColumn + 1)
            let english = row.text(Self.extraColumn + 2)
            let chinese = row.text(Self.extraColumn + 3) ?? word.chinese
            let shown = tier == 0 ? chinese : english
            return GlossMatch(
                word: word, language: language, kind: kind, gloss: shown ?? word.gloss ?? "", viaEnglish: tier == 2
            )
        }
        return rows ?? []
    }

    private static let containingChineseSQL = """
        SELECT \(columns), s.chinese FROM senses s JOIN words w ON w.id = s.word_id
        WHERE s.chinese LIKE ?1 ESCAPE '\\'
        ORDER BY w.rank DESC, w.id LIMIT ?2
        """

    private static let containingEnglishSQL = """
        SELECT \(columns), s.gloss FROM senses s JOIN words w ON w.id = s.word_id
        WHERE s.gloss LIKE ?1 ESCAPE '\\'
        ORDER BY w.rank DESC, w.id LIMIT ?2
        """

    private func containing(_ term: String, language: GlossMatch.Language, limit: Int) -> [GlossMatch] {
        let escaped = term.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "%", with: "\\%")
            .replacingOccurrences(of: "_", with: "\\_")
        let sql = language == .chinese ? Self.containingChineseSQL : Self.containingEnglishSQL
        // English rows are filtered to whole words below (`rice` shouldn't find `price`), so fetch extra.
        let fetch = language == .chinese ? limit * 2 : limit * 6
        let rows = (try? database.query(sql, [.text("%\(escaped)%"), .int(fetch)]) { row in
            (Self.word(row), row.text(Self.extraColumn) ?? "")
        }) ?? []
        let pattern = language == .english
            ? try? NSRegularExpression(pattern: "(^|[^a-z])\(NSRegularExpression.escapedPattern(for: term))($|[^a-z])", options: .caseInsensitive)
            : nil
        return rows.compactMap { word, gloss in
            if let pattern, pattern.firstMatch(in: gloss, range: NSRange(gloss.startIndex..., in: gloss)) == nil {
                return nil
            }
            return GlossMatch(word: word, language: language, kind: .contains, gloss: gloss, viaEnglish: false)
        }
    }
}

/// One row under the search box: a word found by its spelling or reading, or by its meaning.
public enum SearchSuggestion: Sendable, Hashable, Identifiable {
    case word(DictionaryWord)
    case meaning(GlossMatch)

    public var word: DictionaryWord {
        switch self {
        case .word(let word): word
        case .meaning(let match): match.word
        }
    }

    public var id: Int { word.id }
}

extension OfflineDictionary {
    /// `suggestions(for:)` and `glossSuggestions(for:)` together: words spelt or read exactly
    /// as typed, words that mean exactly what was typed, then the other matches of each.
    /// `go` lists 碁 and 五 (ご) before 行く; `吃` lists 食べる before words starting with 吃.
    public func searchSuggestions(for text: String, limit: Int = 12) -> [SearchSuggestion] {
        let words = suggestions(for: text, limit: 10)
        let meanings = glossSuggestions(for: text, limit: 10)
        let typed = Set(Self.keys(for: text))
        func spelt(_ word: DictionaryWord) -> Bool {
            typed.contains(Kana.searchKey(word.written)) || typed.contains(Kana.searchKey(word.reading))
        }
        func means(_ match: GlossMatch) -> Bool { match.kind == .exact && !match.viaEnglish }
        let ordered = words.filter(spelt).map(SearchSuggestion.word)
            + meanings.filter(means).map(SearchSuggestion.meaning)
            + words.filter { !spelt($0) }.map(SearchSuggestion.word)
            + meanings.filter { !means($0) }.map(SearchSuggestion.meaning)
        var seen = Set<Int>()
        return Array(ordered.filter { seen.insert($0.id).inserted }.prefix(limit))
    }
}
