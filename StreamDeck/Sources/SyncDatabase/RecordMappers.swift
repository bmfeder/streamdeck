import Database
import Foundation
import PowerSync

/// Maps between PowerSync SqlCursor rows and existing GRDB record types.
/// Handles column name differences between the local GRDB schema and the Supabase/PowerSync schema.
///
/// Key differences:
/// - GRDB `channel_num` ↔ PowerSync `channel_number`
/// - GRDB `password_ref` ↔ PowerSync `encrypted_password` (handled separately via Keychain)
/// - GRDB `poster_url` ↔ PowerSync `logo_url` (vod_items)
/// - GRDB `description` ↔ PowerSync `plot` (vod_items)
/// - GRDB `duration_s` ↔ PowerSync `duration` (vod_items)
/// - GRDB `rating` (Double) ↔ PowerSync `rating` (text)
/// - GRDB timestamps (Int epoch) ↔ PowerSync timestamps (ISO 8601 text)
public enum RecordMappers {

    // MARK: - Timestamp Conversion

    /// Convert epoch seconds to ISO 8601 string for PowerSync.
    public static func epochToISO(_ epoch: Int?) -> String? {
        guard let epoch else { return nil }
        let date = Date(timeIntervalSince1970: TimeInterval(epoch))
        return iso8601Formatter.string(from: date)
    }

    /// Convert ISO 8601 string from PowerSync to epoch seconds.
    public static func isoToEpoch(_ iso: String?) -> Int? {
        guard let iso, !iso.isEmpty else { return nil }
        guard let date = iso8601Formatter.date(from: iso)
                ?? iso8601FractionalFormatter.date(from: iso) else { return nil }
        return Int(date.timeIntervalSince1970)
    }

    nonisolated(unsafe) private static let iso8601Formatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    nonisolated(unsafe) private static let iso8601FractionalFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    // MARK: - Playlist Mapping

    /// SqlCursor mapper for use with `db.getAll(sql:mapper:)`.
    public static func playlistMapper(_ cursor: any SqlCursor) throws -> PlaylistRecord {
        PlaylistRecord(
            id: try cursor.getString(name: "id"),
            name: try cursor.getString(name: "name"),
            type: try cursor.getString(name: "type"),
            url: try cursor.getString(name: "url"),
            username: try cursor.getStringOptional(name: "username"),
            passwordRef: nil, // encrypted_password handled separately via Keychain bridge
            epgURL: try cursor.getStringOptional(name: "epg_url"),
            refreshHrs: (try cursor.getIntOptional(name: "refresh_hrs")) ?? 24,
            lastSync: isoToEpoch(try cursor.getStringOptional(name: "last_sync")),
            lastEpgSync: isoToEpoch(try cursor.getStringOptional(name: "last_epg_sync")),
            lastSyncEtag: nil, // local-only, not synced
            lastSyncHash: nil, // local-only, not synced
            isActive: (try cursor.getIntOptional(name: "is_active")) == 1,
            sortOrder: (try cursor.getIntOptional(name: "sort_order")) ?? 0
        )
    }

    /// Convert a PlaylistRecord to SQL parameter values for INSERT/UPDATE.
    public static func playlistParams(_ record: PlaylistRecord) -> [Sendable?] {
        [
            record.name,
            record.type,
            record.url,
            record.username,
            nil as String?, // encrypted_password
            record.epgURL,
            record.refreshHrs,
            record.isActive ? 1 : 0,
            record.sortOrder,
            epochToISO(record.lastSync),
            epochToISO(record.lastEpgSync),
        ]
    }

    // MARK: - Channel Mapping

