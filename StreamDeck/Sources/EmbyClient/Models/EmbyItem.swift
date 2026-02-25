import Foundation

/// An Emby media item (Movie, Series, or Episode).
public struct EmbyItem: Equatable, Sendable, Decodable, Identifiable {
    public let id: String
    public let name: String
    public let type: String
    public let overview: String?
    public let productionYear: Int?
    public let officialRating: String?
    public let communityRating: Double?
    public let runTimeTicks: Int64?
    public let seriesId: String?
    public let seriesName: String?
    public let parentIndexNumber: Int?
    public let indexNumber: Int?
    public let imageTags: [String: String]?
    public let userData: UserData?
    public let genreItems: [GenreItem]?

    public struct UserData: Equatable, Sendable, Decodable {
        public let playbackPositionTicks: Int64
        public let played: Bool

        enum CodingKeys: String, CodingKey {
            case playbackPositionTicks = "PlaybackPositionTicks"
            case played = "Played"
        }

        public init(playbackPositionTicks: Int64 = 0, played: Bool = false) {
            self.playbackPositionTicks = playbackPositionTicks
            self.played = played
        }
    }

    public struct GenreItem: Equatable, Sendable, Decodable {
        public let name: String

        enum CodingKeys: String, CodingKey {
            case name = "Name"
        }

        public init(name: String) {
            self.name = name
        }
    }

    enum CodingKeys: String, CodingKey {
        case id = "Id"
        case name = "Name"
        case type = "Type"
        case overview = "Overview"
        case productionYear = "ProductionYear"
        case officialRating = "OfficialRating"
        case communityRating = "CommunityRating"
        case runTimeTicks = "RunTimeTicks"
        case seriesId = "SeriesId"
        case seriesName = "SeriesName"
        case parentIndexNumber = "ParentIndexNumber"
        case indexNumber = "IndexNumber"
        case imageTags = "ImageTags"
        case userData = "UserData"
        case genreItems = "GenreItems"
    }

    /// Duration in seconds, derived from runTimeTicks (1 tick = 100ns).
    public var durationSeconds: Int? {
        guard let ticks = runTimeTicks, ticks > 0 else { return nil }
        return Int(ticks / 10_000_000)
    }

    /// Playback resume position in milliseconds, derived from userData.
    public var resumePositionMs: Int? {
        guard let ticks = userData?.playbackPositionTicks, ticks > 0 else { return nil }
        return Int(ticks / 10_000)
    }

    public init(
        id: String,
        name: String,
        type: String,
        overview: String? = nil,
        productionYear: Int? = nil,
        officialRating: String? = nil,
        communityRating: Double? = nil,
        runTimeTicks: Int64? = nil,
        seriesId: String? = nil,
        seriesName: String? = nil,
        parentIndexNumber: Int? = nil,
        indexNumber: Int? = nil,
        imageTags: [String: String]? = nil,
        userData: UserData? = nil,
        genreItems: [GenreItem]? = nil
    ) {
        self.id = id
        self.name = name
        self.type = type
        self.overview = overview
        self.productionYear = productionYear
        self.officialRating = officialRating
        self.communityRating = communityRating
        self.runTimeTicks = runTimeTicks
        self.seriesId = seriesId
        self.seriesName = seriesName
        self.parentIndexNumber = parentIndexNumber
        self.indexNumber = indexNumber
        self.imageTags = imageTags
        self.userData = userData
        self.genreItems = genreItems
    }
}
