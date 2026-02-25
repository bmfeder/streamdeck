import Foundation
import GRDB
import Database

/// Result of a batch channel import operation.
public struct ImportResult: Equatable, Sendable {
    public let added: Int
    public let updated: Int
    public let softDeleted: Int
    public let unchanged: Int

    public init(added: Int, updated: Int, softDeleted: Int, unchanged: Int) {
        self.added = added
        self.updated = updated
        self.softDeleted = softDeleted
        self.unchanged = unchanged
    }
}

/// Repository for channel CRUD, identity matching, batch import, and UI queries.
/// Wraps DatabaseManager for typed access to ChannelRecord.
public struct ChannelRepository: Sendable {
    private let dbManager: DatabaseManager

    public init(dbManager: DatabaseManager) {
        self.dbManager = dbManager
    }

    // MARK: - CRUD

    /// Inserts a new channel record.
    public func create(_ record: ChannelRecord) throws {
        try dbManager.dbQueue.write { db in
            try record.insert(db)
        }
    }

    /// Fetches a single channel by ID, or nil if not found.
    public func get(id: String) throws -> ChannelRecord? {
        try dbManager.dbQueue.read { db in
            try ChannelRecord.fetchOne(db, key: id)
        }
    }

    /// Updates an existing channel record.
    public func update(_ record: ChannelRecord) throws {
        try dbManager.dbQueue.write { db in
            try record.update(db)
        }
    }

    /// Hard-deletes a channel by ID.
    public func delete(id: String) throws {
        try dbManager.dbQueue.write { db in
            _ = try ChannelRecord.deleteOne(db, key: id)
        }
    }

    // MARK: - Identity Matching (Three-Tier Strategy)

    /// Tier 1: Match by playlist + source channel ID (provider's native ID).
    public func findBySourceID(playlistID: String, sourceChannelID: String) throws -> ChannelRecord? {
        try dbManager.dbQueue.read { db in
            try ChannelRecord
                .filter(Column("playlist_id") == playlistID && Column("source_channel_id") == sourceChannelID)
                .fetchOne(db)
        }
    }

    /// Tier 2: Match by playlist + tvg ID.
    public func findByTvgID(playlistID: String, tvgID: String) throws -> ChannelRecord? {
        try dbManager.dbQueue.read { db in
            try ChannelRecord
                .filter(Column("playlist_id") == playlistID && Column("tvg_id") == tvgID)
                .fetchOne(db)
        }
    }

    /// Tier 3: Match by playlist + name + optional group name.
    public func findByNameAndGroup(playlistID: String, name: String, groupName: String?) throws -> ChannelRecord? {
        try dbManager.dbQueue.read { db in
            if let groupName {
                return try ChannelRecord
                    .filter(Column("playlist_id") == playlistID && Column("name") == name && Column("group_name") == groupName)
                    .fetchOne(db)
            } else {
                return try ChannelRecord
                    .filter(Column("playlist_id") == playlistID && Column("name") == name && Column("group_name") == nil)
                    .fetchOne(db)
            }
        }
    }

    // MARK: - Batch Import

    /// Imports channels using the three-tier identity matching strategy.
    ///
    /// For each incoming channel:
    /// 1. Try tier 1: match by (playlistID, sourceChannelID)
    /// 2. Try tier 2: match by (playlistID, tvgID)
    /// 3. Try tier 3: match by (playlistID, name, groupName)
    /// 4. If matched: update mutable fields, keep canonical ID
    /// 5. If not matched: insert new record
    /// 6. Soft-delete existing channels not seen in the incoming batch
    ///
    /// All operations run in a single transaction for atomicity.
    public func importChannels(playlistID: String, channels: [ChannelRecord], now: Int? = nil) throws -> ImportResult {
        try dbManager.dbQueue.write { db in
            let currentTime = now ?? Int(Date().timeIntervalSince1970)

            // Fetch all existing channels for this playlist (including soft-deleted for re-activation)
            let existing = try ChannelRecord
                .filter(Column("playlist_id") == playlistID)
                .fetchAll(db)

            // Build lookup dictionaries
            var bySourceID: [String: ChannelRecord] = [:]
            var byTvgID: [String: ChannelRecord] = [:]
            var byNameGroup: [String: ChannelRecord] = [:]

            for channel in existing {
                if let sourceID = channel.sourceChannelID, !sourceID.isEmpty {
                    bySourceID[sourceID] = channel
                }
                if let tvgID = channel.tvgID, !tvgID.isEmpty {
                    byTvgID[tvgID] = channel
                }
                let key = nameGroupKey(name: channel.name, groupName: channel.groupName)
                byNameGroup[key] = channel
            }

            var added = 0
            var updated = 0
            var unchanged = 0
            var seenIDs: Set<String> = []

            for incoming in channels {
                // Try three-tier matching
                var match: ChannelRecord?

                if let sourceID = incoming.sourceChannelID, !sourceID.isEmpty {
                    match = bySourceID[sourceID]
                }
                if match == nil, let tvgID = incoming.tvgID, !tvgID.isEmpty {
                    match = byTvgID[tvgID]
                }
                if match == nil {
                    let key = nameGroupKey(name: incoming.name, groupName: incoming.groupName)
                    match = byNameGroup[key]
                }

                if var matched = match {
                    seenIDs.insert(matched.id)

                    // Check if mutable fields changed
                    let changed = matched.streamURL != incoming.streamURL
                        || matched.logoURL != incoming.logoURL
                        || matched.name != incoming.name
                        || matched.groupName != incoming.groupName
                        || matched.epgID != incoming.epgID
                        || matched.tvgID != incoming.tvgID
                        || matched.channelNum != incoming.channelNum
                        || matched.sourceChannelID != incoming.sourceChannelID
                        || matched.isDeleted // re-activate soft-deleted

                    if changed {
                        matched.streamURL = incoming.streamURL
                        matched.logoURL = incoming.logoURL
                        matched.name = incoming.name
                        matched.groupName = incoming.groupName
                        matched.epgID = incoming.epgID
                        matched.tvgID = incoming.tvgID
                        matched.channelNum = incoming.channelNum
                        matched.sourceChannelID = incoming.sourceChannelID
                        matched.isDeleted = false
                        matched.deletedAt = nil
                        try matched.update(db)
                        updated += 1
                    } else {
                        unchanged += 1
                    }
                } else {
                    // Insert new channel
                    try incoming.insert(db)
                    seenIDs.insert(incoming.id)
                    added += 1
                }
            }

            // Soft-delete channels not seen in incoming batch
            let softDeleted = try softDeleteMissing(
                db: db,
                playlistID: playlistID,
                activeIDs: seenIDs,
                now: currentTime
            )

            return ImportResult(
                added: added,
                updated: updated,
                softDeleted: softDeleted,
                unchanged: unchanged
            )
        }
    }

