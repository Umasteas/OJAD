import Foundation
#if canImport(SQLite3)
import SQLite3
#else
import CSQLite
#endif

public enum SQLiteError: Error, Equatable, Sendable {
    case open(String)
    case prepare(String)
    case step(String)
}

/// A minimal read-only SQLite connection. Not thread-safe; callers serialize access.
final class SQLiteDatabase {
    private var handle: OpaquePointer?

    init(readOnly url: URL) throws {
        // `immutable=1` skips locking and journal checks: the bundled file never changes.
        // If a URI open is refused, fall back to a plain read-only open of the path.
        var components = URLComponents()
        components.scheme = "file"
        components.path = url.path
        components.queryItems = [URLQueryItem(name: "immutable", value: "1")]
        var failures: [String] = []
        for (path, flags) in [
            (components.string, SQLITE_OPEN_READONLY | SQLITE_OPEN_URI | SQLITE_OPEN_NOMUTEX),
            (url.path, SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX),
        ] {
            guard let path else { continue }
            if sqlite3_open_v2(path, &handle, flags, nil) == SQLITE_OK {
                break
            }
            failures.append(handle.map { String(cString: sqlite3_errmsg($0)) } ?? "cannot open")
            sqlite3_close(handle)
            handle = nil
        }
        guard handle != nil else {
            throw SQLiteError.open(failures.joined(separator: "; "))
        }
        // Map the file instead of copying pages through SQLite's cache.
        _ = try? query("PRAGMA mmap_size = 268435456") { _ in () }
    }

    deinit {
        sqlite3_close(handle)
    }

    enum Value {
        case int(Int)
        case text(String)
    }

    struct Row {
        fileprivate let statement: OpaquePointer

        func int(_ column: Int32) -> Int { Int(sqlite3_column_int64(statement, column)) }
        func isNull(_ column: Int32) -> Bool { sqlite3_column_type(statement, column) == SQLITE_NULL }

        func text(_ column: Int32) -> String? {
            sqlite3_column_text(statement, column).map { String(cString: $0) }
        }
    }

    func query<T>(_ sql: String, _ values: [Value] = [], _ read: (Row) throws -> T) throws -> [T] {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw SQLiteError.prepare(errorMessage)
        }
        defer { sqlite3_finalize(statement) }
        for (index, value) in values.enumerated() {
            let position = Int32(index + 1)
            switch value {
            case .int(let int): sqlite3_bind_int64(statement, position, sqlite3_int64(int))
            case .text(let text): sqlite3_bind_text(statement, position, text, -1, Self.transient)
            }
        }
        var rows: [T] = []
        while true {
            switch sqlite3_step(statement) {
            case SQLITE_ROW: rows.append(try read(Row(statement: statement)))
            case SQLITE_DONE: return rows
            default: throw SQLiteError.step(errorMessage)
            }
        }
    }

    private var errorMessage: String {
        handle.map { String(cString: sqlite3_errmsg($0)) } ?? "no connection"
    }

    /// `SQLITE_TRANSIENT`, which the C macro defines as `(sqlite3_destructor_type)-1`.
    private static let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
}
