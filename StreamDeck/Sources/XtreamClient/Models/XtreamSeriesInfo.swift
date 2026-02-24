import Foundation

/// Detailed series info from get_series_info, including seasons and episodes.
public struct XtreamSeriesInfo: Equatable, Sendable, Decodable {
    public let seasons: [Season]?
    public let info: SeriesMetadata?
    public let episodes: [String: [Episode]]?

    public struct SeriesMetadata: Equatable, Sendable, Decodable {
        public let name: String?
        public let cover: String?
        public let plot: String?
        public let cast: String?
        public let director: String?
        public let genre: String?
        public let releaseDate: String?
        public let rating: LenientOptionalDouble?
        public let backdropPath: LenientStringOrArray?
        public let categoryId: LenientString?
    }

    public struct Season: Equatable, Sendable, Decodable {
        public let seasonNumber: LenientInt
        public let name: String?
        public let airDate: String?
        public let episodeCount: LenientOptionalInt?
        public let cover: String?
        public let overview: String?
    }

    public struct Episode: Equatable, Sendable, Decodable {
        public let id: LenientString
        public let episodeNum: LenientInt
        public let title: String?
        public let containerExtension: String?
        public let info: EpisodeInfo?
        public let season: LenientInt
        public let added: LenientOptionalInt?
        public let customSid: String?
        public let directSource: String?
    }

    public struct EpisodeInfo: Equatable, Sendable, Decodable {
        public let movieImage: String?
        public let plot: String?
        public let duration: String?
        public let durationSecs: LenientOptionalInt?
        public let rating: LenientOptionalDouble?
        public let releasedate: String?
    }
}
