import Foundation
import GRDB

/// Unified watch history and resume position for both live TV and VOD content.
/// Enables "recently watched" and resume playback features.
public struct WatchProgressRecord: Equatable, Sendable, Codable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "watch_progress"

    public var contentID: String
    public var playlistID: String?
    public var positionMs: Int
    public var durationMs: Int?
    public var updatedAt: Int

    public init(
        contentID: String,
        playlistID: String? = nil,
        positionMs: Int = 0,
        durationMs: Int? = nil,
        updatedAt: Int
    ) {
        self.contentID = contentID
        self.playlistID = playlistID
        self.positionMs = positionMs
        self.durationMs = durationMs
        self.updatedAt = updatedAt
    }

    enum CodingKeys: String, CodingKey {
        case contentID = "content_id"
        case playlistID = "playlist_id"
        case positionMs = "position_ms"
        case durationMs = "duration_ms"
        case updatedAt = "updated_at"
    }
}
