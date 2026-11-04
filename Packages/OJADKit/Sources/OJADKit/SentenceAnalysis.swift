import Foundation
import SwiftSoup

/// スズキクン's prosody analysis of a text: sentences split into accent phrases.
public struct SentenceAnalysis: Sendable, Hashable, Codable {
    /// One array of accent phrases per sentence, in reading order.
    public let sentences: [[AccentPhrase]]

    public init(sentences: [[AccentPhrase]]) {
        self.sentences = sentences
    }
}

public struct AccentPhrase: Sendable, Hashable, Codable {
    /// The original text of this phrase, punctuation included (`昨日、`).
    public let text: String
    public let reading: AccentedReading
    /// Position within its sentence; later phrases start lower (declination).
    public let phraseIndex: Int
    /// The phrase ends a question and gets a final rise.
    public let isQuestion: Bool

    public init(text: String, reading: AccentedReading, phraseIndex: Int, isQuestion: Bool) {
        self.text = text
        self.reading = reading
        self.phraseIndex = phraseIndex
        self.isQuestion = isQuestion
    }
}

/// Parses the HTML of `POST /ojad/phrasing/index`.
enum PhrasingParser {
    static func parse(html: String) throws -> SentenceAnalysis {
        let document: Document
        do {
            document = try SwiftSoup.parse(html)
        } catch {
            throw OJADError.unexpectedPage
        }
        guard let main = try document.select("#phrasing_main").first() else {
            throw OJADError.unexpectedPage
        }
        let sentences = try main.select("div.phrasing_row_wrapper").array().map { row in
            try row.select("div.phrasing_phrase_wrapper").array().compactMap(parsePhrase)
        }
        return SentenceAnalysis(sentences: sentences.filter { !$0.isEmpty })
    }

    private static func parsePhrase(_ wrapper: Element) throws -> AccentPhrase? {
        let morae: [Mora] = try wrapper.select("div.phrasing_text > span[class*=mola_]").array().map { span in
            let isNucleus = span.hasClass("accent_top")
            return Mora(
                text: try span.select("span.char").array().map { try $0.text() }.joined(),
                isHigh: isNucleus || span.hasClass("accent_plain"),
                isNucleus: isNucleus
            )
        }
        guard !morae.isEmpty else { return nil }

        let script = try wrapper.select("script").array().map { $0.data() }.joined()
        let call = PhraseCurveCall(script: script)
        let commands = call.map(\.commands).flatMap { $0.count == morae.count ? $0 : nil }
            ?? morae.map { $0.isHigh ? 1 : 0 }
        return AccentPhrase(
            text: try wrapper.select("div.phrasing_subscript").text().filter { !$0.isWhitespace },
            reading: AccentedReading(morae: morae, accentCommands: commands),
            phraseIndex: call?.phraseIndex ?? 0,
            isQuestion: call?.isQuestion ?? false
        )
    }

    /// `set_accent_curve_phrase('#phrase_0_1', 23, [0,1,…], 1, 1, 0)`:
    /// id, morae, accent commands, first mora, phrase index, question flag.
    private struct PhraseCurveCall {
        let commands: [Double]
        let phraseIndex: Int
        let isQuestion: Bool

        init?(script: String) {
            guard let commands = WordSearchParser.curveCommands(in: script),
                  let call = script.range(of: "set_accent_curve_phrase("),
                  let close = script[call.upperBound...].firstIndex(of: "]"),
                  let end = script[close...].firstIndex(of: ")")
            else { return nil }
            let trailing = script[script.index(after: close)..<end]
                .split(separator: ",")
                .compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
            guard trailing.count == 3 else { return nil }
            self.commands = commands
            self.phraseIndex = trailing[1]
            self.isQuestion = trailing[2] != 0
        }
    }
}
