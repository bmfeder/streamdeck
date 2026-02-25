import Foundation
import Database
import EmbyClient

/// Static conversion helpers for transforming Emby API models into VodItemRecords.
/// No database access — pure data mapping only.
public enum EmbyConverter {

    /// Converts an EmbyItem (Movie) to a VodItemRecord.
    public static func fromEmbyMovie(
        _ item: EmbyItem,
        playlistID: String,
        serverURL: URL,
        accessToken: String
    ) -> VodItemRecord {
        VodItemRecord(
            id: "emby-\(playlistID)-\(item.id)",
            playlistID: playlistID,
            title: item.name,
            type: "movie",
            streamURL: EmbyClient.directStreamURL(
                serverURL: serverURL, itemId: item.id, accessToken: accessToken
            ).absoluteString,
            posterURL: posterURL(serverURL: serverURL, item: item),
            backdropURL: backdropURL(serverURL: serverURL, item: item),
            description: item.overview,
            year: item.productionYear,
            rating: item.communityRating,
            genre: item.genreItems?.map(\.name).joined(separator: ", "),
            durationS: item.durationSeconds
        )
    }

    /// Converts an EmbyItem (Series) to a VodItemRecord.
    /// Series parents are not directly playable — no streamURL.
    public static func fromEmbySeries(
        _ item: EmbyItem,
        playlistID: String,
        serverURL: URL
    ) -> VodItemRecord {
        VodItemRecord(
            id: "emby-\(playlistID)-\(item.id)",
            playlistID: playlistID,
            title: item.name,
            type: "series",
            posterURL: posterURL(serverURL: serverURL, item: item),
            backdropURL: backdropURL(serverURL: serverURL, item: item),
            description: item.overview,
            year: item.productionYear,
            rating: item.communityRating,
            genre: item.genreItems?.map(\.name).joined(separator: ", ")
        )
    }

    /// Converts an EmbyItem (Episode) to a VodItemRecord.
    public static func fromEmbyEpisode(
        _ item: EmbyItem,
        playlistID: String,
        seriesID: String,
        serverURL: URL,
        accessToken: String
    ) -> VodItemRecord {
        VodItemRecord(
            id: "emby-\(playlistID)-\(item.id)",
            playlistID: playlistID,
            title: item.name,
            type: "episode",
            streamURL: EmbyClient.directStreamURL(
                serverURL: serverURL, itemId: item.id, accessToken: accessToken
            ).absoluteString,
            posterURL: posterURL(serverURL: serverURL, item: item),
            description: item.overview,
            seriesID: seriesID,
            seasonNum: item.parentIndexNumber,
            episodeNum: item.indexNumber,
            durationS: item.durationSeconds
        )
    }

    // MARK: - Private

    private static func posterURL(serverURL: URL, item: EmbyItem) -> String? {
        let tag = item.imageTags?["Primary"]
        return EmbyClient.imageURL(
            serverURL: serverURL, itemId: item.id,
            imageType: "Primary", tag: tag, maxWidth: 300
        ).absoluteString
    }

    private static func backdropURL(serverURL: URL, item: EmbyItem) -> String? {
        guard item.imageTags?["Backdrop"] != nil else { return nil }
        return EmbyClient.imageURL(
            serverURL: serverURL, itemId: item.id,
            imageType: "Backdrop", tag: item.imageTags?["Backdrop"], maxWidth: 1280
        ).absoluteString
    }
}
