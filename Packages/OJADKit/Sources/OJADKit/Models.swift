import Foundation

/// One dictionary row of OJAD's 単語検索 result: a word and its conjugated forms.
public struct WordEntry: Sendable, Hashable, Codable, Identifiable {
    /// OJAD's own word id (`tr#word_<id>`). Stable across requests.
    public let id: Int
    /// OJAD's 見出し語, e.g. `食べる・食べます`, `高い・高いです`, `学校`.
    public let headword: String
    public let category: WordCategory
    /// Only the forms OJAD actually lists for this word, in OJAD's column order.
    public let forms: [ConjugatedForm]

    public init(id: Int, headword: String, category: WordCategory, forms: [ConjugatedForm]) {
        self.id = id
        self.headword = headword
        self.category = category
        self.forms = forms
    }

    /// The dictionary form part of the headword (`食べる・食べます` → `食べる`).
    public var lemma: String {
        String(headword.split(separator: "・", maxSplits: 1).first ?? Substring(headword))
    }
}

public enum WordCategory: String, Sendable, Hashable, Codable, CaseIterable {
    case verb
    case iAdjective
    case naAdjective
    case noun
}

/// One column of the conjugation table (辞書形, 〜ます形, …).
public struct ConjugatedForm: Sendable, Hashable, Codable {
    /// OJAD's column key: `jisho masu te ta nai nakatta ba shieki ukemi meirei kano ishi`.
    /// Adjectives reuse these keys with different meanings, so display `label`, not `kind`.
    public let kind: String
    public let label: String
    /// Usually one; several when OJAD lists accent variants (e.g. `たꜜかくて` / `たかꜜくて`).
    public let readings: [AccentedReading]

    public init(kind: String, label: String, readings: [AccentedReading]) {
        self.kind = kind
        self.label = label
        self.readings = readings
    }
}

/// A kana reading with its pitch pattern, plus the raw accent-command array OJAD
/// feeds its curve renderer (`set_accent_curve_word`).
public struct AccentedReading: Sendable, Hashable, Codable {
    public let morae: [Mora]
    /// One value per mora: 0 = low, >0 = high; the integer counts accent commands.
    /// Input for `FujisakiModel.contour(accent:)`.
    public let accentCommands: [Double]

    public init(morae: [Mora], accentCommands: [Double]) {
        self.morae = morae
        self.accentCommands = accentCommands
    }

    public var kana: String { morae.map(\.text).joined() }

    /// Kana with `ꜜ` after every accent nucleus, e.g. `たべꜜる`.
    public var notation: String {
        morae.map { $0.isNucleus ? $0.text + "ꜜ" : $0.text }.joined()
    }
}

public struct Mora: Sendable, Hashable, Codable {
    /// Usually one kana; two for 拗音 such as `きょ`.
    public let text: String
    public let isHigh: Bool
    /// High, and pitch falls right after this mora (アクセント核).
    public let isNucleus: Bool

    public init(text: String, isHigh: Bool, isNucleus: Bool) {
        self.text = text
        self.isHigh = isHigh
        self.isNucleus = isNucleus
    }
}
