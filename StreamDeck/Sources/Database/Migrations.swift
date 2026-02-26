import GRDB

/// Database migrations for the StreamDeck schema.
public enum DatabaseMigrations {

    /// Registers all migrations with the given migrator.
    public static func registerAll(in migrator: inout DatabaseMigrator) {
        registerV1(in: &migrator)
        registerV2(in: &migrator)
    }

    // MARK: - v1: Initial Schema

    private static func registerV1(in migrator: inout DatabaseMigrator) {
        migrator.registerMigration("v1") { db in
            // -- Playlist --
            try db.create(table: "playlist") { t in
                t.primaryKey("id", .text)
                t.column("name", .text).notNull()
                t.column("type", .text).notNull()
                t.column("url", .text).notNull()
                t.column("username", .text)
                t.column("password_ref", .text)
                t.column("epg_url", .text)
                t.column("refresh_hrs", .integer).notNull().defaults(to: 24)
                t.column("last_sync", .integer)
                t.column("last_epg_sync", .integer)
                t.column("last_sync_etag", .text)
                t.column("last_sync_hash", .text)
                t.column("is_active", .integer).notNull().defaults(to: 1)
                t.column("sort_order", .integer).notNull().defaults(to: 0)
            }

            // -- Channel --
            try db.create(table: "channel") { t in
                t.primaryKey("id", .text)
                t.column("playlist_id", .text).notNull()
                    .references("playlist", onDelete: .cascade)
                t.column("source_channel_id", .text)
                t.column("name", .text).notNull()
                t.column("group_name", .text)
                t.column("stream_url", .text).notNull()
                t.column("logo_url", .text)
                t.column("epg_id", .text)
                t.column("tvg_id", .text)
                t.column("channel_num", .integer)
                t.column("is_favorite", .integer).notNull().defaults(to: 0)
                t.column("is_deleted", .integer).notNull().defaults(to: 0)
                t.column("deleted_at", .integer)
            }

            // -- VodItem --
            try db.create(table: "vod_item") { t in
                t.primaryKey("id", .text)
                t.column("playlist_id", .text).notNull()
                    .references("playlist", onDelete: .cascade)
                t.column("title", .text).notNull()
                t.column("type", .text).notNull()
                t.column("stream_url", .text)
                t.column("poster_url", .text)
                t.column("backdrop_url", .text)
                t.column("description", .text)
                t.column("year", .integer)
                t.column("rating", .double)
                t.column("genre", .text)
                t.column("series_id", .text)
                t.column("season_num", .integer)
                t.column("episode_num", .integer)
                t.column("duration_s", .integer)
            }

            // -- WatchProgress --
            try db.create(table: "watch_progress") { t in
                t.primaryKey("content_id", .text)
                t.column("playlist_id", .text)
                    .references("playlist", onDelete: .cascade)
                t.column("position_ms", .integer).notNull().defaults(to: 0)
                t.column("duration_ms", .integer)
                t.column("updated_at", .integer).notNull()
            }

            // -- EpgProgram --
            try db.create(table: "epg_program") { t in
                t.primaryKey("id", .text)
                t.column("channel_epg_id", .text).notNull()
                t.column("title", .text).notNull()
                t.column("description", .text)
                t.column("start_time", .integer).notNull()
                t.column("end_time", .integer).notNull()
                t.column("category", .text)
                t.column("icon_url", .text)
                t.uniqueKey(["channel_epg_id", "start_time"])
            }

            // -- Indexes --

            // Channel indexes
            try db.create(index: "idx_channel_playlist", on: "channel", columns: ["playlist_id"])
            try db.create(index: "idx_channel_source", on: "channel", columns: ["playlist_id", "source_channel_id"])
            try db.create(index: "idx_channel_number", on: "channel", columns: ["playlist_id", "channel_num"])
            try db.create(index: "idx_channel_tvg", on: "channel", columns: ["tvg_id"])

            // Filtered indexes for active/favorite channels
            try db.execute(sql: """
                CREATE INDEX idx_channel_favorite ON channel(is_favorite) WHERE is_deleted = 0
                """)
            try db.execute(sql: """
                CREATE INDEX idx_channel_active ON channel(playlist_id) WHERE is_deleted = 0
                """)

            // EPG index
            try db.create(index: "idx_epg_channel_time", on: "epg_program", columns: ["channel_epg_id", "start_time"])

            // VOD index
            try db.create(index: "idx_vod_type", on: "vod_item", columns: ["type", "playlist_id"])

            // WatchProgress index
            try db.execute(sql: """
                CREATE INDEX idx_progress_updated ON watch_progress(updated_at DESC)
                """)
        }
    }

    // MARK: - v2: Search Indexes

    private static func registerV2(in migrator: inout DatabaseMigrator) {
        migrator.registerMigration("v2") { db in
            try db.create(index: "idx_channel_name", on: "channel", columns: ["name"])
            try db.create(index: "idx_vod_title", on: "vod_item", columns: ["title"])
            try db.create(index: "idx_epg_title", on: "epg_program", columns: ["title"])
        }
    }
}
