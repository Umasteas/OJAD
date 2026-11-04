import Foundation

/// Kana utilities shared by the offline dictionary and the conjugator.
public enum Kana {
    /// The form every dictionary key is stored in: NFKC, lowercased, katakana folded
    /// to hiragana. Must match `search_key` in `scripts/dictionary/build.py`.
    public static func searchKey(_ text: String) -> String {
        // Composing again: some Foundation versions leave ﾍﾞ as ヘ + U+3099 after NFKC.
        let folded = text.precomposedStringWithCompatibilityMapping.precomposedStringWithCanonicalMapping.lowercased()
        return String(String.UnicodeScalarView(folded.unicodeScalars.map { scalar in
            (0x30A1...0x30F6).contains(scalar.value) ? Unicode.Scalar(scalar.value - 0x60)! : scalar
        }))
    }

    /// Splits kana into morae: small ゃゅょぁぃぅぇぉゎ join the previous kana;
    /// っ, ん and ー are morae of their own.
    public static func morae(_ kana: String) -> [String] {
        var result: [String] = []
        for character in kana {
            if smallKana.contains(character), let last = result.popLast() {
                result.append(last + String(character))
            } else {
                result.append(String(character))
            }
        }
        return result
    }

    static let smallKana: Set<Character> = Set("ゃゅょぁぃぅぇぉゎャュョァィゥェォヮ")

    public static func isKana(_ text: String) -> Bool {
        text.unicodeScalars.allSatisfy { (0x3041...0x30FF).contains($0.value) }
    }

    /// Converts romaji typed on a Latin keyboard (`tabe`, `gakkou`, `kyou`, `shi`/`si`)
    /// to hiragana. A trailing incomplete syllable (`tab` → `た` + `b`) is returned
    /// separately so callers can still search by the complete part.
    ///
    /// Kana pass through, so text a Japanese IME is still composing (`たb`) works too.
    /// Returns nil when the text has no romaji in it, or isn't romaji.
    public static func hiragana(fromRomaji text: String) -> (kana: String, pending: String)? {
        let input = searchKey(text)
        guard input.contains(where: isLatin) else { return nil }
        var output = ""
        var rest = Substring(input)
        while let first = rest.first {
            if !isLatin(first) && first != "-" && first != "'" {
                guard isKana(String(first)) || first == "ー" else { return nil }
                output.append(first); rest = rest.dropFirst(); continue
            }
            if first == "-" {
                output += "ー"; rest = rest.dropFirst(); continue
            }
            if first == "'" {
                rest = rest.dropFirst(); continue
            }
            if rest.count >= 2, let second = rest.dropFirst().first,
               first == second, first != "n", !"aiueo".contains(first) {
                output += "っ"; rest = rest.dropFirst(); continue
            }
            if first == "n" {
                let next = rest.dropFirst().first
                if next == "n" { output += "ん"; rest = rest.dropFirst(2); continue }
                if let next, !"aiueoy".contains(next) { output += "ん"; rest = rest.dropFirst(); continue }
                if next == nil { return (output, "n") }
            }
            var matched = false
            for length in stride(from: min(4, rest.count), through: 1, by: -1) {
                if let kana = romajiTable[String(rest.prefix(length))] {
                    output += kana
                    rest = rest.dropFirst(length)
                    matched = true
                    break
                }
            }
            if !matched {
                let pending = String(rest)
                guard pending.count <= 3, pending.allSatisfy(isLatin), !completions(ofPending: pending).isEmpty else {
                    return nil
                }
                return (output, pending)
            }
        }
        return (output, "")
    }

    /// Kana an incomplete romaji syllable can still become: `b` → ば, び, ぶ, べ, ぼ, びゃ…
    public static func completions(ofPending pending: String) -> [String] {
        guard !pending.isEmpty else { return [] }
        var seen = Set<String>()
        var result = romajiTable.keys.sorted()
            .filter { $0.hasPrefix(pending) }
            .compactMap { romajiTable[$0] }
            .filter { seen.insert($0).inserted }
        if pending == "n", seen.insert("ん").inserted { result.insert("ん", at: 0) }
        return result
    }

    private static func isLatin(_ character: Character) -> Bool {
        ("a"..."z").contains(character)
    }

    private static let romajiTable: [String: String] = {
        var table: [String: String] = [:]
        let rows: [(String, [String])] = [
            ("", ["あ", "い", "う", "え", "お"]),
            ("k", ["か", "き", "く", "け", "こ"]), ("g", ["が", "ぎ", "ぐ", "げ", "ご"]),
            ("s", ["さ", "し", "す", "せ", "そ"]), ("z", ["ざ", "じ", "ず", "ぜ", "ぞ"]),
            ("t", ["た", "ち", "つ", "て", "と"]), ("d", ["だ", "ぢ", "づ", "で", "ど"]),
            ("n", ["な", "に", "ぬ", "ね", "の"]), ("h", ["は", "ひ", "ふ", "へ", "ほ"]),
            ("b", ["ば", "び", "ぶ", "べ", "ぼ"]), ("p", ["ぱ", "ぴ", "ぷ", "ぺ", "ぽ"]),
            ("m", ["ま", "み", "む", "め", "も"]), ("r", ["ら", "り", "る", "れ", "ろ"]),
            ("y", ["や", "い", "ゆ", "いぇ", "よ"]), ("w", ["わ", "うぃ", "う", "うぇ", "を"]),
            ("f", ["ふぁ", "ふぃ", "ふ", "ふぇ", "ふぉ"]), ("v", ["ゔぁ", "ゔぃ", "ゔ", "ゔぇ", "ゔぉ"]),
            ("j", ["じゃ", "じ", "じゅ", "じぇ", "じょ"]), ("l", ["ぁ", "ぃ", "ぅ", "ぇ", "ぉ"]),
            ("x", ["ぁ", "ぃ", "ぅ", "ぇ", "ぉ"]),
        ]
        for (consonant, kana) in rows {
            for (vowel, value) in zip(["a", "i", "u", "e", "o"], kana) {
                table[consonant + vowel] = value
            }
        }
        let youon: [(String, String)] = [
            ("ky", "き"), ("gy", "ぎ"), ("sh", "し"), ("sy", "し"), ("zy", "じ"), ("jy", "じ"),
            ("ch", "ち"), ("ty", "ち"), ("cy", "ち"), ("dy", "ぢ"), ("ny", "に"), ("hy", "ひ"),
            ("by", "び"), ("py", "ぴ"), ("my", "み"), ("ry", "り"),
        ]
        for (prefix, kana) in youon {
            table[prefix + "a"] = kana + "ゃ"
            table[prefix + "u"] = kana + "ゅ"
            table[prefix + "o"] = kana + "ょ"
            table[prefix + "e"] = kana + "ぇ"
        }
        table["shi"] = "し"; table["chi"] = "ち"; table["tsu"] = "つ"; table["fu"] = "ふ"
        table["ji"] = "じ"; table["tu"] = "つ"; table["ti"] = "ち"; table["si"] = "し"; table["zi"] = "じ"
        table["hu"] = "ふ"; table["di"] = "ぢ"; table["du"] = "づ"
        table["ltu"] = "っ"; table["xtu"] = "っ"; table["ltsu"] = "っ"
        table["lya"] = "ゃ"; table["lyu"] = "ゅ"; table["lyo"] = "ょ"
        table["xya"] = "ゃ"; table["xyu"] = "ゅ"; table["xyo"] = "ょ"
        table["thi"] = "てぃ"; table["dhi"] = "でぃ"; table["twu"] = "とぅ"
        return table
    }()
}
