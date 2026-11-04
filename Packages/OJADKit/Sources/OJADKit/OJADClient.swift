import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public enum OJADError: Error, Equatable, Sendable {
    /// The query is empty once characters OJAD's URL scheme can't carry are removed.
    case invalidQuery
    case httpStatus(Int)
    /// The page doesn't look like an OJAD search result; the site layout probably changed.
    case unexpectedPage
}

/// Client for OJAD (Online Japanese Accent Dictionary, University of Tokyo).
///
/// Sends one request per call and never touches OJAD's speech-synthesis endpoints.
/// Callers should only invoke it on explicit user action and cache results.
public struct OJADClient: Sendable {
    public typealias Transport = @Sendable (URLRequest) async throws -> (Data, URLResponse)

    public static let baseURL = URL(string: "https://www.gavo.t.u-tokyo.ac.jp/ojad/")!
    public static let userAgent = "OJADPersonal/1.0 (personal study app; +https://github.com/Umasteas/OJAD)"

    private let transport: Transport

    public init(transport: @escaping Transport) {
        self.transport = transport
    }

    public init(session: URLSession = .shared) {
        self.init(transport: { try await session.data(for: $0) })
    }

    /// Looks up a word (kanji or kana) in 単語検索 and returns every matching row.
    /// An unknown word yields an empty array, not an error.
    public func searchWord(_ query: String) async throws -> [WordEntry] {
        let request = try Self.searchRequest(for: query)
        let (data, response) = try await transport(request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw OJADError.httpStatus(http.statusCode)
        }
        guard let html = String(data: data, encoding: .utf8) else { throw OJADError.unexpectedPage }
        return try WordSearchParser.parse(html: html)
    }

    /// OJAD takes CakePHP named params in the path (`/word:食べる`), so `/` would end
    /// the param, `,` would turn it into a batch query, and `:` would start a new key.
    static func searchRequest(for query: String) throws -> URLRequest {
        let word = query
            .components(separatedBy: CharacterSet(charactersIn: "/,:、，\\?#%").union(.whitespacesAndNewlines))
            .joined()
        guard !word.isEmpty,
              let encoded = word.addingPercentEncoding(withAllowedCharacters: .alphanumerics)
        else { throw OJADError.invalidQuery }

        let url = URL(string: "search/index/curve:fujisaki/word:\(encoded)", relativeTo: baseURL)!.absoluteURL
        var request = URLRequest(url: url, timeoutInterval: 20)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("ja,zh-Hans;q=0.8,en;q=0.5", forHTTPHeaderField: "Accept-Language")
        return request
    }
}
