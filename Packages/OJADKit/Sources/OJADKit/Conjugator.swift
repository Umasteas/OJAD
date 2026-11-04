import Foundation

/// JMdict's conjugation class, as stored in the offline dictionary's `class` column.
public enum WordClass: String, Sendable, Hashable, Codable, CaseIterable {
    case ichidan = "v1"
    case kureru = "v1-s"
    case zuru = "vz"
    case godanAru = "v5aru"
    case godanB = "v5b", godanG = "v5g", godanK = "v5k", godanIku = "v5k-s", godanM = "v5m", godanN = "v5n"
    case godanR = "v5r", godanAruIrregular = "v5r-i", godanS = "v5s", godanT = "v5t", godanU = "v5u"
    case godanUSpecial = "v5u-s"
    case kuru = "vk"
    case suru = "vs-i"
    case suruSpecial = "vs-s"
    case iAdjective = "adj-i"
    case ii = "adj-ix"
    case naAdjective = "adj-na"
    case noun = "n"

    public var category: WordCategory {
        switch self {
        case .iAdjective, .ii: .iAdjective
        case .naAdjective: .naAdjective
        case .noun: .noun
        default: .verb
        }
    }

    var isGodan: Bool { rawValue.hasPrefix("v5") }
}

/// Derives OJAD-style conjugation tables (forms, morae, pitch and curve commands)
/// from a dictionary-form reading and its accent nucleus.
///
/// The rules reproduce what OJAD lists (Tokyo pitch accent); they were fitted and
/// checked against 510 recorded OJAD rows (`Fixtures/ojad-validation.json`).
public enum Conjugator {
    /// `accents` are nucleus positions of the dictionary form, 1-based; 0 = 平板.
    public static func forms(reading: String, accents: [Int], wordClass: WordClass) -> [ConjugatedForm] {
        let category = wordClass.category
        var order: [String] = []
        var readings: [String: [AccentedReading]] = [:]
        for accent in accents {
            for (kind, variants) in table(reading: reading, accent: accent, wordClass: wordClass) {
                if readings[kind] == nil { order.append(kind) }
                for variant in variants where !(readings[kind] ?? []).contains(variant) {
                    readings[kind, default: []].append(variant)
                }
            }
        }
        return order.map { kind in
            ConjugatedForm(
                kind: kind,
                label: WordCategory.fallbackLabels[category]?[kind] ?? kind,
                readings: readings[kind] ?? []
            )
        }
    }

    /// OJAD's 見出し語: `食べる・食べます`, `高い・高いです`, `静か[な]・静かです`, `学校`.
    public static func headword(written: String, reading: String, wordClass: WordClass) -> String {
        switch wordClass.category {
        case .noun: return written
        case .naAdjective: return "\(written)[な]・\(written)です"
        case .iAdjective: return "\(written)・\(written)です"
        case .verb:
            let masu = verbForms(reading: written, wordClass: wordClass).first { $0.kind == "masu" }?.kana.first
            return masu.map { "\(written)・\($0)" } ?? written
        }
    }

    // MARK: Tables

    private static func table(reading: String, accent: Int, wordClass: WordClass) -> [(String, [AccentedReading])] {
        let morae = Kana.morae(reading)
        let accent = min(max(accent, 0), morae.count)
        switch wordClass.category {
        case .noun:
            return [("jisho", [pattern(reading, nucleus: accent)])]
        case .naAdjective:
            return naAdjective(reading, accent: accent)
        case .iAdjective:
            return iAdjective(reading, accent: accent, wordClass: wordClass)
        case .verb:
            var reading = reading
            var wordClass = wordClass
            if wordClass == .zuru, reading.hasSuffix("ずる") {
                // OJAD conjugates 〜ずる verbs as their 〜じる doublets.
                reading = String(reading.dropLast(2)) + "じる"
                wordClass = .ichidan
            }
            return verbForms(reading: reading, wordClass: wordClass).map { kind, kanas in
                (kind, kanas.map { pattern($0, nucleus: verbNucleus(kind: kind, kana: $0, accent: accent, wordClass: wordClass, prefixLength: suruPrefixLength(reading, wordClass))) })
            }
        }
    }

    private static let godanRows: [Character: (a: String, i: String, e: String, o: String, te: String)] = [
        "う": ("わ", "い", "え", "お", "って"), "く": ("か", "き", "け", "こ", "いて"), "ぐ": ("が", "ぎ", "げ", "ご", "いで"),
        "す": ("さ", "し", "せ", "そ", "して"), "つ": ("た", "ち", "て", "と", "って"), "ぬ": ("な", "に", "ね", "の", "んで"),
        "ぶ": ("ば", "び", "べ", "ぼ", "んで"), "む": ("ま", "み", "め", "も", "んで"), "る": ("ら", "り", "れ", "ろ", "って"),
    ]