    public static func channelMapper(_ cursor: any SqlCursor) throws -> ChannelRecord {
        ChannelRecord(
            id: try cursor.getString(name: "id"),
            playlistID: try cursor.getString(name: "playlist_id"),
            sourceChannelID: try cursor.getStringOptional(name: "source_channel_id"),
            name: try cursor.getString(name: "name"),
            groupName: try cursor.getStringOptional(name: "group_name"),
            streamURL: try cursor.getString(name: "stream_url"),
            logoURL: try cursor.getStringOptional(name: "logo_url"),
            epgID: try cursor.getStringOptional(name: "epg_id"),
            tvgID: try cursor.getStringOptional(name: "tvg_id"),
            channelNum: try cursor.getIntOptional(name: "channel_number"),
            isFavorite: (try cursor.getIntOptional(name: "is_favorite")) == 1,
            isDeleted: (try cursor.getIntOptional(name: "is_deleted")) == 1,
            deletedAt: isoToEpoch(try cursor.getStringOptional(name: "deleted_at"))
        )
    }

    public static func channelParams(_ record: ChannelRecord) -> [Sendable?] {
        [
            record.playlistID,
            record.sourceChannelID,
            record.tvgID,
            record.name,
            record.groupName,
            record.epgID,
            record.logoURL,
            record.streamURL,
            record.channelNum,
            record.isFavorite ? 1 : 0,
            record.isDeleted ? 1 : 0,
            epochToISO(record.deletedAt),
        ]
    }

    // MARK: - VodItem Mapping

    public static func vodItemMapper(_ cursor: any SqlCursor) throws -> VodItemRecord {
        // PowerSync stores rating as text, GRDB stores as Double
        let ratingText = try cursor.getStringOptional(name: "rating")
        let ratingDouble = ratingText.flatMap { Double($0) }

        return VodItemRecord(
            id: try cursor.getString(name: "id"),
            playlistID: try cursor.getString(name: "playlist_id"),
            title: try cursor.getString(name: "title"),
            type: try cursor.getString(name: "type"),
            streamURL: try cursor.getStringOptional(name: "stream_url"),
            posterURL: try cursor.getStringOptional(name: "logo_url"), // PowerSync logo_url → posterURL
            backdropURL: nil, // Not synced
            description: try cursor.getStringOptional(name: "plot"), // PowerSync plot → description
            year: try cursor.getIntOptional(name: "year"),
            rating: ratingDouble,
            genre: try cursor.getStringOptional(name: "genre"),
            seriesID: try cursor.getStringOptional(name: "series_id"),
            seasonNum: try cursor.getIntOptional(name: "season_num"),
            episodeNum: try cursor.getIntOptional(name: "episode_num"),
            durationS: try cursor.getIntOptional(name: "duration") // PowerSync duration → durationS
        )
    }

    public static func vodItemParams(_ record: VodItemRecord) -> [Sendable?] {
        [
            record.playlistID,
            record.title,
            record.type,
            record.streamURL,
            record.posterURL, // posterURL → logo_url
            record.genre,
            record.year,
            record.rating.map { String($0) }, // Double → text
            record.durationS, // durationS → duration
            record.seasonNum,
            record.episodeNum,
            record.seriesID,
            nil as String?, // container_extension
            record.description, // description → plot
            nil as String?, // cast_list
            nil as String?, // director
        ]
    }

    // MARK: - WatchProgress Mapping

    /// Note: PowerSync uses auto-generated UUID `id` as PK, plus `content_id` as a column.
    /// GRDB uses `content_id` as PK directly. The mapper handles this asymmetry.
    public static func watchProgressMapper(_ cursor: any SqlCursor) throws -> WatchProgressRecord {
        WatchProgressRecord(
            contentID: try cursor.getString(name: "content_id"),
            playlistID: try cursor.getStringOptional(name: "playlist_id"),
            positionMs: (try cursor.getIntOptional(name: "position_ms")) ?? 0,
            durationMs: try cursor.getIntOptional(name: "duration_ms"),
            updatedAt: isoToEpoch(try cursor.getStringOptional(name: "updated_at")) ?? Int(Date().timeIntervalSince1970)
        )
    }

    public static func watchProgressParams(_ record: WatchProgressRecord) -> [Sendable?] {
        [
            record.contentID,
            record.playlistID,
            record.positionMs,
            record.durationMs,
            epochToISO(record.updatedAt),
        ]
    }
}
