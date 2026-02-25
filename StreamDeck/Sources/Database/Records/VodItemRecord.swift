import Foundation
import GRDB

/// A video-on-demand item (movie, series, or episode) from a playlist or Emby server.
public struct VodItemRecord: Equatable, Sendable, Codable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "vod_item"

    public var id: String
    public var playlistID: String
    public var title: String
    public var type: String // movie, series, episode
    public var streamURL: String?
    public var posterURL: String?
    public var backdropURL: String?
    public var description: String?
    public var year: Int?
    public var rating: Double?
    public var genre: String? // comma-separated
    public var seriesID: String?
    public var seasonNum: Int?
    public var episodeNum: Int?
    public var durationS: Int?

    public init(
        id: String,
        playlistID: String,
        title: String,
        type: String,
        streamURL: String? = nil,
        posterURL: String? = nil,
        backdropURL: String? = nil,
        description: String? = nil,
        year: Int? = nil,
        rating: Double? = nil,
        genre: String? = nil,
        seriesID: String? = nil,
        seasonNum: Int? = nil,
        episodeNum: Int? = nil,
        durationS: Int? = nil
    ) {
        self.id = id
        self.playlistID = playlistID
        self.title = title
        self.type = type
        self.streamURL = streamURL
        self.posterURL = posterURL
        self.backdropURL = backdropURL
        self.description = description
        self.year = year
        self.rating = rating
        self.genre = genre
        self.seriesID = seriesID
        self.seasonNum = seasonNum
        self.episodeNum = episodeNum
        self.durationS = durationS
    }

    enum CodingKeys: String, CodingKey {
        case id, title, type, description, year, rating, genre
        case playlistID = "playlist_id"
        case streamURL = "stream_url"
        case posterURL = "poster_url"
        case backdropURL = "backdrop_url"
        case seriesID = "series_id"
        case seasonNum = "season_num"
        case episodeNum = "episode_num"
        case durationS = "duration_s"
    }
}
