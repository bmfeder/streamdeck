-- ============================================================
-- StreamDeck Indexes
-- Run after schema.sql in Supabase SQL Editor
-- ============================================================

-- Playlists
CREATE INDEX idx_playlists_user_id ON playlists (user_id);

-- Channels
CREATE INDEX idx_channels_user_id ON channels (user_id);
CREATE INDEX idx_channels_playlist_id ON channels (playlist_id);
CREATE INDEX idx_channels_group ON channels (playlist_id, group_name) WHERE NOT is_deleted;
CREATE INDEX idx_channels_favorite ON channels (user_id) WHERE is_favorite AND NOT is_deleted;
CREATE INDEX idx_channels_name ON channels (name) WHERE NOT is_deleted;
CREATE INDEX idx_channels_source ON channels (playlist_id, source_channel_id);
CREATE INDEX idx_channels_epg ON channels (epg_id) WHERE epg_id IS NOT NULL AND NOT is_deleted;

-- VOD Items
CREATE INDEX idx_vod_items_user_id ON vod_items (user_id);
CREATE INDEX idx_vod_items_playlist ON vod_items (playlist_id, type);
CREATE INDEX idx_vod_items_series ON vod_items (series_id) WHERE series_id IS NOT NULL;
CREATE INDEX idx_vod_items_title ON vod_items (title);
CREATE INDEX idx_vod_items_genre ON vod_items (playlist_id, genre) WHERE genre IS NOT NULL;

-- Watch Progress
CREATE INDEX idx_watch_progress_user_id ON watch_progress (user_id);
CREATE INDEX idx_watch_progress_updated ON watch_progress (user_id, updated_at DESC);
