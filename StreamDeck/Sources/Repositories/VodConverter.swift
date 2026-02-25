import Foundation
import Database
import M3UParser
import XtreamClient

/// Static conversion helpers for transforming parsed data into VodItemRecords.
/// No database access — pure data mapping only.
public enum VodConverter {

    nonisolated(unsafe) private static let yearPattern = try! Regex(#"\((\d{4})\)\s*$"#)

    /// Converts an M3U ParsedChannel with `duration > 0` into a VodItemRecord.
    ///
    /// Mapping:
    /// - `name` → `title` (with year extracted if present)
    /// - `streamURL` → `streamURL`
    /// - `groupTitle` → `genre`
    /// - `tvgLogo` → `posterURL`
    /// - `duration` → `durationS`
    /// - Type: "series" if groupTitle contains "Series", otherwise "movie"
    public static func fromParsedChannel(
        _ parsed: ParsedChannel,
        playlistID: String,
        id: String? = nil
    ) -> VodItemRecord {
        let extractedYear = extractYear(from: parsed.name)
        let type = (parsed.groupTitle?.localizedCaseInsensitiveContains("series") == true
            || parsed.groupTitle?.localizedCaseInsensitiveContains("episode") == true)
            ? "series" : "movie"

        return VodItemRecord(
            id: id ?? UUID().uuidString,
            playlistID: playlistID,
            title: parsed.name,
            type: type,
            streamURL: parsed.streamURL.absoluteString,
            posterURL: parsed.tvgLogo?.absoluteString,
            year: extractedYear,
            genre: parsed.groupTitle,
            durationS: parsed.duration > 0 ? parsed.duration : nil
        )
    }

    /// Converts an Xtream VOD stream into a VodItemRecord.
    ///
    /// Mapping:
    /// - `name` → `title`
    /// - `streamIcon` → `posterURL`
    /// - `rating` → `rating`
    /// - `categoryName` → `genre`
    /// - Caller provides pre-built `streamURL` via `client.vodStreamURL(...)`
    public static func fromXtreamVODStream(
        _ stream: XtreamVODStream,
        playlistID: String,
        categoryName: String?,
        streamURL: String,
        id: String? = nil
    ) -> VodItemRecord {
        VodItemRecord(
            id: id ?? UUID().uuidString,
            playlistID: playlistID,
            title: stream.name,
            type: "movie",
            streamURL: streamURL,
            posterURL: stream.streamIcon,
            rating: stream.rating?.value,
            genre: categoryName
        )
    }

    /// Converts an Xtream series listing into a VodItemRecord (type="series").
    /// Series parents are not directly playable — no streamURL.
    ///
    /// Mapping:
    /// - `name` → `title`
    /// - `cover` → `posterURL`
    /// - `plot` → `description`
    /// - `genre` → `genre`
    /// - `rating` → `rating`
    /// - `backdropPath.values.first` → `backdropURL`
    /// - `releaseDate` → extract year
    public static func fromXtreamSeries(
        _ series: XtreamSeries,
        playlistID: String,
        categoryName: String?,
        id: String? = nil
    ) -> VodItemRecord {
        let year = series.releaseDate.flatMap { extractYearFromDate($0) ?? extractYear(from: $0) }
        let genre = series.genre ?? categoryName

        return VodItemRecord(
            id: id ?? UUID().uuidString,
            playlistID: playlistID,
            title: series.name,
            type: "series",
            posterURL: series.cover,
            backdropURL: series.backdropPath?.values.first,
            description: series.plot,
            year: year,
            rating: series.rating?.value,
            genre: genre
        )
    }

    /// Converts an Xtream series episode into a VodItemRecord (type="episode").
    ///
    /// Mapping:
    /// - `title` → `title` (falls back to "Episode N")
    /// - `info.movieImage` → `posterURL`
    /// - `info.plot` → `description`
    /// - `season` → `seasonNum`
    /// - `episodeNum` → `episodeNum`
    /// - `info.durationSecs` → `durationS`
    /// - `info.rating` → `rating`
    /// - Caller provides pre-built `streamURL` via `client.seriesStreamURL(...)`
    public static func fromXtreamEpisode(
        _ episode: XtreamSeriesInfo.Episode,
        playlistID: String,
        seriesID: String,
        streamURL: String,
        id: String? = nil
    ) -> VodItemRecord {
        let title = episode.title ?? "Episode \(episode.episodeNum.value)"

        return VodItemRecord(
            id: id ?? UUID().uuidString,
            playlistID: playlistID,
            title: title,
            type: "episode",
            streamURL: streamURL,
            posterURL: episode.info?.movieImage,
            description: episode.info?.plot,
            rating: episode.info?.rating?.value,
            seriesID: seriesID,
            seasonNum: episode.season.value,
            episodeNum: episode.episodeNum.value,
            durationS: episode.info?.durationSecs?.value
        )
    }

    // MARK: - Private Helpers

    /// Extracts a 4-digit year from a string, e.g. "The Matrix (1999)" → 1999.
    private static func extractYear(from text: String) -> Int? {
        guard let match = text.firstMatch(of: yearPattern),
              let yearStr = match.output[1].substring else { return nil }
        return Int(yearStr)
    }

    /// Extracts a year from a date string like "2008-01-20" or "2008".
    private static func extractYearFromDate(_ text: String) -> Int? {
        let prefix = text.prefix(4)
        guard prefix.count == 4, let year = Int(prefix), year >= 1900, year <= 2100 else { return nil }
        return year
    }
}
