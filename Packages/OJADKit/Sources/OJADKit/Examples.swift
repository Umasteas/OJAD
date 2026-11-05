import Foundation

/// One JMdict sense of a dictionary word, numbered as in JMdict (from 1).
public struct WordSense: Sendable, Hashable, Identifiable {
    /// Where a sense's Simplified Chinese comes from (`scripts/dictionary/chinese.py`).
    public enum ChineseSource: String, Sendable, Hashable {
        /// Chinese Wiktionary's definition of the Japanese word.
        case wiktionary
        /// The Chinese word spelt the same (衝突 → 冲突), when CC-CEDICT's English agrees with the sense.
        case cedict
    }

    public let number: Int
    /// Up to three English glosses, e.g. `to eat`.
    public let gloss: String
    /// Simplified Chinese for this sense, e.g. `吃`; nil when no source has one.
    public let chinese: String?
    public let chineseSource: ChineseSource?

    public init(number: Int, gloss: String, chinese: String? = nil, chineseSource: ChineseSource? = nil) {
        self.number = number
        self.gloss = gloss
        self.chinese = chinese
        self.chineseSource = chineseSource
    }

    public var id: Int { number }
}

/// A corpus sentence that uses a word, tied to the sense it illustrates where known.
public struct ExampleSentence: Sendable, Hashable, Identifiable {
    /// How the sentence was tied to the word and sense (`scripts/dictionary/examples.py`).
    public enum Basis: String, Sendable, Hashable {
        /// Tatoeba's index names the sense.
        case tagged
        /// JMdict lists the sentence under the sense.
        case jmdict
        /// The word has only one sense.
        case single
        /// Sense guessed from the English translation.
        case gloss
        /// The index lists the word, but not which sense.
        case unassigned
        /// The sentence merely contains the spelling; not checked by any index.
        case text
    }

    public enum Source: Sendable, Hashable {
        case tatoeba
        /// Kyoto Free Translation Task (Wikipedia's Kyoto articles, NICT translations).
        case kftt
    }

    /// Sentence ids from KFTT start here; lower ids are Tatoeba's own.
    public static let kfttIDBase = 1_000_000_000

    public let id: Int
    public let japanese: String
    public let english: String?
    /// Simplified Chinese translation, from Tatoeba.
    public let chinese: String?
    /// The Chinese translates the English translation rather than the Japanese.
    public let chineseViaEnglish: Bool
    /// JMdict sense number; nil when unknown.
    public let sense: Int?
    public let basis: Basis

    public init(
        id: Int, japanese: String, english: String?, chinese: String?, chineseViaEnglish: Bool = false,
        sense: Int?, basis: Basis
    ) {
        self.id = id
        self.japanese = japanese
        self.english = english
        self.chinese = chinese
        self.chineseViaEnglish = chineseViaEnglish
        self.sense = sense
        self.basis = basis
    }

    public var source: Source { id >= Self.kfttIDBase ? .kftt : .tatoeba }
}

/// Examples grouped under the sense they illustrate, in sense order; examples whose
/// sense is unknown come last with `sense == nil`. Senses without examples are kept,
/// so every meaning of the word is listed.
public struct SenseExamples: Sendable, Hashable, Identifiable {
    public let sense: WordSense?
    public let examples: [ExampleSentence]

    public var id: Int { sense?.number ?? 0 }

    public static func group(_ examples: [ExampleSentence], senses: [WordSense]) -> [SenseExamples] {
        let known = Set(senses.map(\.number))
        var groups = senses.map { sense in
            SenseExamples(sense: sense, examples: examples.filter { $0.sense == sense.number })
        }
        let unassigned = examples.filter { $0.sense.map { !known.contains($0) } ?? true }
        if !unassigned.isEmpty {
            groups.append(SenseExamples(sense: nil, examples: unassigned))
        }
        return groups
    }
}
