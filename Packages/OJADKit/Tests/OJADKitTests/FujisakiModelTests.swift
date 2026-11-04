import XCTest
import OJADKit

/// Expected values were produced by running OJAD's own renderer
/// (`/ojad/js/function.js?20180709`, `Fujisaki.fujisaki_curve` minus the canvas
/// baseline) in Node on the same inputs. See `Fixtures/README.md`.
final class FujisakiModelTests: XCTestCase {
    private func golden(_ name: String) throws -> [[Double]] {
        let json = try JSONSerialization.jsonObject(with: Fixture.data("fujisaki-golden", ext: "json")) as? [String: [[Double]]]
        return try XCTUnwrap(json?[name], "missing golden case \(name)")
    }

    private func assertMatches(_ samples: [PitchSample], _ expected: [[Double]], file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(samples.count, expected.count, "sample count", file: file, line: line)
        for (sample, pair) in zip(samples, expected) {
            XCTAssertEqual(sample.position, pair[0], accuracy: 1e-9, file: file, line: line)
            XCTAssertEqual(sample.level, pair[1], accuracy: 1e-9, "at mora \(pair[0])", file: file, line: line)
        }
    }

    func testWordCurveMatchesOJADForNakadaka() throws {
        assertMatches(FujisakiModel.word.contour(accent: [0, 1, 0]), try golden("word_nakadaka_010"))
    }

    func testWordCurveMatchesOJADForHeiban() throws {
        assertMatches(FujisakiModel.word.contour(accent: [0, 1, 1, 1]), try golden("word_heiban_0111"))
    }

    func testWordCurveMatchesOJADWithASecondAccentCommand() throws {
        assertMatches(FujisakiModel.word.contour(accent: [1, 0, 0, 2, 0]), try golden("word_two_accents_10020"))
    }

    func testPhraseCurveMatchesOJADForAWholeSentence() throws {
        assertMatches(
            FujisakiModel.phrase.contour(accent: [1, 1, 0, 0, 2, 0, 3, 0, 0, 0, 0, 0]),
            try golden("phrase_kyouwa_ii_tenki")
        )
    }

    func testPhraseCurveMatchesOJADForAQuestionInALaterPhrase() throws {
        assertMatches(
            FujisakiModel.phrase.contour(accent: [0, 1, 1, 0], phraseIndex: 1, isQuestion: true),
            try golden("phrase_second_phrase_question")
        )
    }

    func testEmptyAccentYieldsNoCurve() {
        XCTAssertEqual(FujisakiModel.word.contour(accent: []), [])
    }
}
