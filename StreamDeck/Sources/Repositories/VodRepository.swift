import Foundation
import GRDB
import Database

/// Result of a VOD batch import operation.
public struct VodImportResult: Equatable, Sendable {
    public let added: Int
    public let removed: Int

    public init(added: Int, removed: Int) {
        self.added = added
        self.removed = removed
    }
}

/// Repository for VOD item CRUD, batch import, and UI queries.
/// Wraps DatabaseManager for typed access to VodItemRecord.
public struct VodRepository: Sendable {
    private let dbManager: DatabaseManager

    public init(dbManager: DatabaseManager) {
        self.dbManager = dbManager
    }

    // MARK: - CRUD

    /// Inserts a new VOD item record.
    public func create(_ record: VodItemRecord) throws {
        try dbManager.dbQueue.write { db in
            try record.insert(db)
        }
    }

    /// Fetches a single VOD item by ID, or nil if not found.
    public func get(id: String) throws -> VodItemRecord? {
        try dbManager.dbQueue.read { db in
            try VodItemRecord.fetchOne(db, key: id)
        }
    }

    /// Fetches multiple VOD items by their IDs.
    public func getByIDs(ids: [String]) throws -> [VodItemRecord] {
        guard !ids.isEmpty else { return [] }
        return try dbManager.dbQueue.read { db in
            try VodItemRecord
                .filter(ids.contains(Column("id")))
                .fetchAll(db)
        }
    }

    /// Updates an existing VOD item record.
    public func update(_ record: VodItemRecord) throws {
        try dbManager.dbQueue.write { db in
            try record.update(db)
        }
    }

    /// Hard-deletes a VOD item by ID.
    public func delete(id: String) throws {
        try dbManager.dbQueue.write { db in
            _ = try VodItemRecord.deleteOne(db, key: id)
        }
    }

    // MARK: - Batch Import

    /// Imports VOD items for a playlist. Deletes existing items for the playlist, then inserts new ones.
    /// Runs in a single transaction for atomicity.
    public func importVodItems(playlistID: String, items: [VodItemRecord]) throws -> VodImportResult {
        try dbManager.dbQueue.write { db in
            let removed = try VodItemRecord
                .filter(Column("playlist_id") == playlistID)
                .deleteAll(db)

            for item in items {
                try item.insert(db)
            }

            return VodImportResult(added: items.count, removed: removed)
        }
    }

    // MARK: - UI Queries

    /// Fetches all movies for a playlist, ordered by title.
    public func getMovies(playlistID: String) throws -> [VodItemRecord] {
        try dbManager.dbQueue.read { db in
            try VodItemRecord
                .filter(Column("playlist_id") == playlistID && Column("type") == "movie")
                .order(Column("title").asc)
                .fetchAll(db)
        }
    }

    /// Fetches all series for a playlist, ordered by title.
    public func getSeries(playlistID: String) throws -> [VodItemRecord] {
        try dbManager.dbQueue.read { db in
            try VodItemRecord
                .filter(Column("playlist_id") == playlistID && Column("type") == "series")
                .order(Column("title").asc)
                .fetchAll(db)
        }
    }

    /// Fetches all episodes for a series, ordered by season and episode number.
    public func getEpisodes(seriesID: String) throws -> [VodItemRecord] {
        try dbManager.dbQueue.read { db in
            try VodItemRecord
                .filter(Column("type") == "episode" && Column("series_id") == seriesID)
                .order(Column("season_num").asc, Column("episode_num").asc)
                .fetchAll(db)
        }
    }

    /// Searches VOD items by title (case-insensitive LIKE).
    /// Optionally scoped to a playlist and/or type. Limited to `limit` results for performance.
    public func searchVod(query: String, playlistID: String? = nil, type: String? = nil, limit: Int = 20) throws -> [VodItemRecord] {
        try dbManager.dbQueue.read { db in
            var request = VodItemRecord
                .filter(Column("title").like("%\(query)%"))

            if let playlistID {
                request = request.filter(Column("playlist_id") == playlistID)
            }
            if let type {
                request = request.filter(Column("type") == type)
            }

            return try request.order(Column("title").asc).limit(limit).fetchAll(db)
        }
    }

    /// Returns distinct genre values for a playlist and type.
    /// Splits comma-separated genre strings and deduplicates.
    public func getGenres(playlistID: String, type: String) throws -> [String] {
        try dbManager.dbQueue.read { db in
            let rows = try String.fetchAll(
                db,
                sql: "SELECT DISTINCT genre FROM vod_item WHERE playlist_id = ? AND type = ? AND genre IS NOT NULL",
                arguments: [playlistID, type]
            )
            // Split comma-separated genres and deduplicate
            var seen = Set<String>()
            var result: [String] = []
            for row in rows {
                let parts = row.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
                for part in parts where !part.isEmpty && seen.insert(part).inserted {
                    result.append(part)
                }
            }
            return result.sorted()
        }
    }
}
