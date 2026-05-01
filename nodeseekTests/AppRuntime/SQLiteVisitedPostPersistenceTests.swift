//
//  SQLiteVisitedPostPersistenceTests.swift
//  nodeseekTests
//
//  Created by Codex on 2026/5/1.
//

import Foundation
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
}

private func makePersistence() throws -> SQLiteVisitedPostPersistence {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let databaseURL = directory.appendingPathComponent("visited-posts.sqlite3")
    return try SQLiteVisitedPostPersistence(databaseURL: databaseURL)
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
