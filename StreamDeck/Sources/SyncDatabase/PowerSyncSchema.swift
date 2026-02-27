import PowerSync

/// PowerSync schema definition matching the Supabase tables and web dashboard schema.
/// Must stay in sync with `web/app/lib/powersync-schema.ts`.
public let syncSchema = Schema(
    tables: [
        Table(
            name: "playlists",
            columns: [
                .text("name"),
                .text("type"),
                .text("url"),
                .text("username"),
                .text("encrypted_password"),
                .text("epg_url"),
                .integer("refresh_hrs"),
                .integer("is_active"),
                .integer("sort_order"),
                .text("last_sync"),
                .text("last_epg_sync"),
                .text("created_at"),
                .text("updated_at"),
            ],
            indexes: [
                Index.ascending(name: "playlists_sort", columns: ["sort_order"])
            ]
        ),
        Table(
            name: "channels",
            columns: [
                .text("playlist_id"),
                .text("source_channel_id"),
                .text("tvg_id"),
                .text("name"),
                .text("group_name"),
                .text("epg_id"),
                .text("logo_url"),
                .text("stream_url"),
                .integer("channel_number"),
                .integer("is_favorite"),
                .integer("is_deleted"),
                .text("deleted_at"),
                .text("created_at"),
                .text("updated_at"),
            ],
            indexes: [
                Index.ascending(name: "channels_playlist", columns: ["playlist_id"]),
                Index(name: "channels_group", columns: [
                    IndexedColumn.ascending("playlist_id"),
                    IndexedColumn.ascending("group_name"),
                ]),
                Index.ascending(name: "channels_favorite", column: "is_favorite"),
                Index.ascending(name: "channels_name", column: "name"),
            ]
        ),
        Table(
            name: "vod_items",
            columns: [
                .text("playlist_id"),
                .text("title"),
                .text("type"),
                .text("stream_url"),
                .text("logo_url"),
                .text("genre"),
                .integer("year"),
                .text("rating"),
                .integer("duration"),
                .integer("season_num"),
                .integer("episode_num"),
                .text("series_id"),
                .text("container_extension"),
                .text("plot"),
                .text("cast_list"),
                .text("director"),
                .text("created_at"),
                .text("updated_at"),
            ],
            indexes: [
                Index(name: "vod_playlist_type", columns: [
                    IndexedColumn.ascending("playlist_id"),
                    IndexedColumn.ascending("type"),
                ]),
                Index.ascending(name: "vod_title", column: "title"),
                Index.ascending(name: "vod_series", column: "series_id"),
            ]
        ),
        Table(
            name: "watch_progress",
            columns: [
                .text("content_id"),
                .text("playlist_id"),
                .integer("position_ms"),
                .integer("duration_ms"),
                .text("updated_at"),
            ],
            indexes: [
                Index.ascending(name: "progress_content", column: "content_id")
            ]
        ),
        Table(
            name: "user_preferences",
            columns: [
                .text("preferred_engine"),
                .integer("resume_playback_enabled"),
                .integer("buffer_timeout_seconds"),
                .text("updated_at"),
            ]
        ),
    ]
)
