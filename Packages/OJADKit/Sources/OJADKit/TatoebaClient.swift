import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public enum TatoebaError: Error, Equatable, Sendable {
    case invalidQuery
    case httpStatus(Int)
    case unexpectedResponse
}

/// A Japanese sentence from Tatoeba (CC BY 2.0 FR; show `owner` and link `url`).
public struct ExampleSentence: Sendable, Hashable, Codable, Identifiable {
    public let id: Int
    public let text: String
    public let owner: String?
    public let license: String?
    public let translations: [Translation]

    public init(id: Int, text: String, owner: String?, license: String?, translations: [Translation]) {
        self.id = id
        self.text = text
        self.owner = owner
        self.license = license
        self.translations = translations
    }

    public var url: URL { URL(string: "https://tatoeba.org/sentences/show/\(id)")! }

    /// Simplified Chinese first, then any Chinese, then English.
    public var preferredTranslation: Translation? {
        translations.first { $0.lang == "cmn" && $0.script == "Hans" }
            ?? translations.first { $0.lang == "cmn" }
            ?? translations.first { $0.lang == "eng" }
            ?? translations.first
    }

    public struct Translation: Sendable, Hashable, Codable {
        public let id: Int
        public let text: String
        public let lang: String
        public let script: String?
        public let owner: String?

        public init(id: Int, text: String, lang: String, script: String?, owner: String?) {
            self.id = id
            self.text = text
            self.lang = lang
            self.script = script
            self.owner = owner
        }
    }
}

/// Client for Tatoeba's public, read-only sentence search (`/v1/sentences`).
public struct TatoebaClient: Sendable {
    public static let baseURL = URL(string: "https://api.tatoeba.org/v1/sentences")!

    private let transport: OJADClient.Transport

    public init(transport: @escaping OJADClient.Transport) {
        self.transport = transport
    }

    public init(session: URLSession = .shared) {
        self.init(transport: { try await session.data(for: $0) })
    }

    /// Approved Japanese sentences containing `word` that have a Chinese or English
    /// translation, most relevant first.
    public func exampleSentences(containing word: String, limit: Int = 10) async throws -> [ExampleSentence] {
        let request = try Self.searchRequest(for: word, limit: limit)
        let (data, response) = try await transport(request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw TatoebaError.httpStatus(http.statusCode)
        }
        do {
            return try JSONDecoder().decode(SearchResponse.self, from: data).data.map(\.sentence)
        } catch {
            throw TatoebaError.unexpectedResponse
        }
    }

    /// Characters with a meaning in ManticoreSearch's query syntax.
    private static let syntaxCharacters = CharacterSet(charactersIn: "!\"$'()-/<>@\\^|~=&*?:,[]{}%#")

    static func searchRequest(for word: String, limit: Int) throws -> URLRequest {
        let term = word.components(separatedBy: syntaxCharacters.union(.whitespacesAndNewlines)).joined()
        guard !term.isEmpty else { throw TatoebaError.invalidQuery }

        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "q", value: "\"\(term)\""),
            URLQueryItem(name: "lang", value: "jpn"),
            URLQueryItem(name: "sort", value: "relevance"),
            // Japanese has no word boundaries, so Tatoeba counts characters here.
            URLQueryItem(name: "word_count", value: "6-40"),
            URLQueryItem(name: "is_orphan", value: "no"),
            URLQueryItem(name: "is_unapproved", value: "no"),
            URLQueryItem(name: "trans:lang", value: "cmn,eng"),
            URLQueryItem(name: "trans:is_unapproved", value: "no"),
            URLQueryItem(name: "showtrans", value: "matching"),
            URLQueryItem(name: "limit", value: String(limit)),
        ]
        var request = URLRequest(url: components.url!, timeoutInterval: 20)
        request.setValue(OJADClient.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }

    private struct SearchResponse: Decodable {
        let data: [Sentence]
    }

    private struct Sentence: Decodable {
        let id: Int
        let text: String
        let owner: String?
        let license: String?
        let translations: [Translation]?

        struct Translation: Decodable {
            let id: Int
            let text: String
            let lang: String
            let script: String?
            let owner: String?
        }

        var sentence: ExampleSentence {
            ExampleSentence(
                id: id, text: text, owner: owner, license: license,
                translations: (translations ?? []).map {
                    .init(id: $0.id, text: $0.text, lang: $0.lang, script: $0.script, owner: $0.owner)
                }
            )
        }
    }
}
