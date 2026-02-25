import Foundation
import GRDB
import Database

/// Repository for watch progress CRUD and queries.
/// Wraps DatabaseManager for typed access to WatchProgressRecord.
public struct WatchProgressRepository: Sendable {
    private let dbManager: DatabaseManager

    public init(dbManager: DatabaseManager) {
        self.dbManager = dbManager
    }

    // MARK: - CRUD

    /// Inserts or updates a watch progress record (upsert by content_id primary key).
    public func upsert(_ record: WatchProgressRecord) throws {
        try dbManager.dbQueue.write { db in
            try record.save(db)
        }
    }

    /// Fetches watch progress for a content ID, or nil if not found.
    public func get(contentID: String) throws -> WatchProgressRecord? {
        try dbManager.dbQueue.read { db in
            try WatchProgressRecord.fetchOne(db, key: contentID)
        }
    }

    /// Deletes watch progress for a content ID.
    public func delete(contentID: String) throws {
        try dbManager.dbQueue.write { db in
            _ = try WatchProgressRecord.deleteOne(db, key: contentID)
        }
    }

    /// Deletes all watch progress records.
    public func deleteAll() throws {
        try dbManager.dbQueue.write { db in
            _ = try WatchProgressRecord.deleteAll(db)
        }
    }

    // MARK: - Queries

    /// Returns recently watched items ordered by updatedAt DESC.
    public func getRecentlyWatched(limit: Int = 20) throws -> [WatchProgressRecord] {
        try dbManager.dbQueue.read { db in
            try WatchProgressRecord
                .order(Column("updated_at").desc)
                .limit(limit)
                .fetchAll(db)
        }
    }

    /// Returns items with unfinished playback (position > 0, not within last 30s of duration).
    public func getUnfinished(limit: Int = 20) throws -> [WatchProgressRecord] {
        try dbManager.dbQueue.read { db in
            try WatchProgressRecord
                .filter(Column("position_ms") > 0)
                .filter(Column("duration_ms") != nil)
                .filter(Column("position_ms") < Column("duration_ms") - 30_000)
                .order(Column("updated_at").desc)
                .limit(limit)
                .fetchAll(db)
        }
    }

    /// Fetches progress for multiple content IDs, returned as a dictionary.
    public func getBatch(contentIDs: [String]) throws -> [String: WatchProgressRecord] {
        guard !contentIDs.isEmpty else { return [:] }
        return try dbManager.dbQueue.read { db in
            let records = try WatchProgressRecord
                .filter(contentIDs.contains(Column("content_id")))
                .fetchAll(db)
            return Dictionary(uniqueKeysWithValues: records.map { ($0.contentID, $0) })
        }
    }

    /// Hard-deletes records older than the given timestamp. Returns number deleted.
    @discardableResult
    public func purgeOlderThan(_ timestamp: Int) throws -> Int {
        try dbManager.dbQueue.write { db in
            try WatchProgressRecord
                .filter(Column("updated_at") < timestamp)
                .deleteAll(db)
        }
    }
}
