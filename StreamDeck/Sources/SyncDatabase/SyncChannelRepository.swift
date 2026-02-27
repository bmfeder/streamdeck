import Database
import Foundation
import PowerSync

/// PowerSync-backed channel repository. Same public API as ChannelRepository.
public struct SyncChannelRepository: Sendable {
    private let db: any PowerSyncDatabaseProtocol

    public init(db: any PowerSyncDatabaseProtocol) {
        self.db = db
    }

    // MARK: - CRUD

    public func create(_ record: ChannelRecord) async throws {
        let params = RecordMappers.channelParams(record)
        try await db.execute(
            sql: """
                INSERT INTO channels (id, playlist_id, source_channel_id, tvg_id, name,
                    group_name, epg_id, logo_url, stream_url, channel_number,
                    is_favorite, is_deleted, deleted_at)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
            parameters: [record.id] + params
        )
    }

    public func get(id: String) async throws -> ChannelRecord? {
        try await db.getOptional(
            sql: "SELECT * FROM channels WHERE id = ?",
            parameters: [id],
            mapper: RecordMappers.channelMapper
        )
    }

    public func update(_ record: ChannelRecord) async throws {
        let params = RecordMappers.channelParams(record)
        try await db.execute(
            sql: """
                UPDATE channels SET playlist_id = ?, source_channel_id = ?, tvg_id = ?,
                    name = ?, group_name = ?, epg_id = ?, logo_url = ?, stream_url = ?,
                    channel_number = ?, is_favorite = ?, is_deleted = ?, deleted_at = ?
                WHERE id = ?
                """,
            parameters: params + [record.id]
        )
    }

    public func delete(id: String) async throws {
        try await db.execute(sql: "DELETE FROM channels WHERE id = ?", parameters: [id])
    }

    // MARK: - Batch Import (Three-Tier Identity Matching)

    public func importChannels(playlistID: String, channels: [ChannelRecord], now: Int? = nil) async throws -> SyncImportResult {
        try await db.writeTransaction { tx in
            let currentTime = now ?? Int(Date().timeIntervalSince1970)

            // Fetch all existing channels for this playlist
            let existing = try tx.getAll(
                sql: "SELECT * FROM channels WHERE playlist_id = ?",
                parameters: [playlistID],
                mapper: RecordMappers.channelMapper
            )

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
                let key = "\(channel.name)|\(channel.groupName ?? "")"
                byNameGroup[key] = channel
            }

            var added = 0
            var updated = 0
            var unchanged = 0
            var seenIDs: Set<String> = []

            for incoming in channels {
                var match: ChannelRecord?

                if let sourceID = incoming.sourceChannelID, !sourceID.isEmpty {
                    match = bySourceID[sourceID]
                }
                if match == nil, let tvgID = incoming.tvgID, !tvgID.isEmpty {
                    match = byTvgID[tvgID]
                }
                if match == nil {
                    let key = "\(incoming.name)|\(incoming.groupName ?? "")"
                    match = byNameGroup[key]
                }

                if var matched = match {
                    seenIDs.insert(matched.id)

                    let changed = matched.streamURL != incoming.streamURL
                        || matched.logoURL != incoming.logoURL
                        || matched.name != incoming.name
                        || matched.groupName != incoming.groupName
                        || matched.epgID != incoming.epgID
                        || matched.tvgID != incoming.tvgID
                        || matched.channelNum != incoming.channelNum
                        || matched.sourceChannelID != incoming.sourceChannelID
                        || matched.isDeleted

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
                        let updateParams = RecordMappers.channelParams(matched)
                        try tx.execute(
                            sql: """
                                UPDATE channels SET playlist_id = ?, source_channel_id = ?, tvg_id = ?,
                                    name = ?, group_name = ?, epg_id = ?, logo_url = ?, stream_url = ?,
                                    channel_number = ?, is_favorite = ?, is_deleted = ?, deleted_at = ?
                                WHERE id = ?
                                """,
                            parameters: updateParams + [matched.id]
                        )
                        updated += 1
                    } else {
                        unchanged += 1
                    }
                } else {
                    let insertParams = RecordMappers.channelParams(incoming)
                    try tx.execute(
                        sql: """
                            INSERT INTO channels (id, playlist_id, source_channel_id, tvg_id, name,
                                group_name, epg_id, logo_url, stream_url, channel_number,
                                is_favorite, is_deleted, deleted_at)
                            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                            """,
                        parameters: [incoming.id] + insertParams
                    )
                    seenIDs.insert(incoming.id)
                    added += 1
                }
            }

            // Soft-delete channels not in incoming batch
            let activeNotSeen = existing.filter { !$0.isDeleted && !seenIDs.contains($0.id) }
            for channel in activeNotSeen {
                try tx.execute(
                    sql: "UPDATE channels SET is_deleted = 1, deleted_at = ? WHERE id = ?",
                    parameters: [RecordMappers.epochToISO(currentTime), channel.id]
                )
            }

            return SyncImportResult(
                added: added,
                updated: updated,
                softDeleted: activeNotSeen.count,
                unchanged: unchanged
            )
        }
    }

    // MARK: - UI Queries

    public func getActive(playlistID: String) async throws -> [ChannelRecord] {
        try await db.getAll(
            sql: "SELECT * FROM channels WHERE playlist_id = ? AND is_deleted = 0 ORDER BY name ASC",
            parameters: [playlistID],
            mapper: RecordMappers.channelMapper
        )
    }

    public func getFavorites() async throws -> [ChannelRecord] {
        try await db.getAll(
            sql: "SELECT * FROM channels WHERE is_favorite = 1 AND is_deleted = 0 ORDER BY name ASC",
            parameters: [],
            mapper: RecordMappers.channelMapper
        )
    }

    public func search(query: String, playlistID: String? = nil, limit: Int = 20) async throws -> [ChannelRecord] {
        let escapedQuery = query.replacingOccurrences(of: "%", with: "\\%")
            .replacingOccurrences(of: "_", with: "\\_")
        if let playlistID {
            return try await db.getAll(
                sql: "SELECT * FROM channels WHERE is_deleted = 0 AND playlist_id = ? AND name LIKE ? ESCAPE '\\' ORDER BY name ASC LIMIT ?",
                parameters: [playlistID, "%\(escapedQuery)%", limit],
                mapper: RecordMappers.channelMapper
            )
        } else {
            return try await db.getAll(
                sql: "SELECT * FROM channels WHERE is_deleted = 0 AND name LIKE ? ESCAPE '\\' ORDER BY name ASC LIMIT ?",
                parameters: ["%\(escapedQuery)%", limit],
                mapper: RecordMappers.channelMapper
            )
        }
    }

    public func getByEpgID(_ epgID: String) async throws -> ChannelRecord? {
        try await db.getOptional(
            sql: "SELECT * FROM channels WHERE epg_id = ? AND is_deleted = 0 LIMIT 1",
            parameters: [epgID],
            mapper: RecordMappers.channelMapper
        )
    }

    public func getByNumber(playlistID: String, number: Int) async throws -> ChannelRecord? {
        try await db.getOptional(
            sql: "SELECT * FROM channels WHERE playlist_id = ? AND channel_number = ? AND is_deleted = 0 LIMIT 1",
            parameters: [playlistID, number],
            mapper: RecordMappers.channelMapper
        )
    }

    public func getBatch(ids: [String]) async throws -> [ChannelRecord] {
        guard !ids.isEmpty else { return [] }
        let placeholders = ids.map { _ in "?" }.joined(separator: ", ")
        return try await db.getAll(
            sql: "SELECT * FROM channels WHERE id IN (\(placeholders))",
            parameters: ids,
            mapper: RecordMappers.channelMapper
        )
    }

    // MARK: - Favorites

    public func toggleFavorite(id: String) async throws {
        guard let record = try await get(id: id) else { return }
        let newValue = record.isFavorite ? 0 : 1
        try await db.execute(
            sql: "UPDATE channels SET is_favorite = ? WHERE id = ?",
            parameters: [newValue, id]
        )
    }

    public func setFavorite(id: String, isFavorite: Bool) async throws {
        try await db.execute(
            sql: "UPDATE channels SET is_favorite = ? WHERE id = ?",
            parameters: [isFavorite ? 1 : 0, id]
        )
    }

    // MARK: - Soft Delete / Purge

    public func purgeDeleted(olderThan: Int) async throws -> Int {
        let iso = RecordMappers.epochToISO(olderThan) ?? ""
        let result = try await db.execute(
            sql: "DELETE FROM channels WHERE is_deleted = 1 AND deleted_at < ?",
            parameters: [iso]
        )
        return Int(result)
    }
}
