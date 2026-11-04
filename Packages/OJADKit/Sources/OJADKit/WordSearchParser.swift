import Foundation
import SwiftSoup

/// Parses the HTML of `/ojad/search/index/curve:fujisaki/word:…`.
enum WordSearchParser {
    static func parse(html: String) throws -> [WordEntry] {
        let document: Document
        do {
            document = try SwiftSoup.parse(html)
        } catch {
            throw OJADError.unexpectedPage
        }
        guard try document.select("#search_result").first() != nil else {
            throw OJADError.unexpectedPage
        }
        guard let table = try document.select("table#word_table").first() else {
            return []
        }

        let header = try Header(table: table)
        return try table.select("tbody > tr[id^=word_]").array().compactMap { row in
            try parseRow(row, header: header)
        }
    }

    /// The table header is rendered for the *first* row's category only (searching
    /// `きる` lists 着る under 「1グループの動詞」, and い-adjective labels differ from
    /// verb labels), so each row picks its own labels.
    private struct Header {
        let category: WordCategory?
        let labels: [String: String]

        init(table: Element) throws {
            category = try table.select("thead th.midashi").first().map { try WordCategory(headerLabel: $0.text()) } ?? nil
            var labels: [String: String] = [:]
            for th in try table.select("thead th[class*=katsuyo_]").array() {
                guard let kind = try formKind(of: th) else { continue }
                labels[kind] = try th.select("p").text()
            }
            self.labels = labels
        }

        func label(for kind: String, category rowCategory: WordCategory) -> String {
            if rowCategory == category, let label = labels[kind], !label.isEmpty {
                return label
            }
            return WordCategory.fallbackLabels[rowCategory]?[kind] ?? labels[kind] ?? kind
        }
    }

    private static func parseRow(_ row: Element, header: Header) throws -> WordEntry? {
        guard let id = Int(row.id().dropFirst("word_".count)) else { return nil }
        let headword = try row.select("td.midashi p.midashi_word").text()
        let category = WordCategory(headword: headword)

        let forms: [ConjugatedForm] = try row.select("td.katsuyo").array().compactMap { cell in
            guard let kind = try formKind(of: cell) else { return nil }
            let readings = try cell.select("div.katsuyo_proc").array().compactMap(parseReading)
            guard !readings.isEmpty else { return nil }
            return ConjugatedForm(kind: kind, label: header.label(for: kind, category: category), readings: readings)
        }
        return WordEntry(id: id, headword: headword, category: category, forms: forms)
    }

    private static func parseReading(_ proc: Element) throws -> AccentedReading? {
        let morae: [Mora] = try proc.select("span.accented_word > span[class*=mola_]").array().map { span in
            let isNucleus = span.hasClass("accent_top")
            return Mora(
                text: try span.select("span.char").array().map { try $0.text() }.joined(),
                isHigh: isNucleus || span.hasClass("accent_plain"),
                isNucleus: isNucleus
            )
        }
        guard !morae.isEmpty else { return nil }
        let script = try proc.select("script").array().map { $0.data() }.joined()
        let commands = curveCommands(in: script) ?? morae.map { $0.isHigh ? 1 : 0 }
        return AccentedReading(morae: morae, accentCommands: commands)
    }

    /// Extracts the array from `set_accent_curve_word('katsuyo_14377',3,[0,1,0],1)`.
    static func curveCommands(in script: String) -> [Double]? {
        guard let call = script.range(of: "set_accent_curve_word(") ?? script.range(of: "set_accent_curve_phrase("),
              let open = script[call.upperBound...].firstIndex(of: "["),
              let close = script[open...].firstIndex(of: "]")
        else { return nil }
        let values = script[script.index(after: open)..<close]
            .split(separator: ",")
            .map { Double($0.trimmingCharacters(in: .whitespaces)) }
        guard !values.isEmpty, values.allSatisfy({ $0 != nil }) else { return nil }
        return values.compactMap { $0 }
    }

    /// `jisho` from `class="katsuyo katsuyo_jisho_js"` or `class="jisho katsuyo_jisho_js"`.
    private static func formKind(of element: Element) throws -> String? {
        for name in try element.classNames() where name.hasPrefix("katsuyo_") && name.hasSuffix("_js") {
            return String(name.dropFirst("katsuyo_".count).dropLast("_js".count))
        }
        return nil
    }
}

extension WordCategory {
    init?(headerLabel: String) {
        if headerLabel.contains("動詞") { self = .verb }
        else if headerLabel.contains("い形容詞") { self = .iAdjective }
        else if headerLabel.contains("な形容詞") { self = .naAdjective }
        else if headerLabel.contains("名詞") { self = .noun }
        else { return nil }
    }

    /// Inferred from OJAD's headword shape: `食べる・食べます`, `高い・高いです`,
    /// `静か[な]・静かです`, `学校`.
    init(headword: String) {
        let parts = headword.split(separator: "・", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { self = .noun; return }
        if parts[1].hasSuffix("ます") { self = .verb }
        else if parts[0].hasSuffix("[な]") || !parts[0].hasSuffix("い") { self = .naAdjective }
        else { self = .iAdjective }
    }

    /// OJAD's own column labels per category, as recorded from its table headers.
    static let fallbackLabels: [WordCategory: [String: String]] = [
        .verb: [
            "jisho": "辞書形", "masu": "〜ます形", "te": "〜て形", "ta": "〜た形",
            "nai": "〜ない形", "nakatta": "〜なかった形", "ba": "〜ば形", "shieki": "使役形",
            "ukemi": "受身形", "meirei": "命令形", "kano": "可能形", "ishi": "〜う形",
        ],
        .iAdjective: [
            "jisho": "〜い + N形", "masu": "〜いです形", "te": "〜くて形", "ta": "〜かった形",
            "nai": "〜くない形", "nakatta": "〜くなかった形", "ba": "〜ければ形",
            "shieki": "〜い。形", "ukemi": "〜く形",
        ],
        .naAdjective: [
            "jisho": "〜な + N形", "masu": "〜です形", "te": "〜で形", "ta": "〜だった形",
            "nai": "〜じゃない形", "nakatta": "〜じゃなかった形", "ba": "〜ならば形",
            "shieki": "〜だ形", "ukemi": "〜に形",
        ],
        .noun: ["jisho": "辞書形"],
    ]
}
