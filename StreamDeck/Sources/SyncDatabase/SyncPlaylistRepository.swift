import Database
import Foundation
import PowerSync

/// PowerSync-backed playlist repository. Same public API as PlaylistRepository
/// but uses PowerSync SQL instead of GRDB. All writes auto-sync to Supabase.
public struct SyncPlaylistRepository: Sendable {
    private let db: any PowerSyncDatabaseProtocol

    public init(db: any PowerSyncDatabaseProtocol) {
        self.db = db
    }

    // MARK: - CRUD

    public func create(_ record: PlaylistRecord) async throws {
        let params = RecordMappers.playlistParams(record)
        try await db.execute(
            sql: """
                INSERT INTO playlists (id, name, type, url, username, encrypted_password,
                    epg_url, refresh_hrs, is_active, sort_order, last_sync, last_epg_sync)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
            parameters: [record.id] + params
        )
    }

    public func get(id: String) async throws -> PlaylistRecord? {
        try await db.getOptional(
            sql: "SELECT * FROM playlists WHERE id = ?",
            parameters: [id],
            mapper: RecordMappers.playlistMapper
        )
    }

    public func getAll() async throws -> [PlaylistRecord] {
        try await db.getAll(
            sql: "SELECT * FROM playlists ORDER BY sort_order ASC",
            parameters: [],
            mapper: RecordMappers.playlistMapper
        )
    }

    public func update(_ record: PlaylistRecord) async throws {
        let params = RecordMappers.playlistParams(record)
        try await db.execute(
            sql: """
                UPDATE playlists SET name = ?, type = ?, url = ?, username = ?,
                    encrypted_password = ?, epg_url = ?, refresh_hrs = ?, is_active = ?,
                    sort_order = ?, last_sync = ?, last_epg_sync = ?
                WHERE id = ?
                """,
            parameters: params + [record.id]
        )
    }

    public func delete(id: String) async throws {
        // Delete channels and vod_items first (no foreign key cascade in PowerSync)
        try await db.execute(sql: "DELETE FROM channels WHERE playlist_id = ?", parameters: [id])
        try await db.execute(sql: "DELETE FROM vod_items WHERE playlist_id = ?", parameters: [id])
        try await db.execute(sql: "DELETE FROM playlists WHERE id = ?", parameters: [id])
    }

    // MARK: - Sync Tracking

    public func updateSyncTimestamp(
        _ playlistID: String,
        timestamp: Int
    ) async throws {
        try await db.execute(
            sql: "UPDATE playlists SET last_sync = ? WHERE id = ?",
            parameters: [RecordMappers.epochToISO(timestamp), playlistID]
        )
    }

    public func updateEpgSyncTimestamp(_ playlistID: String, timestamp: Int) async throws {
        try await db.execute(
            sql: "UPDATE playlists SET last_epg_sync = ? WHERE id = ?",
            parameters: [RecordMappers.epochToISO(timestamp), playlistID]
        )
    }

    public func needsRefresh(_ playlistID: String, now: Int? = nil) async throws -> Bool {
        guard let record = try await get(id: playlistID) else { return false }
        guard let lastSync = record.lastSync else { return true }
        let currentTime = now ?? Int(Date().timeIntervalSince1970)
        return lastSync + (record.refreshHrs * 3600) < currentTime
    }
}
