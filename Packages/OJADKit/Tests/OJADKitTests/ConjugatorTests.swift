import XCTest
@testable import OJADKit

final class ConjugatorTests: XCTestCase {
    func testDerivedTablesMatchOJADForTheRecordedWords() async throws {
        // OJAD's own pages for 食べる, 高い, 静か and 学校, against the table derived
        // offline from the same reading and dictionary-form accent.
        let cases: [(fixture: String, query: String, reading: String, accents: [Int], wordClass: WordClass)] = [
            ("search-taberu", "食べる", "たべる", [2], .ichidan),
            ("search-takai", "高い", "たかい", [2], .iAdjective),
            ("search-shizuka", "静か", "しずか", [1], .naAdjective),
            ("search-gakkou", "学校", "がっこう", [0], .noun),
        ]
        for item in cases {
            let ojad = try await OJADClient.fixture(FixtureTransport(fixture: item.fixture)).searchWord(item.query)
            let expected = try XCTUnwrap(ojad.first)
            let written = expected.lemma.replacingOccurrences(of: "[な]", with: "")
            XCTAssertEqual(Conjugator.headword(written: written, reading: item.reading, wordClass: item.wordClass), expected.headword)
            XCTAssertEqual(
                Conjugator.forms(reading: item.reading, accents: item.accents, wordClass: item.wordClass),
                expected.forms,
                item.query
            )
        }
    }

    /// 510 words OJAD lists per category (`Fixtures/ojad-validation.json`): derive every
    /// form from OJAD's own dictionary-form accent and compare with what OJAD shows.
    func testAccuracyAgainstOJADValidationSet() throws {
        let rows = try JSONDecoder().decode([ValidationRow].self, from: Fixture.data("ojad-validation", ext: "json"))
        XCTAssertEqual(rows.count, 510)

        var total: [WordCategory: Int] = [:]
        var anyMatch: [WordCategory: Int] = [:]
        var exact: [WordCategory: Int] = [:]
        var mismatches: [String] = []
        for row in rows {
            guard let jisho = row.forms.first(where: { $0.kind == "jisho" })?.variants, !jisho.isEmpty else { continue }
            let bases = jisho.map(Self.base)
            var reading = bases[0].kana
            if row.category == .naAdjective, reading.hasSuffix("な") { reading.removeLast() }
            let wordClass = Self.wordClass(row, reading: reading)
            let derived = Dictionary(
                Conjugator.forms(reading: reading, accents: bases.map(\.accent), wordClass: wordClass)
                    .map { ($0.kind, Set($0.readings.map(Self.describe))) },
                uniquingKeysWith: { $0.union($1) }
            )
            for form in row.forms where form.kind != "jisho" && !form.variants.isEmpty {
                let ojad = Set(form.variants)
                let mine = derived[form.kind] ?? []
                total[row.category, default: 0] += 1
                let spans = { (set: Set<String>) in Set(set.map { $0.split(separator: " ").prefix(2).joined(separator: " ") }) }
                if !spans(ojad).isDisjoint(with: spans(mine)) {
                    anyMatch[row.category, default: 0] += 1
                } else {
                    mismatches.append("\(row.headword) \(form.kind): OJAD \(ojad.sorted()) mine \(mine.sorted())")
                }
                if ojad == mine { exact[row.category, default: 0] += 1 }
            }
        }
        for category in WordCategory.allCases where total[category] != nil {
            let n = total[category] ?? 0
            print("\(category): \(anyMatch[category] ?? 0)/\(n) forms match a variant, \(exact[category] ?? 0)/\(n) identical")
        }
        print(mismatches.joined(separator: "\n"))

        func ratio(_ category: WordCategory) -> Double {
            Double(anyMatch[category] ?? 0) / Double(max(total[category] ?? 0, 1))
        }
        XCTAssertGreaterThanOrEqual(ratio(.verb), 0.985)
        XCTAssertEqual(ratio(.iAdjective), 1)
        XCTAssertGreaterThanOrEqual(ratio(.naAdjective), 0.96)
    }

    func testNucleusMovesOffMoraeThatCannotCarryIt() {
        XCTAssertEqual(Conjugator.shifted(Kana.morae("かえって"), 3), 2)
        XCTAssertEqual(Conjugator.shifted(Kana.morae("よんで"), 2), 1)
        XCTAssertEqual(Conjugator.shifted(Kana.morae("おもって"), 3), 2)
        XCTAssertEqual(Conjugator.shifted(Kana.morae("たべて"), 2), 2)
    }

    func testSuruVerbsKeepAnAccentedNounsNucleus() {
        let forms = Conjugator.forms(reading: "りょうりする", accents: [1], wordClass: .suru)
        XCTAssertEqual(forms.first { $0.kind == "masu" }?.readings.map(\.notation), ["りょꜜうりします"])
        let flat = Conjugator.forms(reading: "べんきょうする", accents: [0], wordClass: .suru)
        XCTAssertEqual(flat.first { $0.kind == "masu" }?.readings.map(\.notation), ["べんきょうしまꜜす"])
        XCTAssertEqual(Conjugator.headword(written: "勉強する", reading: "べんきょうする", wordClass: .suru), "勉強する・勉強します")
    }

    // MARK: Helpers

    private struct ValidationRow: Decodable {
        let headword: String
        let category: WordCategory
        let forms: [Form]
        let ojadCategory: String

        struct Form: Decodable {
            let kind: String
            let variants: [String]

            init(from decoder: Decoder) throws {
                var container = try decoder.unkeyedContainer()
                kind = try container.decode(String.self)
                variants = try container.decode([String].self)
            }
        }
    }

    /// `たべꜜる LHL 0,1,0` → (たべる, 2).
    private static func base(_ variant: String) -> (kana: String, accent: Int) {
        let notation = String(variant.split(separator: " ")[0])
        let kana = notation.replacingOccurrences(of: "ꜜ", with: "")
        guard let mark = notation.firstIndex(of: "ꜜ") else { return (kana, 0) }
        return (kana, Kana.morae(String(notation[..<mark])).count)
    }

    private static func describe(_ reading: AccentedReading) -> String {
        let pitch = reading.morae.map { $0.isHigh ? "H" : "L" }.joined()
        let commands = reading.accentCommands.map { String(Int($0)) }.joined(separator: ",")
        return "\(reading.notation) \(pitch) \(commands)"
    }

    private static func wordClass(_ row: ValidationRow, reading: String) -> WordClass {
        let lemma = String(row.headword.split(separator: "・")[0])
        switch row.ojadCategory {
        case "ichidan": return .ichidan
        case "iAdjective": return reading.hasSuffix("いい") && lemma.hasSuffix("いい") ? .ii : .iAdjective
        case "naAdjective": return .naAdjective
        case "noun": return .noun
        case "irregular":
            if lemma.hasSuffix("来る") || lemma == "くる" { return .kuru }
            if lemma.hasSuffix("ずる") { return .zuru }
            return lemma.count == 3 && lemma != "する" ? .suruSpecial : .suru
        default:
            if lemma.hasSuffix("行く") { return .godanIku }
            let byEnding: [Character: WordClass] = [
                "う": .godanU, "く": .godanK, "ぐ": .godanG, "す": .godanS, "つ": .godanT,
                "ぬ": .godanN, "ぶ": .godanB, "む": .godanM, "る": .godanR,
            ]
            return reading.last.flatMap { byEnding[$0] } ?? .godanR
        }
    }
}
