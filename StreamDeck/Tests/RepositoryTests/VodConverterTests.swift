import XCTest
import Foundation
import M3UParser
import XtreamClient
import Database
@testable import Repositories

final class VodConverterTests: XCTestCase {

    // MARK: - Helpers

    private func makeXtreamVODStream(
        num: Int = 1,
        name: String = "Test Movie",
        streamType: String? = "movie",
        streamId: Int = 5001,
        streamIcon: String? = nil,
        rating: String? = nil,
        added: String? = nil,
        categoryId: String = "10",
        containerExtension: String? = "mp4"
    ) throws -> XtreamVODStream {
        var dict: [String: Any] = [
            "num": num,
            "name": name,
            "stream_id": streamId,
            "category_id": categoryId,
        ]
        if let streamType { dict["stream_type"] = streamType }
        if let streamIcon { dict["stream_icon"] = streamIcon }
        if let rating { dict["rating"] = rating }
        if let added { dict["added"] = added }
        if let containerExtension { dict["container_extension"] = containerExtension }

        let data = try JSONSerialization.data(withJSONObject: dict)
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(XtreamVODStream.self, from: data)
    }

    private func makeXtreamSeries(
        num: Int = 1,
        name: String = "Test Series",
        seriesId: Int = 3001,
        cover: String? = nil,
        plot: String? = nil,
        genre: String? = nil,
        releaseDate: String? = nil,
        rating: String? = nil,
        categoryId: String = "20",
        backdropPath: Any? = nil
    ) throws -> XtreamSeries {
        var dict: [String: Any] = [
            "num": num,
            "name": name,
            "series_id": seriesId,
            "category_id": categoryId,
        ]
        if let cover { dict["cover"] = cover }
        if let plot { dict["plot"] = plot }
        if let genre { dict["genre"] = genre }
        if let releaseDate { dict["release_date"] = releaseDate }
        if let rating { dict["rating"] = rating }
        if let backdropPath { dict["backdrop_path"] = backdropPath }

        let data = try JSONSerialization.data(withJSONObject: dict)
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(XtreamSeries.self, from: data)
    }

    private func makeXtreamEpisode(
        id: String = "45678",
        episodeNum: Int = 1,
        title: String? = "Pilot",
        containerExtension: String? = "mkv",
        season: Int = 1,
        movieImage: String? = nil,
        plot: String? = nil,
        durationSecs: Int? = nil,
        rating: String? = nil
    ) throws -> XtreamSeriesInfo.Episode {
        var infoDict: [String: Any] = [:]
        if let movieImage { infoDict["movie_image"] = movieImage }
        if let plot { infoDict["plot"] = plot }
        if let durationSecs { infoDict["duration_secs"] = durationSecs }
        if let rating { infoDict["rating"] = rating }

        var dict: [String: Any] = [
            "id": id,
            "episode_num": episodeNum,
            "season": season,
        ]
        if let title { dict["title"] = title }
        if let containerExtension { dict["container_extension"] = containerExtension }
        if !infoDict.isEmpty { dict["info"] = infoDict }

        let data = try JSONSerialization.data(withJSONObject: dict)
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(XtreamSeriesInfo.Episode.self, from: data)
    }

    // MARK: - M3U → VodItemRecord

    func testFromParsedChannel_movieWithAllFields() {
        let parsed = ParsedChannel(
            name: "The Matrix (1999)",
            streamURL: URL(string: "http://vod.example.com/movies/matrix.mp4")!,
            groupTitle: "Movies",
            tvgLogo: URL(string: "http://example.com/matrix.jpg"),
            duration: 7200
        )

        let record = VodConverter.fromParsedChannel(parsed, playlistID: "pl-1", id: "vod-1")

        XCTAssertEqual(record.id, "vod-1")
        XCTAssertEqual(record.playlistID, "pl-1")
        XCTAssertEqual(record.title, "The Matrix (1999)")
        XCTAssertEqual(record.type, "movie")
        XCTAssertEqual(record.streamURL, "http://vod.example.com/movies/matrix.mp4")
        XCTAssertEqual(record.posterURL, "http://example.com/matrix.jpg")
        XCTAssertEqual(record.genre, "Movies")
        XCTAssertEqual(record.year, 1999)
        XCTAssertEqual(record.durationS, 7200)
    }

    func testFromParsedChannel_minimalFields() {
        let parsed = ParsedChannel(
            name: "Unknown Movie",
            streamURL: URL(string: "http://example.com/movie.mp4")!,
            duration: 3600
        )

        let record = VodConverter.fromParsedChannel(parsed, playlistID: "pl-1", id: "vod-2")

        XCTAssertEqual(record.title, "Unknown Movie")
        XCTAssertEqual(record.type, "movie")
        XCTAssertEqual(record.streamURL, "http://example.com/movie.mp4")
        XCTAssertNil(record.posterURL)
        XCTAssertNil(record.genre)
        XCTAssertNil(record.year)
        XCTAssertEqual(record.durationS, 3600)
    }

    func testFromParsedChannel_seriesGroupTitle_setsSeries() {
        let parsed = ParsedChannel(
            name: "Breaking Bad S01E01",
            streamURL: URL(string: "http://example.com/bb.mp4")!,
            groupTitle: "Series | Drama",
            duration: 2700
        )

        let record = VodConverter.fromParsedChannel(parsed, playlistID: "pl-1", id: "vod-3")

        XCTAssertEqual(record.type, "series")
    }

