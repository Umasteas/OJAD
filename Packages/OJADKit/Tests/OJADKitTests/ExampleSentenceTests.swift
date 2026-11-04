import XCTest
@testable import OJADKit

final class ExampleSentenceTests: XCTestCase {
    private func client(_ transport: FixtureTransport) -> TatoebaClient {
        TatoebaClient(transport: { try await transport($0) })
    }

    func testReturnsJapaneseSentencesWithAttribution() async throws {
        let transport = try FixtureTransport(fixture: "tatoeba-taberu", ext: "json")
        let sentences = try await client(transport).exampleSentences(containing: "食べる")

        XCTAssertEqual(sentences.count, 10)
        let first = try XCTUnwrap(sentences.first)
        XCTAssertEqual(first.id, 12047446)
        XCTAssertEqual(first.text, "プリン食べる？")
        XCTAssertEqual(first.owner, "small_snow")
        XCTAssertEqual(first.license, "CC BY 2.0 FR")
        XCTAssertEqual(first.url.absoluteString, "https://tatoeba.org/sentences/show/12047446")
    }

    func testPrefersSimplifiedChineseThenEnglishTranslation() async throws {
        let transport = try FixtureTransport(fixture: "tatoeba-taberu", ext: "json")
        let sentences = try await client(transport).exampleSentences(containing: "食べる")

        let ice = try XCTUnwrap(sentences.first { $0.id == 3699447 })
        XCTAssertEqual(ice.preferredTranslation?.text, "吃冰激淋吗！")
        let pudding = try XCTUnwrap(sentences.first { $0.id == 12047446 })
        XCTAssertEqual(pudding.preferredTranslation?.text, "Do you want some pudding?")
    }

    func testAsksForApprovedTranslatedSentencesOfReasonableLength() async throws {
        let transport = try FixtureTransport(fixture: "tatoeba-taberu", ext: "json")
        _ = try await client(transport).exampleSentences(containing: "食べる")

        let url = try XCTUnwrap(transport.requests.first?.url)
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        XCTAssertEqual(components.host, "api.tatoeba.org")
        XCTAssertEqual(components.path, "/v1/sentences")
        let query = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") })
        XCTAssertEqual(query["q"], "\"食べる\"")
        XCTAssertEqual(query["lang"], "jpn")
        XCTAssertEqual(query["trans:lang"], "cmn,eng")
        XCTAssertEqual(query["is_unapproved"], "no")
        XCTAssertEqual(query["is_orphan"], "no")
        XCTAssertEqual(query["sort"], "relevance")
        XCTAssertEqual(query["word_count"], "6-40")
        XCTAssertEqual(query["limit"], "10")
    }

    func testSearchSyntaxCharactersAreDropped() async throws {
        let transport = try FixtureTransport(fixture: "tatoeba-taberu", ext: "json")
        _ = try await client(transport).exampleSentences(containing: "食べ\"る(*)")

        let url = try XCTUnwrap(transport.requests.first?.url)
        let q = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "q" }?.value
        XCTAssertEqual(q, "\"食べる\"")
    }

    func testBlankWordIsRejectedWithoutARequest() async throws {
        let transport = FixtureTransport(body: "")
        do {
            _ = try await client(transport).exampleSentences(containing: "  ")
            XCTFail("expected an error")
        } catch {
            XCTAssertEqual(error as? TatoebaError, .invalidQuery)
        }
        XCTAssertTrue(transport.requests.isEmpty)
    }

    func testServerErrorIsSurfaced() async throws {
        let transport = FixtureTransport(body: "{\"message\":\"oops\"}", status: 500)
        do {
            _ = try await client(transport).exampleSentences(containing: "食べる")
            XCTFail("expected an error")
        } catch {
            XCTAssertEqual(error as? TatoebaError, .httpStatus(500))
        }
    }
}
