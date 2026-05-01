//
//  SQLiteVisitedPostPersistenceTests.swift
//  nodeseekTests
//
//  Created by Codex on 2026/5/1.
//

import Foundation
import SQLite3
import Testing
@testable import nodeseek

@MainActor
struct SQLiteVisitedPostPersistenceTests {
    @Test func upsertAndLoadRecentReturnsNewestFirst() throws {
        let persistence = try makePersistence()
        let first = record(id: "1", title: "第一", visitedAt: Date(timeIntervalSince1970: 1))
        let second = record(id: "2", title: "第二", visitedAt: Date(timeIntervalSince1970: 2))

        try persistence.upsert(first)
        try persistence.upsert(second)

        let records = try persistence.loadRecent(limit: 10)
        #expect(records.map(\.postID) == ["2", "1"])
        #expect(records.map(\.title) == ["第二", "第一"])
    }

    @Test func upsertExistingRecordUpdatesMetadataAndVisitedAt() throws {
        let persistence = try makePersistence()
        try persistence.upsert(record(id: "1", title: "旧标题", visitedAt: Date(timeIntervalSince1970: 1)))

        try persistence.upsert(record(id: "1", title: "新标题", visitedAt: Date(timeIntervalSince1970: 3)))

        let records = try persistence.loadRecent(limit: 10)
        #expect(records.count == 1)
        #expect(records.first?.postID == "1")
        #expect(records.first?.title == "新标题")
        #expect(records.first?.visitedAt == Date(timeIntervalSince1970: 3))
    }

    @Test func trimKeepsOnlyLatestRecords() throws {
        let persistence = try makePersistence()
        try persistence.upsert(record(id: "1", visitedAt: Date(timeIntervalSince1970: 1)))
        try persistence.upsert(record(id: "2", visitedAt: Date(timeIntervalSince1970: 2)))
        try persistence.upsert(record(id: "3", visitedAt: Date(timeIntervalSince1970: 3)))

        try persistence.trim(keepingLatest: 2)

        let records = try persistence.loadRecent(limit: 10)
        #expect(records.map(\.postID) == ["3", "2"])
    }

    @Test func batchUpsertWritesRecordsAndTrimsOnce() throws {
        let persistence = try makePersistence()
        let first = record(id: "1", title: "第一", visitedAt: Date(timeIntervalSince1970: 1))
        let second = record(id: "2", title: "第二", visitedAt: Date(timeIntervalSince1970: 2))
        let third = record(id: "3", title: "第三", visitedAt: Date(timeIntervalSince1970: 3))

        try persistence.upsert([first, second, third], keepingLatest: 2)

        let records = try persistence.loadRecent(limit: 10)
        #expect(records.map(\.postID) == ["3", "2"])
    }

    @Test func batchUpsertRollsBackInsertedRecordsWhenOneRecordFails() throws {
        let fixture = try makePersistenceFixture()
        try installRejectingTitleTrigger(databaseURL: fixture.databaseURL)
        let accepted = record(id: "1", title: "可写入", visitedAt: Date(timeIntervalSince1970: 1))
        let rejected = record(id: "2", title: "拒绝", visitedAt: Date(timeIntervalSince1970: 2))

        #expect(throws: SQLiteVisitedPostPersistenceError.self) {
            try fixture.persistence.upsert([accepted, rejected], keepingLatest: 10)
        }

        let records = try fixture.persistence.loadRecent(limit: 10)
        #expect(records.isEmpty)
    }
}

private func makePersistence() throws -> SQLiteVisitedPostPersistence {
    try makePersistenceFixture().persistence
}

private struct SQLiteVisitedPostPersistenceFixture {
    let persistence: SQLiteVisitedPostPersistence
    let databaseURL: URL
}

private func makePersistenceFixture() throws -> SQLiteVisitedPostPersistenceFixture {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let databaseURL = directory.appendingPathComponent("visited-posts.sqlite3")
    return try SQLiteVisitedPostPersistenceFixture(
        persistence: SQLiteVisitedPostPersistence(databaseURL: databaseURL),
        databaseURL: databaseURL
    )
}

private func installRejectingTitleTrigger(databaseURL: URL) throws {
    var database: OpaquePointer?
    guard sqlite3_open_v2(databaseURL.path, &database, SQLITE_OPEN_READWRITE, nil) == SQLITE_OK else {
        throw SQLiteVisitedPostPersistenceError.openFailed("Unable to open test database")
    }
    defer { sqlite3_close(database) }

    let sql = """
    CREATE TRIGGER reject_visited_post_title
    BEFORE INSERT ON visited_posts
    WHEN NEW.title = '拒绝'
    BEGIN
        SELECT RAISE(FAIL, 'reject visited post');
    END;
    """
    guard sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK else {
        let message = sqlite3_errmsg(database).map { String(cString: $0) } ?? "Unknown SQLite error"
        throw SQLiteVisitedPostPersistenceError.stepFailed(message)
    }
}

private func record(
    id: String,
    title: String = "标题",
    visitedAt: Date
) -> VisitedPostRecord {
    VisitedPostRecord(
        postID: id,
        title: title,
        url: URL(string: "https://www.nodeseek.com/post-\(id)")!,
        visitedAt: visitedAt
    )
}
