import Foundation
import GRDB

/// A live TV channel extracted from a playlist.
/// Uses three-tier identity strategy: id (canonical) → source_channel_id (provider) → tvg_id/name fallback.
/// Supports soft-delete with 30-day purge policy.
public struct ChannelRecord: Equatable, Sendable, Codable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "channel"

    public var id: String
    public var playlistID: String
    public var sourceChannelID: String?
    public var name: String
    public var groupName: String?
    public var streamURL: String
    public var logoURL: String?
    public var epgID: String?
    public var tvgID: String?
    public var channelNum: Int?
    public var isFavorite: Bool
    public var isDeleted: Bool
    public var deletedAt: Int?

    public init(
        id: String,
        playlistID: String,
        sourceChannelID: String? = nil,
        name: String,
        groupName: String? = nil,
        streamURL: String,
        logoURL: String? = nil,
        epgID: String? = nil,
        tvgID: String? = nil,
        channelNum: Int? = nil,
        isFavorite: Bool = false,
        isDeleted: Bool = false,
        deletedAt: Int? = nil
    ) {
        self.id = id
        self.playlistID = playlistID
        self.sourceChannelID = sourceChannelID
        self.name = name
        self.groupName = groupName
        self.streamURL = streamURL
        self.logoURL = logoURL
        self.epgID = epgID
        self.tvgID = tvgID
        self.channelNum = channelNum
        self.isFavorite = isFavorite
        self.isDeleted = isDeleted
        self.deletedAt = deletedAt
    }

    enum CodingKeys: String, CodingKey {
        case id, name
        case playlistID = "playlist_id"
        case sourceChannelID = "source_channel_id"
        case groupName = "group_name"
        case streamURL = "stream_url"
        case logoURL = "logo_url"
        case epgID = "epg_id"
        case tvgID = "tvg_id"
        case channelNum = "channel_num"
        case isFavorite = "is_favorite"
        case isDeleted = "is_deleted"
        case deletedAt = "deleted_at"
    }
}
