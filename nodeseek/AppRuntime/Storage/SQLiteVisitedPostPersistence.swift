//
//  SQLiteVisitedPostPersistence.swift
//  nodeseek
//
//  Created by Codex on 2026/5/1.
//

import Foundation
import SQLite3

enum SQLiteVisitedPostPersistenceError: Error, Equatable {
    case openFailed(String)
    case prepareFailed(String)
    case stepFailed(String)
    case invalidStoredURL(String)
}

final class SQLiteVisitedPostPersistence: VisitedPostPersistence {
    private let databaseURL: URL
    private var database: OpaquePointer?

    init(databaseURL: URL) throws {
        self.databaseURL = databaseURL
        try FileManager.default.createDirectory(
            at: databaseURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try openDatabase()
        try createSchema()
    }

    deinit {
        sqlite3_close(database)
    }

    func loadRecent(limit: Int) throws -> [VisitedPostRecord] {
        let sql = """
        SELECT post_id, title, url, visited_at
        FROM visited_posts
        ORDER BY visited_at DESC
        LIMIT ?;
        """
        var statement: OpaquePointer?
        try prepare(sql, statement: &statement)
        defer { sqlite3_finalize(statement) }

        sqlite3_bind_int(statement, 1, Int32(max(0, limit)))

        var records: [VisitedPostRecord] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            let postID = textColumn(statement, index: 0)
            let title = textColumn(statement, index: 1)
            let urlString = textColumn(statement, index: 2)
            let visitedAt = Date(timeIntervalSince1970: sqlite3_column_double(statement, 3))
            guard let url = URL(string: urlString) else {
                throw SQLiteVisitedPostPersistenceError.invalidStoredURL(urlString)
            }
            records.append(VisitedPostRecord(
                postID: postID,
                title: title,
                url: url,
                visitedAt: visitedAt
            ))
        }

        return records
    }

    func upsert(_ record: VisitedPostRecord) throws {
        let sql = """
        INSERT INTO visited_posts (post_id, title, url, visited_at)
        VALUES (?, ?, ?, ?)
        ON CONFLICT(post_id) DO UPDATE SET
            title = excluded.title,
            url = excluded.url,
            visited_at = excluded.visited_at;
        """
        var statement: OpaquePointer?
        try prepare(sql, statement: &statement)
        defer { sqlite3_finalize(statement) }

        bind(record.postID, to: statement, index: 1)
        bind(record.title, to: statement, index: 2)
        bind(record.url.absoluteString, to: statement, index: 3)
        sqlite3_bind_double(statement, 4, record.visitedAt.timeIntervalSince1970)

        try stepDone(statement)
    }

    func trim(keepingLatest limit: Int) throws {
        let sql = """
        DELETE FROM visited_posts
        WHERE post_id NOT IN (
            SELECT post_id
            FROM visited_posts
            ORDER BY visited_at DESC
            LIMIT ?
        );
        """
        var statement: OpaquePointer?
        try prepare(sql, statement: &statement)
        defer { sqlite3_finalize(statement) }

        sqlite3_bind_int(statement, 1, Int32(max(0, limit)))
        try stepDone(statement)
    }

    static func defaultDatabaseURL() throws -> URL {
        let baseURL = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return baseURL
            .appendingPathComponent("NodeSeek", isDirectory: true)
            .appendingPathComponent("visited-posts.sqlite3")
    }

    private func openDatabase() throws {
        let flags = SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX
        guard sqlite3_open_v2(databaseURL.path, &database, flags, nil) == SQLITE_OK else {
            let message = databaseMessage()
            sqlite3_close(database)
            database = nil
            throw SQLiteVisitedPostPersistenceError.openFailed(message)
        }
    }

    private func createSchema() throws {
        try execute("""
        CREATE TABLE IF NOT EXISTS visited_posts (
            post_id TEXT PRIMARY KEY,
            title TEXT NOT NULL,
            url TEXT NOT NULL,
            visited_at REAL NOT NULL
        );
        """)
        try execute("""
        CREATE INDEX IF NOT EXISTS idx_visited_posts_visited_at
        ON visited_posts(visited_at DESC);
        """)
    }

    private func execute(_ sql: String) throws {
        guard sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK else {
            throw SQLiteVisitedPostPersistenceError.stepFailed(databaseMessage())
        }
    }

    private func prepare(_ sql: String, statement: inout OpaquePointer?) throws {
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else {
            throw SQLiteVisitedPostPersistenceError.prepareFailed(databaseMessage())
        }
    }

    private func stepDone(_ statement: OpaquePointer?) throws {
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw SQLiteVisitedPostPersistenceError.stepFailed(databaseMessage())
        }
    }

    private func bind(_ string: String, to statement: OpaquePointer?, index: Int32) {
        sqlite3_bind_text(statement, index, string, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
    }

    private func textColumn(_ statement: OpaquePointer?, index: Int32) -> String {
        guard let text = sqlite3_column_text(statement, index) else { return "" }
        return String(cString: text)
    }

    private func databaseMessage() -> String {
        guard let database, let message = sqlite3_errmsg(database) else {
            return "Unknown SQLite error"
        }
        return String(cString: message)
    }
}

extension VisitedPostStore {
    static let shared: VisitedPostStore = {
        do {
            let persistence = try SQLiteVisitedPostPersistence(databaseURL: SQLiteVisitedPostPersistence.defaultDatabaseURL())
            return VisitedPostStore(persistence: persistence)
        } catch {
            return VisitedPostStore(persistence: NoopVisitedPostPersistence())
        }
    }()
}

private final class NoopVisitedPostPersistence: VisitedPostPersistence {
    func loadRecent(limit: Int) throws -> [VisitedPostRecord] {
        []
    }

    func upsert(_ record: VisitedPostRecord) throws {
    }

    func trim(keepingLatest limit: Int) throws {
    }
}
