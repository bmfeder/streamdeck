-- ============================================================
-- StreamDeck Supabase Schema
-- Run this in the Supabase SQL Editor (Dashboard > SQL Editor)
-- ============================================================

-- Enable required extensions
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- ============================================================
-- playlists: Core playlist metadata
-- ============================================================
CREATE TABLE playlists (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id             UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    name                TEXT NOT NULL,
    type                TEXT NOT NULL CHECK (type IN ('m3u', 'xtream', 'emby')),
    url                 TEXT NOT NULL,
    username            TEXT,
    encrypted_password  TEXT,
    epg_url             TEXT,
    refresh_hrs         INTEGER NOT NULL DEFAULT 24,
    is_active           BOOLEAN NOT NULL DEFAULT true,
    sort_order          INTEGER NOT NULL DEFAULT 0,
    last_sync           TIMESTAMPTZ,
    last_epg_sync       TIMESTAMPTZ,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT now()
);

COMMENT ON COLUMN playlists.encrypted_password IS
    'Encrypted via pgp_sym_encrypt(password, user_id::text). Decrypt with pgp_sym_decrypt(encrypted_password::bytea, user_id::text).';
COMMENT ON COLUMN playlists.type IS 'Playlist source type: m3u, xtream, or emby';
COMMENT ON COLUMN playlists.refresh_hrs IS 'Auto-refresh interval in hours. 0 = manual only.';

-- ============================================================
-- channels: Imported channel records
-- ============================================================
CREATE TABLE channels (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id             UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    playlist_id         UUID NOT NULL REFERENCES playlists(id) ON DELETE CASCADE,
    source_channel_id   TEXT,
    tvg_id              TEXT,
    name                TEXT NOT NULL,
    group_name          TEXT,
    epg_id              TEXT,
    logo_url            TEXT,
    stream_url          TEXT NOT NULL,
    channel_number      INTEGER,
    is_favorite         BOOLEAN NOT NULL DEFAULT false,
    is_deleted          BOOLEAN NOT NULL DEFAULT false,
    deleted_at          TIMESTAMPTZ,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT now()
);

COMMENT ON COLUMN channels.source_channel_id IS 'Provider-native channel ID for identity matching on re-import';
COMMENT ON COLUMN channels.is_deleted IS 'Soft-delete flag. Channels purged after 30 days.';

-- ============================================================
-- vod_items: Movies, series, episodes
-- ============================================================
CREATE TABLE vod_items (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id             UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    playlist_id         UUID NOT NULL REFERENCES playlists(id) ON DELETE CASCADE,
    title               TEXT NOT NULL,
    type                TEXT NOT NULL CHECK (type IN ('movie', 'series', 'episode')),
    stream_url          TEXT,
    logo_url            TEXT,
    genre               TEXT,
    year                INTEGER,
    rating              TEXT,
    duration            INTEGER,
    season_num          INTEGER,
    episode_num         INTEGER,
    series_id           TEXT,
    container_extension TEXT,
    plot                TEXT,
    cast_list           TEXT,
    director            TEXT,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT now()
);

COMMENT ON COLUMN vod_items.duration IS 'Duration in seconds';
COMMENT ON COLUMN vod_items.series_id IS 'Parent series UUID for episode records';

-- ============================================================
-- watch_progress: Resume positions
-- ============================================================
CREATE TABLE watch_progress (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id         UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    content_id      TEXT NOT NULL,
    playlist_id     TEXT,
    position_ms     INTEGER NOT NULL DEFAULT 0,
    duration_ms     INTEGER,
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (user_id, content_id)
);

COMMENT ON COLUMN watch_progress.content_id IS 'Matches PlayableItem.contentID (channel ID or VOD item ID)';

-- ============================================================
-- user_preferences: App settings (one row per user)
-- ============================================================
CREATE TABLE user_preferences (
    user_id                 UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    preferred_engine        TEXT NOT NULL DEFAULT 'auto',
    resume_playback_enabled BOOLEAN NOT NULL DEFAULT true,
    buffer_timeout_seconds  INTEGER NOT NULL DEFAULT 10,
    updated_at              TIMESTAMPTZ NOT NULL DEFAULT now()
);

COMMENT ON COLUMN user_preferences.preferred_engine IS 'auto, avPlayer, or vlcKit';
