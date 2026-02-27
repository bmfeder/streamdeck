import Database
import Foundation
import PowerSync

/// PowerSync-backed VOD repository. Same public API as VodRepository.
public struct SyncVodRepository: Sendable {
    private let db: any PowerSyncDatabaseProtocol

    public init(db: any PowerSyncDatabaseProtocol) {
        self.db = db
    }

    // MARK: - CRUD

    public func create(_ record: VodItemRecord) async throws {
        let params = RecordMappers.vodItemParams(record)
        try await db.execute(
            sql: """
                INSERT INTO vod_items (id, playlist_id, title, type, stream_url, logo_url,
                    genre, year, rating, duration, season_num, episode_num, series_id,
                    container_extension, plot, cast_list, director)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
            parameters: [record.id] + params
        )
    }

    public func get(id: String) async throws -> VodItemRecord? {
        try await db.getOptional(
            sql: "SELECT * FROM vod_items WHERE id = ?",
            parameters: [id],
            mapper: RecordMappers.vodItemMapper
        )
    }

    public func delete(id: String) async throws {
        try await db.execute(sql: "DELETE FROM vod_items WHERE id = ?", parameters: [id])
    }

    // MARK: - Batch Import

    public func importVodItems(playlistID: String, items: [VodItemRecord]) async throws -> SyncVodImportResult {
        try await db.writeTransaction { tx in
            // Delete existing VOD items for this playlist
            try tx.execute(
                sql: "DELETE FROM vod_items WHERE playlist_id = ?",
                parameters: [playlistID]
            )

            // Insert new items
            for item in items {
                let params = RecordMappers.vodItemParams(item)
                try tx.execute(
                    sql: """
                        INSERT INTO vod_items (id, playlist_id, title, type, stream_url, logo_url,
                            genre, year, rating, duration, season_num, episode_num, series_id,
                            container_extension, plot, cast_list, director)
                        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                        """,
                    parameters: [item.id] + params
                )
            }

            return SyncVodImportResult(imported: items.count)
        }
    }

    // MARK: - Queries

    public func getMovies(playlistID: String) async throws -> [VodItemRecord] {
        try await db.getAll(
            sql: "SELECT * FROM vod_items WHERE playlist_id = ? AND type = 'movie' ORDER BY title ASC",
            parameters: [playlistID],
            mapper: RecordMappers.vodItemMapper
        )
    }

    public func getSeries(playlistID: String) async throws -> [VodItemRecord] {
        try await db.getAll(
            sql: "SELECT * FROM vod_items WHERE playlist_id = ? AND type = 'series' ORDER BY title ASC",
            parameters: [playlistID],
            mapper: RecordMappers.vodItemMapper
        )
    }

    public func getEpisodes(seriesID: String) async throws -> [VodItemRecord] {
        try await db.getAll(
            sql: "SELECT * FROM vod_items WHERE series_id = ? AND type = 'episode' ORDER BY season_num ASC, episode_num ASC",
            parameters: [seriesID],
            mapper: RecordMappers.vodItemMapper
        )
    }

    public func searchVod(query: String, playlistID: String? = nil, type: String? = nil, limit: Int = 20) async throws -> [VodItemRecord] {
        let escapedQuery = query.replacingOccurrences(of: "%", with: "\\%")
            .replacingOccurrences(of: "_", with: "\\_")
        var sql = "SELECT * FROM vod_items WHERE title LIKE ? ESCAPE '\\'"
        var params: [Sendable?] = ["%\(escapedQuery)%"]

        if let playlistID {
            sql += " AND playlist_id = ?"
            params.append(playlistID)
        }
        if let type {
            sql += " AND type = ?"
            params.append(type)
        }
        sql += " ORDER BY title ASC LIMIT ?"
        params.append(limit)

        return try await db.getAll(sql: sql, parameters: params, mapper: RecordMappers.vodItemMapper)
    }

    public func getGenres(playlistID: String, type: String) async throws -> [String] {
        try await db.getAll(
            sql: "SELECT DISTINCT genre FROM vod_items WHERE playlist_id = ? AND type = ? AND genre IS NOT NULL ORDER BY genre ASC",
            parameters: [playlistID, type]
        ) { cursor in
            try cursor.getString(name: "genre")
        }
    }

    public func getByIDs(ids: [String]) async throws -> [VodItemRecord] {
        guard !ids.isEmpty else { return [] }
        let placeholders = ids.map { _ in "?" }.joined(separator: ", ")
        return try await db.getAll(
            sql: "SELECT * FROM vod_items WHERE id IN (\(placeholders))",
            parameters: ids,
            mapper: RecordMappers.vodItemMapper
        )
    }
}
