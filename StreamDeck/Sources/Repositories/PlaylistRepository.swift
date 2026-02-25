import Foundation
import GRDB
import Database

/// Repository for playlist CRUD operations and sync tracking.
/// Wraps DatabaseManager for typed access to PlaylistRecord.
public struct PlaylistRepository: Sendable {
    private let dbManager: DatabaseManager

    public init(dbManager: DatabaseManager) {
        self.dbManager = dbManager
    }

    // MARK: - CRUD

    /// Inserts a new playlist record.
    public func create(_ record: PlaylistRecord) throws {
        try dbManager.dbQueue.write { db in
            try record.insert(db)
        }
    }

    /// Fetches a single playlist by ID, or nil if not found.
    public func get(id: String) throws -> PlaylistRecord? {
        try dbManager.dbQueue.read { db in
            try PlaylistRecord.fetchOne(db, key: id)
        }
    }

    /// Fetches all playlists ordered by sortOrder ascending.
    public func getAll() throws -> [PlaylistRecord] {
        try dbManager.dbQueue.read { db in
            try PlaylistRecord
                .order(Column("sort_order").asc)
                .fetchAll(db)
        }
    }

    /// Updates an existing playlist record.
    public func update(_ record: PlaylistRecord) throws {
        try dbManager.dbQueue.write { db in
            try record.update(db)
        }
    }

    /// Deletes a playlist by ID. Cascades to channels, VOD items, and watch progress.
    public func delete(id: String) throws {
        try dbManager.dbQueue.write { db in
            _ = try PlaylistRecord.deleteOne(db, key: id)
        }
    }

    // MARK: - Sync Tracking

    /// Updates sync metadata after a successful playlist refresh.
    public func updateSyncTimestamp(
        _ playlistID: String,
        timestamp: Int,
        etag: String? = nil,
        hash: String? = nil
    ) throws {
        try dbManager.dbQueue.write { db in
            guard var record = try PlaylistRecord.fetchOne(db, key: playlistID) else { return }
            record.lastSync = timestamp
            if let etag { record.lastSyncEtag = etag }
            if let hash { record.lastSyncHash = hash }
            try record.update(db)
        }
    }

    /// Returns true if the playlist needs a refresh based on its refreshHrs interval.
    /// A playlist needs refresh if it has never been synced or if
    /// `lastSync + (refreshHrs * 3600)` is less than the current time.
    public func needsRefresh(_ playlistID: String, now: Int? = nil) throws -> Bool {
        try dbManager.dbQueue.read { db in
            guard let record = try PlaylistRecord.fetchOne(db, key: playlistID) else { return false }
            guard let lastSync = record.lastSync else { return true }
            let currentTime = now ?? Int(Date().timeIntervalSince1970)
            return lastSync + (record.refreshHrs * 3600) < currentTime
        }
    }
}
