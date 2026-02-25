import XCTest
import Database
import EmbyClient
@testable import Repositories

final class EmbyConverterTests: XCTestCase {

    private let serverURL = URL(string: "http://emby.local:8096")!
    private let playlistID = "pl-emby-1"
    private let accessToken = "test-token"

    // MARK: - Movie

    func testFromEmbyMovie_allFields() {
        let item = EmbyItem(
            id: "movie-1", name: "Inception", type: "Movie",
            overview: "A mind-bending thriller",
            productionYear: 2010, communityRating: 8.8,
            runTimeTicks: 88800000000,
            imageTags: ["Primary": "tag-abc", "Backdrop": "tag-bd"],
            genreItems: [.init(name: "Action"), .init(name: "Sci-Fi")]
        )

        let record = EmbyConverter.fromEmbyMovie(
            item, playlistID: playlistID, serverURL: serverURL, accessToken: accessToken
        )

        XCTAssertEqual(record.id, "emby-pl-emby-1-movie-1")
        XCTAssertEqual(record.playlistID, playlistID)
        XCTAssertEqual(record.title, "Inception")
        XCTAssertEqual(record.type, "movie")
        XCTAssertEqual(record.description, "A mind-bending thriller")
        XCTAssertEqual(record.year, 2010)
        XCTAssertEqual(record.rating, 8.8)
        XCTAssertEqual(record.genre, "Action, Sci-Fi")
        XCTAssertEqual(record.durationS, 8880)
    }

    func testFromEmbyMovie_generatesStreamURL() {
        let item = EmbyItem(id: "m1", name: "Test", type: "Movie")
        let record = EmbyConverter.fromEmbyMovie(
            item, playlistID: playlistID, serverURL: serverURL, accessToken: accessToken
        )
        let streamURL = try! XCTUnwrap(record.streamURL)
        XCTAssertTrue(streamURL.contains("Videos/m1/stream"))
        XCTAssertTrue(streamURL.contains("api_key=test-token"))
    }

    func testFromEmbyMovie_generatesPosterURL() {
        let item = EmbyItem(id: "m1", name: "Test", type: "Movie", imageTags: ["Primary": "tag-p"])
        let record = EmbyConverter.fromEmbyMovie(
            item, playlistID: playlistID, serverURL: serverURL, accessToken: accessToken
        )
        let posterURL = try! XCTUnwrap(record.posterURL)
        XCTAssertTrue(posterURL.contains("Items/m1/Images/Primary"))
        XCTAssertTrue(posterURL.contains("tag=tag-p"))
    }

    func testFromEmbyMovie_minimalFields() {
        let item = EmbyItem(id: "m1", name: "Minimal", type: "Movie")
        let record = EmbyConverter.fromEmbyMovie(
            item, playlistID: playlistID, serverURL: serverURL, accessToken: accessToken
        )
        XCTAssertEqual(record.title, "Minimal")
        XCTAssertNil(record.description)
        XCTAssertNil(record.year)
        XCTAssertNil(record.rating)
        XCTAssertNil(record.genre)
        XCTAssertNil(record.durationS)
        XCTAssertNil(record.backdropURL)
    }

    // MARK: - Series

    func testFromEmbySeries_allFields() {
        let item = EmbyItem(
            id: "s1", name: "Breaking Bad", type: "Series",
            overview: "A chemistry teacher turns drug lord",
            productionYear: 2008, communityRating: 9.5,
            imageTags: ["Primary": "tag-bb"],
            genreItems: [.init(name: "Drama"), .init(name: "Crime")]
        )
        let record = EmbyConverter.fromEmbySeries(item, playlistID: playlistID, serverURL: serverURL)

        XCTAssertEqual(record.id, "emby-pl-emby-1-s1")
        XCTAssertEqual(record.type, "series")
        XCTAssertNil(record.streamURL)
        XCTAssertEqual(record.genre, "Drama, Crime")
        XCTAssertEqual(record.year, 2008)
    }

    // MARK: - Episode

    func testFromEmbyEpisode_allFields() {
        let item = EmbyItem(
            id: "ep-1", name: "Pilot", type: "Episode",
            overview: "Walter White begins",
            runTimeTicks: 35400000000,
            seriesId: "series-1",
            parentIndexNumber: 1, indexNumber: 1
        )
        let record = EmbyConverter.fromEmbyEpisode(
            item, playlistID: playlistID, seriesID: "emby-pl-emby-1-series-1",
            serverURL: serverURL, accessToken: accessToken
        )

        XCTAssertEqual(record.id, "emby-pl-emby-1-ep-1")
        XCTAssertEqual(record.type, "episode")
        XCTAssertEqual(record.seriesID, "emby-pl-emby-1-series-1")
        XCTAssertEqual(record.seasonNum, 1)
        XCTAssertEqual(record.episodeNum, 1)
        XCTAssertEqual(record.durationS, 3540)
        XCTAssertNotNil(record.streamURL)
    }

    func testFromEmbyEpisode_deterministicID() {
        let item = EmbyItem(id: "ep-1", name: "Pilot", type: "Episode")
        let r1 = EmbyConverter.fromEmbyEpisode(
            item, playlistID: playlistID, seriesID: "s1",
            serverURL: serverURL, accessToken: accessToken
        )
        let r2 = EmbyConverter.fromEmbyEpisode(
            item, playlistID: playlistID, seriesID: "s1",
            serverURL: serverURL, accessToken: accessToken
        )
        XCTAssertEqual(r1.id, r2.id)
    }
}
