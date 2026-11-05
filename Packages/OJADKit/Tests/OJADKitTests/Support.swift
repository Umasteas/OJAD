import Foundation
@testable import OJADKit

enum Fixture {
    static func data(_ name: String, ext: String = "json") throws -> Data {
        guard let url = Bundle.module.url(forResource: name, withExtension: ext, subdirectory: "Fixtures") else {
            throw CocoaError(.fileNoSuchFile)
        }
        return try Data(contentsOf: url)
    }
}
