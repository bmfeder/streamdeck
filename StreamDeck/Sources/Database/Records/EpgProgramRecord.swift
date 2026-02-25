import Foundation
import GRDB

/// An EPG programme entry from XMLTV data.
/// Uses channel_epg_id (string) rather than FK to Channel for flexible matching.
/// UNIQUE(channel_epg_id, start_time) prevents duplicate programmes in the same slot.
public struct EpgProgramRecord: Equatable, Sendable, Codable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "epg_program"

    public var id: String
    public var channelEpgID: String
    public var title: String
    public var description: String?
    public var startTime: Int
    public var endTime: Int
    public var category: String?
    public var iconURL: String?

    public init(
        id: String,
        channelEpgID: String,
        title: String,
        description: String? = nil,
        startTime: Int,
        endTime: Int,
        category: String? = nil,
        iconURL: String? = nil
    ) {
        self.id = id
        self.channelEpgID = channelEpgID
        self.title = title
        self.description = description
        self.startTime = startTime
        self.endTime = endTime
        self.category = category
        self.iconURL = iconURL
    }

    enum CodingKeys: String, CodingKey {
        case id, title, description, category
        case channelEpgID = "channel_epg_id"
        case startTime = "start_time"
        case endTime = "end_time"
        case iconURL = "icon_url"
    }
}
