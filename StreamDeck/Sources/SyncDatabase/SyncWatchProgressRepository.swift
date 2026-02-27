import Database
import Foundation
import PowerSync

/// PowerSync-backed watch progress repository. Same public API as WatchProgressRepository.
public struct SyncWatchProgressRepository: Sendable {
    private let db: any PowerSyncDatabaseProtocol

    public init(db: any PowerSyncDatabaseProtocol) {
        self.db = db
    }

    // MARK: - CRUD

    /// Upsert by content_id. Since PowerSync uses UUID `id` as PK,
    /// we first check if a row with this content_id exists.
    public func upsert(_ record: WatchProgressRecord) async throws {
        let existing = try await db.getOptional(
            sql: "SELECT id FROM watch_progress WHERE content_id = ? LIMIT 1",
            parameters: [record.contentID]
        ) { cursor in
            try cursor.getString(name: "id")
        }

        let params = RecordMappers.watchProgressParams(record)

        if let existingID = existing {
            try await db.execute(
                sql: """
                    UPDATE watch_progress SET content_id = ?, playlist_id = ?,
                        position_ms = ?, duration_ms = ?, updated_at = ?
                    WHERE id = ?
                    """,
                parameters: params + [existingID]
            )
        } else {
            let newID = UUID().uuidString
            try await db.execute(
                sql: """
                    INSERT INTO watch_progress (id, content_id, playlist_id,
                        position_ms, duration_ms, updated_at)
                    VALUES (?, ?, ?, ?, ?, ?)
                    """,
                parameters: [newID] + params
            )
        }
    }

    public func get(contentID: String) async throws -> WatchProgressRecord? {
        try await db.getOptional(
            sql: "SELECT * FROM watch_progress WHERE content_id = ? LIMIT 1",
            parameters: [contentID],
            mapper: RecordMappers.watchProgressMapper
        )
    }

    public func delete(contentID: String) async throws {
        try await db.execute(
            sql: "DELETE FROM watch_progress WHERE content_id = ?",
            parameters: [contentID]
        )
    }

    public func deleteAll() async throws {
        try await db.execute(sql: "DELETE FROM watch_progress", parameters: [])
    }

    // MARK: - Queries

    public func getRecentlyWatched(limit: Int = 20) async throws -> [WatchProgressRecord] {
        try await db.getAll(
            sql: "SELECT * FROM watch_progress ORDER BY updated_at DESC LIMIT ?",
            parameters: [limit],
            mapper: RecordMappers.watchProgressMapper
        )
    }

    public func getUnfinished(limit: Int = 20) async throws -> [WatchProgressRecord] {
        try await db.getAll(
            sql: """
                SELECT * FROM watch_progress
                WHERE position_ms > 0 AND duration_ms IS NOT NULL
                    AND position_ms < duration_ms - 30000
                ORDER BY updated_at DESC LIMIT ?
                """,
            parameters: [limit],
            mapper: RecordMappers.watchProgressMapper
        )
    }

    public func getBatch(contentIDs: [String]) async throws -> [String: WatchProgressRecord] {
        guard !contentIDs.isEmpty else { return [:] }
        let placeholders = contentIDs.map { _ in "?" }.joined(separator: ", ")
        let records = try await db.getAll(
            sql: "SELECT * FROM watch_progress WHERE content_id IN (\(placeholders))",
            parameters: contentIDs,
            mapper: RecordMappers.watchProgressMapper
        )
        return Dictionary(uniqueKeysWithValues: records.map { ($0.contentID, $0) })
    }

    @discardableResult
    public func purgeOlderThan(_ timestamp: Int) async throws -> Int {
        let iso = RecordMappers.epochToISO(timestamp) ?? ""
        let result = try await db.execute(
            sql: "DELETE FROM watch_progress WHERE updated_at < ?",
            parameters: [iso]
        )
        return Int(result)
    }
}
