import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import OJADKit

enum Fixture {
    static func data(_ name: String, ext: String = "html") throws -> Data {
        guard let url = Bundle.module.url(forResource: name, withExtension: ext, subdirectory: "Fixtures") else {
            throw CocoaError(.fileNoSuchFile)
        }
        return try Data(contentsOf: url)
    }
}

/// Serves recorded OJAD pages and records the requests it was asked for.
final class FixtureTransport: @unchecked Sendable {
    private let lock = NSLock()
    private var _requests: [URLRequest] = []
    private let body: Data
    private let status: Int

    init(fixture: String, ext: String = "html", status: Int = 200) throws {
        self.body = try Fixture.data(fixture, ext: ext)
        self.status = status
    }

    init(body: String, status: Int = 200) {
        self.body = Data(body.utf8)
        self.status = status
    }

    var requests: [URLRequest] { lock.withLock { _requests } }

    func callAsFunction(_ request: URLRequest) async throws -> (Data, URLResponse) {
        lock.withLock { _requests.append(request) }
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: nil)!
        return (body, response)
    }
}

extension OJADClient {
    static func fixture(_ transport: FixtureTransport) -> OJADClient {
        OJADClient(transport: { try await transport($0) })
    }
}