    /// Kana for each verb form. Works on written forms too, as long as the okurigana
    /// ends like the reading (`食べる` → `食べます`).
    static func verbForms(reading r: String, wordClass: WordClass) -> [(kind: String, kana: [String])] {
        func forms(_ masu: String, _ te: String, _ ta: String, _ nai: String, _ nakatta: String, _ ba: String,
                   _ shieki: String, _ ukemi: String, _ meirei: [String], _ kano: String, _ ishi: String) -> [(String, [String])] {
            [("jisho", [r]), ("masu", [masu]), ("te", [te]), ("ta", [ta]), ("nai", [nai]), ("nakatta", [nakatta]),
             ("ba", [ba]), ("shieki", [shieki]), ("ukemi", [ukemi]), ("meirei", meirei), ("kano", [kano]), ("ishi", [ishi])]
        }
        switch wordClass {
        case .ichidan, .kureru, .zuru:
            let s = String(r.dropLast())
            return forms(s + "ます", s + "て", s + "た", s + "ない", s + "なかった", s + "れば", s + "させる", s + "られる",
                         [wordClass == .kureru ? s : s + "ろ"], s + "られる", s + "よう")
        case .suru:
            let p = String(r.dropLast(2))
            return forms(p + "します", p + "して", p + "した", p + "しない", p + "しなかった", p + "すれば", p + "させる",
                         p + "される", p.isEmpty ? ["しろ", "せよ"] : [p + "しろ"], p + "できる", p + "しよう")
        case .suruSpecial:
            let p = String(r.dropLast(2))
            return forms(p + "します", p + "して", p + "した", p + "しない", p + "しなかった", p + "すれば", p + "しさせる",
                         p + "せられる", [p + "しろ"], p + "せられる", p + "しよう")
        case .kuru:
            let p = String(r.dropLast(2))
            let (ki, ko, ku) = r.hasSuffix("来る") ? ("来", "来", "来") : ("き", "こ", "く")
            return forms(p + ki + "ます", p + ki + "て", p + ki + "た", p + ko + "ない", p + ko + "なかった", p + ku + "れば",
                         p + ko + "させる", p + ko + "られる", [p + ko + "い"], p + ko + "られる", p + ko + "よう")
        case .noun, .iAdjective, .ii, .naAdjective:
            return []
        default:
            guard let last = r.last, let row = godanRows[last] else { return [] }
            let s = String(r.dropLast())
            var te = row.te
            if wordClass == .godanIku { te = "って" }
            if wordClass == .godanUSpecial { te = "うて" }
            let ta = String(te.dropLast()) + (te.hasSuffix("で") ? "だ" : "た")
            let i = wordClass == .godanAru ? "い" : row.i
            let nai = wordClass == .godanAruIrregular ? String(s.dropLast()) : s + row.a
            return forms(s + i + "ます", s + te, s + ta, nai + "ない", nai + "なかった", s + row.e + "ば", s + row.a + "せる",
                         s + row.a + "れる", [wordClass == .godanAru ? s + "い" : s + row.e], s + row.e + "る", s + row.o + "う")
        }
    }

    /// Morae of a noun before `する` whose own nucleus the する forms keep (料ꜜ理する).
    private static func suruPrefixLength(_ reading: String, _ wordClass: WordClass) -> Int {
        wordClass == .suru ? Kana.morae(String(reading.dropLast(2))).count : 0
    }

    private static func verbNucleus(kind: String, kana: String, accent k: Int, wordClass: WordClass, prefixLength: Int) -> Int {
        let morae = Kana.morae(kana)
        let n = morae.count
        if kind == "jisho" { return k }
        if prefixLength > 0, k > 0, k <= prefixLength { return k }
        if kind == "masu" || kind == "ishi" { return n - 1 }
        if wordClass == .suru, kind == "kano" || kana.hasSuffix("せよ") { return n - 1 }
        if k == 0 {
            switch kind {
            case "nakatta": return n - 3
            case "ba": return n - 1
            default: return 0
            }
        }
        switch kind {
        case "te", "ta":
            if wordClass == .ichidan || wordClass == .kureru { return shifted(morae, max(1, k - 1)) }
            if wordClass == .kuru { return 1 }
            return shifted(morae, k)
        case "nai": return n - 2
        case "nakatta": return n - 4
        case "ba": return wordClass == .kuru ? 1 : shifted(morae, k)
        case "shieki", "ukemi", "kano": return shifted(morae, n - 1)
        case "meirei": return shifted(morae, min(k, n))
        default: return k
        }
    }

