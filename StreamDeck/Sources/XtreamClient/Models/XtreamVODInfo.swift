import Foundation

/// Detailed VOD metadata from get_vod_info.
public struct XtreamVODInfo: Equatable, Sendable, Decodable {
    public let info: VODMetadata?
    public let movieData: VODMovieData?

    public struct VODMetadata: Equatable, Sendable, Decodable {
        public let movieImage: String?
        public let backdropPath: LenientStringOrArray?
        public let tmdbId: LenientOptionalInt?
        public let releasedate: String?
        public let youtubeTrailer: String?
        public let genre: String?
        public let plot: String?
        public let cast: String?
        public let rating: LenientOptionalDouble?
        public let director: String?
        public let duration: String?
        public let durationSecs: LenientOptionalInt?
    }

    public struct VODMovieData: Equatable, Sendable, Decodable {
        public let streamId: LenientInt
        public let name: String?
        public let added: LenientOptionalInt?
        public let categoryId: LenientString?
        public let containerExtension: String?
        public let customSid: String?
        public let directSource: String?
    }
}
