//
//  VisitedPostStoreTests.swift
//  nodeseekTests
//
//  Created by Codex on 2026/5/1.
//

import Foundation
import Testing
@testable import nodeseek

@MainActor
struct VisitedPostStoreTests {
    @Test func initializationLoadsOnlyConfiguredRecentLimit() {
        let records = (0..<5).map { index in
            record(id: "\(index)", visitedAt: Date(timeIntervalSince1970: TimeInterval(index)))
        }
        let persistence = SpyVisitedPostPersistence(records: records)

        let store = VisitedPostStore(persistence: persistence, limit: 3)

        #expect(persistence.loadLimits == [3])
        #expect(store.recentRecords(limit: 10).map(\.postID) == ["0", "1", "2"])
        #expect(store.isVisited(postID: "0"))
        #expect(!store.isVisited(postID: "4"))
    }

    @Test func markVisitedUpdatesMemoryImmediatelyAndPersistsAsynchronously() {
        let persistence = SpyVisitedPostPersistence(records: [])
        let writeQueue = DispatchQueue(label: "VisitedPostStoreTests.markVisited")
        let store = VisitedPostStore(persistence: persistence, limit: 3, writeQueue: writeQueue)
        let post = post(id: "1", title: "标题")
        let visitedAt = Date(timeIntervalSince1970: 100)

        store.markVisited(post: post, visitedAt: visitedAt)

        #expect(store.isVisited(postID: "1"))
        #expect(store.recentRecords(limit: 1).first?.postID == "1")
        #expect(store.recentRecords(limit: 1).first?.title == "标题")

        store.flush()
        writeQueue.sync {}

        #expect(persistence.persistedBatches.map { $0.records.map(\.postID) } == [["1"]])
        #expect(persistence.persistedBatches.map(\.limit) == [3])
    }

    @Test func flushCoalescesRepeatedPendingRecordsByLatestVisit() {
        let persistence = SpyVisitedPostPersistence(records: [])
        let writeQueue = DispatchQueue(label: "VisitedPostStoreTests.coalesce")
        let store = VisitedPostStore(persistence: persistence, limit: 3, writeQueue: writeQueue)

        store.markVisited(post: post(id: "1", title: "旧标题"), visitedAt: Date(timeIntervalSince1970: 100))
        store.markVisited(post: post(id: "2", title: "其他"), visitedAt: Date(timeIntervalSince1970: 150))
        store.markVisited(post: post(id: "1", title: "新标题"), visitedAt: Date(timeIntervalSince1970: 200))
        store.flush()
        writeQueue.sync {}

        #expect(persistence.persistedBatches.count == 1)
        let records = persistence.persistedBatches.first?.records ?? []
        #expect(Set(records.map(\.postID)) == Set(["1", "2"]))
        #expect(records.first(where: { $0.postID == "1" })?.title == "新标题")
        #expect(records.first(where: { $0.postID == "1" })?.visitedAt == Date(timeIntervalSince1970: 200))
        #expect(persistence.persistedBatches.first?.limit == 3)
    }

    @Test func repeatedVisitMovesRecordToFrontAndUpdatesMetadata() {
        let old = record(id: "1", title: "旧标题", visitedAt: Date(timeIntervalSince1970: 1))
        let other = record(id: "2", title: "其他", visitedAt: Date(timeIntervalSince1970: 2))
        let persistence = SpyVisitedPostPersistence(records: [other, old])
        let store = VisitedPostStore(persistence: persistence, limit: 3)
        let post = post(id: "1", title: "新标题")

        store.markVisited(post: post, visitedAt: Date(timeIntervalSince1970: 3))

        let records = store.recentRecords(limit: 3)
        #expect(records.map(\.postID) == ["1", "2"])
        #expect(records.first?.title == "新标题")
        #expect(records.first?.visitedAt == Date(timeIntervalSince1970: 3))
    }

    @Test func markVisitedTrimsMemoryToLatestLimit() {
        let first = record(id: "1", visitedAt: Date(timeIntervalSince1970: 1))
        let second = record(id: "2", visitedAt: Date(timeIntervalSince1970: 2))
        let persistence = SpyVisitedPostPersistence(records: [second, first])
        let store = VisitedPostStore(persistence: persistence, limit: 2)

        store.markVisited(post: post(id: "3", title: "第三"), visitedAt: Date(timeIntervalSince1970: 3))

        #expect(store.recentRecords(limit: 10).map(\.postID) == ["3", "2"])
        #expect(store.isVisited(postID: "3"))
        #expect(store.isVisited(postID: "2"))
        #expect(!store.isVisited(postID: "1"))
    }
}

@MainActor
private final class SpyVisitedPostPersistence: VisitedPostPersistence {
    struct PersistedBatch: Equatable {
        let records: [VisitedPostRecord]
        let limit: Int
    }

    var records: [VisitedPostRecord]
    var loadLimits: [Int] = []
    var persistedBatches: [PersistedBatch] = []

    init(records: [VisitedPostRecord]) {
        self.records = records
    }

    func loadRecent(limit: Int) throws -> [VisitedPostRecord] {
        loadLimits.append(limit)
        return Array(records.prefix(limit))
    }

    func upsert(_ record: VisitedPostRecord) throws {
        persistedBatches.append(PersistedBatch(records: [record], limit: -1))
    }

    func trim(keepingLatest limit: Int) throws {
        persistedBatches.append(PersistedBatch(records: [], limit: limit))
    }

    func upsert(_ records: [VisitedPostRecord], keepingLatest limit: Int) throws {
        persistedBatches.append(PersistedBatch(records: records, limit: limit))
    }
}

private func post(id: String, title: String) -> PostSummary {
    PostSummary(
        id: id,
        title: title,
        url: URL(string: "https://www.nodeseek.com/post-\(id)")!,
        authorName: "mist",
        nodeName: "开发",
        replyCount: 1,
        lastActivityText: "刚刚"
    )
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
