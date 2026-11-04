import XCTest
@testable import OJADKit

final class WordSearchTests: XCTestCase {
    func testVerbReturnsEveryConjugatedFormWithPitch() async throws {
        let transport = try FixtureTransport(fixture: "search-taberu")
        let entries = try await OJADClient.fixture(transport).searchWord("食べる")

        XCTAssertEqual(entries.count, 1)
        let entry = try XCTUnwrap(entries.first)
        XCTAssertEqual(entry.id, 1238)
        XCTAssertEqual(entry.headword, "食べる・食べます")
        XCTAssertEqual(entry.category, .verb)
        XCTAssertEqual(entry.forms.map(\.label), [
            "辞書形", "〜ます形", "〜て形", "〜た形", "〜ない形", "〜なかった形",
            "〜ば形", "使役形", "受身形", "命令形", "可能形", "〜う形",
        ])
        XCTAssertEqual(entry.forms.map { $0.readings.map(\.notation) }, [
            ["たべꜜる"], ["たべまꜜす"], ["たꜜべて"], ["たꜜべた"], ["たべꜜない"], ["たべꜜなかった"],
            ["たべꜜれば"], ["たべさせꜜる"], ["たべられꜜる"], ["たべꜜろ"], ["たべられꜜる"], ["たべよꜜう"],
        ])
    }

    func testIAdjectiveKeepsAccentVariantsAndItsOwnColumnLabels() async throws {
        let transport = try FixtureTransport(fixture: "search-takai")
        let entries = try await OJADClient.fixture(transport).searchWord("高い")
        let entry = try XCTUnwrap(entries.first)

        XCTAssertEqual(entry.category, .iAdjective)
        XCTAssertEqual(entry.lemma, "高い")
        XCTAssertEqual(entry.forms.map(\.label), [
            "〜い + N形", "〜いです形", "〜くて形", "〜かった形", "〜くない形",
            "〜くなかった形", "〜ければ形", "〜い。形", "〜く形",
        ])
        let te = try XCTUnwrap(entry.forms.first { $0.label == "〜くて形" })
        XCTAssertEqual(te.readings.map(\.notation), ["たꜜかくて", "たかꜜくて"])
        XCTAssertEqual(te.readings.map(\.accentCommands), [[1, 0, 0, 0], [0, 1, 0, 0]])
    }

    func testEachRowGetsLabelsForItsOwnCategoryEvenWhenTheHeaderIsForAnother() async throws {
        // OJAD renders the header for the first row only: here 「1グループの動詞」.
        let transport = try FixtureTransport(fixture: "search-nomu-shizuka")
        let entries = try await OJADClient.fixture(transport).searchWord("飲む")

        XCTAssertEqual(entries.map(\.headword), ["飲む・飲みます", "静か[な]・静かです"])
        XCTAssertEqual(entries.map(\.category), [.verb, .naAdjective])
        XCTAssertEqual(entries[0].forms.first?.label, "辞書形")
        XCTAssertEqual(entries[1].forms.map(\.label).prefix(3), ["〜な + N形", "〜です形", "〜で形"])
    }

    func testHomonymsComeBackAsSeparateEntries() async throws {
        let transport = try FixtureTransport(fixture: "search-kiru")
        let entries = try await OJADClient.fixture(transport).searchWord("きる")

        XCTAssertEqual(entries.map(\.lemma), ["切る", "着る"])
        XCTAssertEqual(entries.map { $0.forms.first?.readings.first?.notation }, ["きꜜる", "きる"])
    }

    func testNounHasOnlyItsDictionaryForm() async throws {
        let transport = try FixtureTransport(fixture: "search-gakkou")
        let entries = try await OJADClient.fixture(transport).searchWord("学校")
        let entry = try XCTUnwrap(entries.first)

        XCTAssertEqual(entry.category, .noun)
        XCTAssertEqual(entry.forms.count, 1)
        let reading = try XCTUnwrap(entry.forms.first?.readings.first)
        XCTAssertEqual(reading.notation, "がっこう")
        XCTAssertEqual(reading.morae.map(\.isHigh), [false, true, true, true])
        XCTAssertEqual(reading.accentCommands, [0, 1, 1, 1])
    }

    func testUnknownWordReturnsNoEntries() async throws {
        let transport = try FixtureTransport(fixture: "search-no-result")
        let entries = try await OJADClient.fixture(transport).searchWord("zzqqxxふが")
        XCTAssertEqual(entries, [])
    }

    func testPageWithoutSearchResultIsReportedAsLayoutChange() async throws {
        let transport = FixtureTransport(body: "<html><body><h1>Maintenance</h1></body></html>")
        do {
            _ = try await OJADClient.fixture(transport).searchWord("食べる")
            XCTFail("expected an error")
        } catch {
            XCTAssertEqual(error as? OJADError, .unexpectedPage)
        }
    }

    func testServerErrorIsSurfaced() async throws {
        let transport = FixtureTransport(body: "", status: 503)
        do {
            _ = try await OJADClient.fixture(transport).searchWord("食べる")
            XCTFail("expected an error")
        } catch {
            XCTAssertEqual(error as? OJADError, .httpStatus(503))
        }
    }

    func testRequestsTheCurveVariantWithAnIdentifyingUserAgent() async throws {
        let transport = try FixtureTransport(fixture: "search-taberu")
        _ = try await OJADClient.fixture(transport).searchWord(" 食べる\n")

        let request = try XCTUnwrap(transport.requests.first)
        XCTAssertEqual(transport.requests.count, 1)
        XCTAssertEqual(request.httpMethod ?? "GET", "GET")
        XCTAssertEqual(
            request.url?.absoluteString,
            "https://www.gavo.t.u-tokyo.ac.jp/ojad/search/index/curve:fujisaki/word:%E9%A3%9F%E3%81%B9%E3%82%8B"
        )
        XCTAssertEqual(request.value(forHTTPHeaderField: "User-Agent"), OJADClient.userAgent)
    }

    func testCharactersThatWouldBreakOJADsPathSyntaxAreDropped() async throws {
        let transport = try FixtureTransport(fixture: "search-taberu")
        _ = try await OJADClient.fixture(transport).searchWord("食べ/る,")

        XCTAssertEqual(
            transport.requests.first?.url?.absoluteString,
            "https://www.gavo.t.u-tokyo.ac.jp/ojad/search/index/curve:fujisaki/word:%E9%A3%9F%E3%81%B9%E3%82%8B"
        )
    }

    func testBlankQueryIsRejectedWithoutARequest() async throws {
        let transport = FixtureTransport(body: "")
        do {
            _ = try await OJADClient.fixture(transport).searchWord("  / ")
            XCTFail("expected an error")
        } catch {
            XCTAssertEqual(error as? OJADError, .invalidQuery)
        }
        XCTAssertTrue(transport.requests.isEmpty)
    }
}
