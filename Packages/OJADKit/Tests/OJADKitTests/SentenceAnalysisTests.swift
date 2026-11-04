import XCTest
@testable import OJADKit

final class SentenceAnalysisTests: XCTestCase {
    func testSingleAccentPhraseCarriesReadingCommandsAndOriginalText() async throws {
        let transport = try FixtureTransport(fixture: "phrasing-asagohan")
        let analysis = try await OJADClient.fixture(transport).analyzeSentence("朝ご飯を食べるのを忘れた。")

        XCTAssertEqual(analysis.sentences.count, 1)
        let phrase = try XCTUnwrap(analysis.sentences.first?.first)
        XCTAssertEqual(phrase.text, "朝ご飯を食べるのを忘れた。")
        XCTAssertEqual(phrase.reading.notation, "あさごꜜはんをたべꜜるのをわすれた")
        XCTAssertEqual(phrase.reading.accentCommands, [0, 1, 1, 0, 0, 0, 0, 2, 0, 0, 0, 0, 3, 3, 3])
        XCTAssertEqual(phrase.phraseIndex, 0)
        XCTAssertFalse(phrase.isQuestion)
    }

    func testSentencesSplitIntoAccentPhrasesAndQuestionsAreMarked() async throws {
        let transport = try FixtureTransport(fixture: "phrasing-kinou-oishikatta")
        let analysis = try await OJADClient.fixture(transport).analyzeSentence("昨日、友達と駅前の店でラーメンを食べました。美味しかったですか？")

        XCTAssertEqual(analysis.sentences.map { $0.map(\.text) }, [
            ["昨日、", "友達と駅前の店でラーメンを食べました。"],
            ["美味しかったですか？"],
        ])
        XCTAssertEqual(analysis.sentences.map { $0.map(\.phraseIndex) }, [[0, 1], [0]])
        XCTAssertEqual(analysis.sentences.map { $0.map(\.isQuestion) }, [[false, false], [true]])
        XCTAssertEqual(analysis.sentences[0][0].reading.kana, "きのう")
        XCTAssertEqual(analysis.sentences[1][0].reading.accentCommands, [0, 1, 1, 1, 0, 0, 0, 0, 0])
    }

    func testPostsTheSentenceAsSuzukiKunsFormWithoutTouchingSynthesis() async throws {
        let transport = try FixtureTransport(fixture: "phrasing-asagohan")
        _ = try await OJADClient.fixture(transport).analyzeSentence(" 朝ご飯を食べるのを忘れた。\n")

        let request = try XCTUnwrap(transport.requests.first)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url?.absoluteString, "https://www.gavo.t.u-tokyo.ac.jp/ojad/phrasing/index")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/x-www-form-urlencoded; charset=UTF-8")
        let form = try XCTUnwrap(request.httpBody.flatMap { String(data: $0, encoding: .utf8) })
        let fields = Dictionary(uniqueKeysWithValues: form.split(separator: "&").map { pair -> (String, String) in
            let kv = pair.split(separator: "=", maxSplits: 1).map { String($0).removingPercentEncoding ?? "" }
            return (kv[0], kv.count > 1 ? kv[1] : "")
        })
        XCTAssertEqual(fields["data[Phrasing][text]"], "朝ご飯を食べるのを忘れた。")
        XCTAssertEqual(fields["data[Phrasing][curve]"], "advanced")
        XCTAssertEqual(fields["data[Phrasing][estimation]"], "crf")
        XCTAssertEqual(fields["data[Phrasing][analyze]"], "true")
    }

    func testPageWithoutPhrasingResultIsReportedAsLayoutChange() async throws {
        let transport = FixtureTransport(body: "<html><body><form id=\"PhrasingIndexForm\"></form></body></html>")
        do {
            _ = try await OJADClient.fixture(transport).analyzeSentence("食べる。")
            XCTFail("expected an error")
        } catch {
            XCTAssertEqual(error as? OJADError, .unexpectedPage)
        }
    }

    func testBlankSentenceIsRejectedWithoutARequest() async throws {
        let transport = FixtureTransport(body: "")
        do {
            _ = try await OJADClient.fixture(transport).analyzeSentence(" \n ")
            XCTFail("expected an error")
        } catch {
            XCTAssertEqual(error as? OJADError, .invalidQuery)
        }
        XCTAssertTrue(transport.requests.isEmpty)
    }
}