    func testFromParsedChannel_generatesUUID_whenNoIDProvided() {
        let parsed = ParsedChannel(
            name: "Test",
            streamURL: URL(string: "http://example.com/test.mp4")!,
            duration: 100
        )

        let record = VodConverter.fromParsedChannel(parsed, playlistID: "pl-1")

        XCTAssertFalse(record.id.isEmpty)
        XCTAssertNotNil(UUID(uuidString: record.id))
    }

    // MARK: - Xtream VOD → VodItemRecord

    func testFromXtreamVODStream_allFields() throws {
        let stream = try makeXtreamVODStream(
            name: "Inception",
            streamId: 5001,
            streamIcon: "https://cdn.example.com/inception.jpg",
            rating: "8.8",
            categoryId: "10"
        )

        let record = VodConverter.fromXtreamVODStream(
            stream,
            playlistID: "pl-2",
            categoryName: "Action Movies",
            streamURL: "http://server.com/movie/user/pass/5001.mp4",
            id: "vod-xt-1"
        )

        XCTAssertEqual(record.id, "vod-xt-1")
        XCTAssertEqual(record.playlistID, "pl-2")
        XCTAssertEqual(record.title, "Inception")
        XCTAssertEqual(record.type, "movie")
        XCTAssertEqual(record.streamURL, "http://server.com/movie/user/pass/5001.mp4")
        XCTAssertEqual(record.posterURL, "https://cdn.example.com/inception.jpg")
        XCTAssertEqual(record.genre, "Action Movies")
        XCTAssertEqual(record.rating, 8.8)
    }

    func testFromXtreamVODStream_nilOptionals() throws {
        let stream = try makeXtreamVODStream(
            name: "Unknown",
            streamId: 99,
            streamIcon: nil,
            rating: nil
        )

        let record = VodConverter.fromXtreamVODStream(
            stream,
            playlistID: "pl-2",
            categoryName: nil,
            streamURL: "http://server.com/movie/user/pass/99.mp4",
            id: "vod-xt-2"
        )

        XCTAssertEqual(record.title, "Unknown")
        XCTAssertNil(record.posterURL)
        XCTAssertNil(record.genre)
        XCTAssertNil(record.rating)
    }

    // MARK: - Xtream Series → VodItemRecord

    func testFromXtreamSeries_allFields() throws {
        let series = try makeXtreamSeries(
            name: "Breaking Bad",
            seriesId: 3001,
            cover: "https://cdn.example.com/bb.jpg",
            plot: "A chemistry teacher turns to making meth.",
            genre: "Drama, Crime",
            releaseDate: "2008-01-20",
            rating: "9.5",
            backdropPath: ["https://cdn.example.com/bb-bg.jpg"]
        )

        let record = VodConverter.fromXtreamSeries(
            series,
            playlistID: "pl-2",
            categoryName: "Drama Series",
            id: "series-1"
        )

        XCTAssertEqual(record.id, "series-1")
        XCTAssertEqual(record.playlistID, "pl-2")
        XCTAssertEqual(record.title, "Breaking Bad")
        XCTAssertEqual(record.type, "series")
        XCTAssertNil(record.streamURL) // series not directly playable
        XCTAssertEqual(record.posterURL, "https://cdn.example.com/bb.jpg")
        XCTAssertEqual(record.backdropURL, "https://cdn.example.com/bb-bg.jpg")
        XCTAssertEqual(record.description, "A chemistry teacher turns to making meth.")
        XCTAssertEqual(record.genre, "Drama, Crime") // series.genre takes precedence over categoryName
        XCTAssertEqual(record.year, 2008)
        XCTAssertEqual(record.rating, 9.5)
    }

    // MARK: - Xtream Episode → VodItemRecord

    func testFromXtreamEpisode_allFields() throws {
        let episode = try makeXtreamEpisode(
            id: "45678",
            episodeNum: 1,
            title: "Pilot",
            containerExtension: "mkv",
            season: 1,
            movieImage: "https://cdn.example.com/ep1.jpg",
            plot: "Walter White begins his journey.",
            durationSecs: 3540,
            rating: "9.0"
        )

        let record = VodConverter.fromXtreamEpisode(
            episode,
            playlistID: "pl-2",
            seriesID: "series-1",
            streamURL: "http://server.com/series/user/pass/45678.mkv",
            id: "ep-1"
        )

        XCTAssertEqual(record.id, "ep-1")
        XCTAssertEqual(record.playlistID, "pl-2")
        XCTAssertEqual(record.title, "Pilot")
        XCTAssertEqual(record.type, "episode")
        XCTAssertEqual(record.streamURL, "http://server.com/series/user/pass/45678.mkv")
        XCTAssertEqual(record.posterURL, "https://cdn.example.com/ep1.jpg")
        XCTAssertEqual(record.description, "Walter White begins his journey.")
        XCTAssertEqual(record.seriesID, "series-1")
        XCTAssertEqual(record.seasonNum, 1)
        XCTAssertEqual(record.episodeNum, 1)
        XCTAssertEqual(record.durationS, 3540)
        XCTAssertEqual(record.rating, 9.0)
    }
}
