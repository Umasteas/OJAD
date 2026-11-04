import Foundation
import OJADKit
import SwiftData

@Model
final class HistoryEntry {
    @Attribute(.unique) var query: String
    var lastSearchedAt: Date
    /// First hit as shown in lists, e.g. `食べる・食べます　たべꜜる`; empty when nothing matched.
    var summary: String

    init(query: String, lastSearchedAt: Date, summary: String) {
        self.query = query
        self.lastSearchedAt = lastSearchedAt
        self.summary = summary
    }
}

@Model
final class FavoriteWord {
    @Attribute(.unique) var wordID: Int
    var headword: String
    var reading: String
    /// The whole `WordEntry`, so a favorite opens without a network request.
    var entryData: Data
    var addedAt: Date

    init(wordID: Int, headword: String, reading: String, entryData: Data, addedAt: Date) {
        self.wordID = wordID
        self.headword = headword
        self.reading = reading
        self.entryData = entryData
        self.addedAt = addedAt
    }

    var entry: WordEntry? { try? JSONDecoder().decode(WordEntry.self, from: entryData) }
}

/// Responses from OJAD and Tatoeba, kept indefinitely: both change rarely, and
/// asking again for the same thing only adds load on volunteer-run services.
@Model
final class CachedResponse {
    @Attribute(.unique) var key: String
    var payload: Data
    var fetchedAt: Date

    init(key: String, payload: Data, fetchedAt: Date) {
        self.key = key
        self.payload = payload
        self.fetchedAt = fetchedAt
    }
}

enum AppSchema {
    static let models: [any PersistentModel.Type] = [HistoryEntry.self, FavoriteWord.self, CachedResponse.self]

    static func container(inMemory: Bool = false) throws -> ModelContainer {
        if !inMemory {
            // SwiftData's default store lives here, but a fresh install has no such directory.
            try FileManager.default.createDirectory(at: .applicationSupportDirectory, withIntermediateDirectories: true)
        }
        return try ModelContainer(
            for: Schema(models),
            configurations: ModelConfiguration(isStoredInMemoryOnly: inMemory)
        )
    }
}
