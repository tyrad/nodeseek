//
//  VisitedPostStore.swift
//  nodeseek
//
//  Created by Codex on 2026/5/1.
//

import Foundation

struct VisitedPostRecord: Equatable, Sendable {
    let postID: String
    let title: String
    let url: URL
    let visitedAt: Date
}

struct PostListItem: Equatable, Sendable {
    let post: PostSummary
    let isVisited: Bool
}

@MainActor
protocol VisitedPostStoreProtocol: AnyObject {
    func isVisited(postID: String) -> Bool
    func markVisited(post: PostSummary, visitedAt: Date)
    func recentRecords(limit: Int) -> [VisitedPostRecord]
}

protocol VisitedPostPersistence: AnyObject, Sendable {
    func loadRecent(limit: Int) throws -> [VisitedPostRecord]
    func upsert(_ record: VisitedPostRecord) throws
    func upsert(_ records: [VisitedPostRecord], keepingLatest limit: Int) throws
    func trim(keepingLatest limit: Int) throws
}

@MainActor
final class VisitedPostStore: VisitedPostStoreProtocol {
    nonisolated static let defaultLimit = 1500

    private let persistence: VisitedPostPersistence
    private let limit: Int
    private let writeQueue: DispatchQueue
    private var records: [VisitedPostRecord]
    private var visitedIDs: Set<String>
    private var pendingRecords: [VisitedPostRecord] = []
    private var scheduledFlushWorkItem: DispatchWorkItem?

    init(
        persistence: VisitedPostPersistence,
        limit: Int = VisitedPostStore.defaultLimit,
        writeQueue: DispatchQueue = DispatchQueue(label: "com.nodeseek.app.visited-post-store")
    ) {
        self.persistence = persistence
        self.limit = limit
        self.writeQueue = writeQueue

        let loadedRecords = (try? persistence.loadRecent(limit: limit)) ?? []
        let trimmedRecords = Array(loadedRecords.prefix(limit))
        self.records = trimmedRecords
        self.visitedIDs = Set(trimmedRecords.map(\.postID))
    }

    func isVisited(postID: String) -> Bool {
        visitedIDs.contains(postID)
    }

    func markVisited(post: PostSummary, visitedAt: Date) {
        let record = VisitedPostRecord(
            postID: post.id,
            title: post.title,
            url: post.url,
            visitedAt: visitedAt
        )

        records.removeAll { $0.postID == record.postID }
        records.insert(record, at: 0)
        if records.count > limit {
            records = Array(records.prefix(limit))
        }
        visitedIDs = Set(records.map(\.postID))

        pendingRecords.append(record)
        scheduleFlush()
    }

    func recentRecords(limit: Int) -> [VisitedPostRecord] {
        Array(records.prefix(limit))
    }

    func flush() {
        scheduledFlushWorkItem?.cancel()
        scheduledFlushWorkItem = nil
        flushPendingRecords()
    }

    private func scheduleFlush() {
        scheduledFlushWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            Task { @MainActor [weak self] in
                self?.flushPendingRecords()
            }
        }
        scheduledFlushWorkItem = workItem
        writeQueue.asyncAfter(deadline: .now() + 0.5, execute: workItem)
    }

    private func flushPendingRecords() {
        guard !pendingRecords.isEmpty else { return }
        let recordsToPersist = coalescedPendingRecords(pendingRecords)
        pendingRecords.removeAll()
        let persistence = persistence
        let limit = limit

        writeQueue.async {
            do {
                try persistence.upsert(recordsToPersist, keepingLatest: limit)
            } catch {
                // UI 已经按内存状态更新，持久化失败不回滚用户可见状态。
            }
        }
    }

    private func coalescedPendingRecords(_ records: [VisitedPostRecord]) -> [VisitedPostRecord] {
        var orderedIDs: [String] = []
        var latestRecordByID: [String: VisitedPostRecord] = [:]

        for record in records {
            if latestRecordByID[record.postID] == nil {
                orderedIDs.append(record.postID)
            }
            if let existing = latestRecordByID[record.postID],
               existing.visitedAt > record.visitedAt {
                continue
            }
            latestRecordByID[record.postID] = record
        }

        return orderedIDs.compactMap { latestRecordByID[$0] }
    }
}

@MainActor
final class EmptyVisitedPostStore: VisitedPostStoreProtocol {
    nonisolated init() {}

    func isVisited(postID: String) -> Bool {
        false
    }

    func markVisited(post: PostSummary, visitedAt: Date) {
    }

    func recentRecords(limit: Int) -> [VisitedPostRecord] {
        []
    }
}
