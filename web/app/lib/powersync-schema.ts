import { column, Schema, Table } from "@powersync/web";

const playlists = new Table(
  {
    name: column.text,
    type: column.text,
    url: column.text,
    username: column.text,
    encrypted_password: column.text,
    epg_url: column.text,
    refresh_hrs: column.integer,
    is_active: column.integer,
    sort_order: column.integer,
    last_sync: column.text,
    last_epg_sync: column.text,
    created_at: column.text,
    updated_at: column.text,
  },
  { indexes: { sort: ["sort_order"] } }
);

const channels = new Table(
  {
    playlist_id: column.text,
    source_channel_id: column.text,
    tvg_id: column.text,
    name: column.text,
    group_name: column.text,
    epg_id: column.text,
    logo_url: column.text,
    stream_url: column.text,
    channel_number: column.integer,
    is_favorite: column.integer,
    is_deleted: column.integer,
    deleted_at: column.text,
    created_at: column.text,
    updated_at: column.text,
  },
  {
    indexes: {
      playlist: ["playlist_id"],
      group: ["playlist_id", "group_name"],
      favorite: ["is_favorite"],
      name: ["name"],
    },
  }
);

const vod_items = new Table(
  {
    playlist_id: column.text,
    title: column.text,
    type: column.text,
    stream_url: column.text,
    logo_url: column.text,
    genre: column.text,
    year: column.integer,
    rating: column.text,
    duration: column.integer,
    season_num: column.integer,
    episode_num: column.integer,
    series_id: column.text,
    container_extension: column.text,
    plot: column.text,
    cast_list: column.text,
    director: column.text,
    created_at: column.text,
    updated_at: column.text,
  },
  {
    indexes: {
      playlist_type: ["playlist_id", "type"],
      title: ["title"],
      series: ["series_id"],
    },
  }
);

const watch_progress = new Table(
  {
    content_id: column.text,
    playlist_id: column.text,
    position_ms: column.integer,
    duration_ms: column.integer,
    updated_at: column.text,
  },
  { indexes: { content: ["content_id"] } }
);

const user_preferences = new Table({
  preferred_engine: column.text,
  resume_playback_enabled: column.integer,
  buffer_timeout_seconds: column.integer,
  updated_at: column.text,
});

export const AppSchema = new Schema({
  playlists,
  channels,
  vod_items,
  watch_progress,
  user_preferences,
});

export type Database = (typeof AppSchema)["types"];