    private static func iAdjective(_ r: String, accent k: Int, wordClass: WordClass) -> [(String, [AccentedReading])] {
        let stem = wordClass == .ii ? String(r.dropLast(2)) + "よ" : String(r.dropLast())
        let n = Kana.morae(r).count
        let forms: [(String, String)] = [
            ("jisho", r), ("masu", r + "です"), ("te", stem + "くて"), ("ta", stem + "かった"), ("nai", stem + "くない"),
            ("nakatta", stem + "くなかった"), ("ba", stem + "ければ"), ("shieki", r), ("ukemi", stem + "く"),
        ]
        return forms.map { kind, kana in
            let morae = Kana.morae(kana)
            if kind == "jisho" { return (kind, [pattern(kana, nucleus: k)]) }
            if k == 0 {
                switch kind {
                case "masu": return (kind, [pattern(kana, nucleus: n - 1)])
                case "te", "ta", "ba": return (kind, [pattern(kana, nucleus: shifted(morae, n - 1))])
                case "nai": return (kind, [pattern(kana, nucleus: morae.count - 1)])
                case "nakatta": return (kind, [pattern(kana, nucleus: morae.count - 3)])
                case "shieki": return (kind, [pattern(kana, nucleus: 0), pattern(kana, nucleus: n - 1)])
                default: return (kind, [pattern(kana, nucleus: 0)])
                }
            }
            if kind == "masu" || kind == "shieki" { return (kind, [pattern(kana, nucleus: k)]) }
            // OJAD lists the traditional (one mora earlier) and the newer accent.
            let nuclei = k > 1 ? [shifted(morae, k - 1), k] : [k]
            let marked = (kind == "nai" || kind == "nakatta") ? (stem + "く").count : nil
            return (kind, unique(nuclei).map { pattern(kana, nucleus: $0, secondPhraseAt: marked) })
        }
    }

    private static func naAdjective(_ r: String, accent k: Int) -> [(String, [AccentedReading])] {
        let n = Kana.morae(r).count
        let forms: [(String, String, Int)] = [
            ("jisho", "な", 0), ("masu", "です", n + 1), ("te", "で", 0), ("ta", "だった", n + 1), ("nai", "じゃない", n + 2),
            ("nakatta", "じゃなかった", n + 2), ("ba", "ならば", n + 1), ("shieki", "だ", 0), ("ukemi", "に", 0),
        ]
        return forms.map { kind, suffix, flatNucleus in
            let kana = r + suffix
            if k == 0 { return (kind, [pattern(kana, nucleus: flatNucleus)]) }
            let marked: Int? = switch kind {
            case "nai": kana.count - 1
            case "nakatta": (r + "じゃな").count
            default: nil
            }
            return (kind, [pattern(kana, nucleus: k, secondPhraseAt: marked)])
        }
    }

    // MARK: Pitch

    /// High/low per mora for one accent phrase, with OJAD's curve commands: one value
    /// per kana (small kana repeat their mora's value); `secondPhraseAt` is a kana
    /// index where OJAD starts a second accent command (`たꜜかくなꜜい` → `[1,0,0,2,0]`).
    static func pattern(_ kana: String, nucleus k: Int, secondPhraseAt marked: Int? = nil) -> AccentedReading {
        let texts = Kana.morae(kana)
        let morae = texts.enumerated().map { index, text in
            let isHigh: Bool = switch k {
            case 0: index > 0
            case 1: index == 0
            default: index > 0 && index < k
            }
            return Mora(text: text, isHigh: isHigh, isNucleus: k > 0 && index == k - 1)
        }
        var commands = morae.flatMap { mora in Array(repeating: mora.isHigh ? 1.0 : 0.0, count: mora.text.count) }
        if let marked, commands.indices.contains(marked) {
            commands[marked] = 2
        }
        return AccentedReading(morae: morae, accentCommands: commands)
    }

    /// Moves a derived nucleus off morae that can't carry one (ん, っ, ー, the second
    /// half of a long vowel).
    static func shifted(_ morae: [String], _ nucleus: Int) -> Int {
        var k = nucleus
        while k > 1, !canCarryNucleus(morae, k - 1) { k -= 1 }
        return k
    }

    private static func canCarryNucleus(_ morae: [String], _ index: Int) -> Bool {
        let mora = Kana.searchKey(morae[index])
        if ["ん", "っ", "ー"].contains(mora) { return false }
        guard index > 0, let previous = vowel(of: morae[index - 1]) else { return true }
        switch mora {
        case "う": return !"ou".contains(previous)
        case "お": return previous != "o"
        case "え", "い": return previous != "e"
        default: return true
        }
    }

    private static func vowel(of mora: String) -> Character? {
        guard let last = Kana.searchKey(mora).last else { return nil }
        for (vowel, row) in vowelRows where row.contains(last) { return vowel }
        return nil
    }

    private static let vowelRows: [(Character, String)] = [
        ("a", "あかさたなはまやらわがざだばぱぁゃ"), ("i", "いきしちにひみりぎじぢびぴぃ"),
        ("u", "うくすつぬふむゆるぐずづぶぷぅゅゔ"), ("e", "えけせてねへめれげぜでべぺぇ"),
        ("o", "おこそとのほもよろをごぞどぼぽぉょ"),
    ]

    private static func unique(_ values: [Int]) -> [Int] {
        var seen = Set<Int>()
        return values.filter { seen.insert($0).inserted }
    }
}