    // MARK: - Soft Delete

    /// Soft-deletes active channels in a playlist that are not in the given ID set.
    /// Returns the number of channels soft-deleted.
    public func softDeleteMissing(playlistID: String, activeIDs: Set<String>, now: Int) throws -> Int {
        try dbManager.dbQueue.write { db in
            try softDeleteMissing(db: db, playlistID: playlistID, activeIDs: activeIDs, now: now)
        }
    }

    /// Hard-deletes channels that were soft-deleted before the given timestamp.
    /// Returns the number of channels purged.
    public func purgeDeleted(olderThan: Int) throws -> Int {
        try dbManager.dbQueue.write { db in
            try ChannelRecord
                .filter(Column("is_deleted") == true && Column("deleted_at") < olderThan)
                .deleteAll(db)
        }
    }

    // MARK: - UI Queries

    /// Fetches all active (non-deleted) channels for a playlist.
    public func getActive(playlistID: String) throws -> [ChannelRecord] {
        try dbManager.dbQueue.read { db in
            try ChannelRecord
                .filter(Column("playlist_id") == playlistID && Column("is_deleted") == false)
                .order(Column("name").asc)
                .fetchAll(db)
        }
    }

    /// Fetches active channels grouped by groupName for a playlist.
    public func getActiveGrouped(playlistID: String) throws -> [String: [ChannelRecord]] {
        let channels = try getActive(playlistID: playlistID)
        return Dictionary(grouping: channels) { $0.groupName ?? "" }
    }

    /// Fetches all favorite channels across all playlists (active only).
    public func getFavorites() throws -> [ChannelRecord] {
        try dbManager.dbQueue.read { db in
            try ChannelRecord
                .filter(Column("is_favorite") == true && Column("is_deleted") == false)
                .order(Column("name").asc)
                .fetchAll(db)
        }
    }

    /// Searches channels by name (case-insensitive LIKE).
    /// Optionally scoped to a specific playlist.
    public func search(query: String, playlistID: String? = nil) throws -> [ChannelRecord] {
        try dbManager.dbQueue.read { db in
            var request = ChannelRecord
                .filter(Column("is_deleted") == false)
                .filter(Column("name").like("%\(query)%"))

            if let playlistID {
                request = request.filter(Column("playlist_id") == playlistID)
            }

            return try request.order(Column("name").asc).fetchAll(db)
        }
    }

    /// Fetches a channel by its channel number within a playlist.
    public func getByNumber(playlistID: String, number: Int) throws -> ChannelRecord? {
        try dbManager.dbQueue.read { db in
            try ChannelRecord
                .filter(Column("playlist_id") == playlistID && Column("channel_num") == number && Column("is_deleted") == false)
                .fetchOne(db)
        }
    }

    // MARK: - Favorites

    /// Toggles the favorite status of a channel.
    public func toggleFavorite(id: String) throws {
        try dbManager.dbQueue.write { db in
            guard var record = try ChannelRecord.fetchOne(db, key: id) else { return }
            record.isFavorite = !record.isFavorite
            try record.update(db)
        }
    }

    // MARK: - Private Helpers

    /// Soft-deletes active channels not in the given set. For use inside a write transaction.
    @discardableResult
    private static func softDeleteMissingInTransaction(
        db: GRDB.Database,
        playlistID: String,
        activeIDs: Set<String>,
        now: Int
    ) throws -> Int {
        let toSoftDelete = try ChannelRecord
            .filter(Column("playlist_id") == playlistID && Column("is_deleted") == false)
            .fetchAll(db)
            .filter { !activeIDs.contains($0.id) }

        for var channel in toSoftDelete {
            channel.isDeleted = true
            channel.deletedAt = now
            try channel.update(db)
        }

        return toSoftDelete.count
    }

    /// Instance method wrapper for use inside write closures.
    private func softDeleteMissing(
        db: GRDB.Database,
        playlistID: String,
        activeIDs: Set<String>,
        now: Int
    ) throws -> Int {
        try Self.softDeleteMissingInTransaction(db: db, playlistID: playlistID, activeIDs: activeIDs, now: now)
    }
}

// MARK: - Helpers

private func nameGroupKey(name: String, groupName: String?) -> String {
    "\(name)|\(groupName ?? "")"
}
