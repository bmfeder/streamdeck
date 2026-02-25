import XCTest
@testable import EmbyClient

final class EmbyDecodingTests: XCTestCase {

    private let decoder = JSONDecoder()

    // MARK: - EmbyAuthResponse

    func testAuthResponse_decodesCorrectly() throws {
        let data = Data(EmbyFixtures.authResponse.utf8)
        let result = try decoder.decode(EmbyAuthResponse.self, from: data)
        XCTAssertEqual(result.user.id, "user-123")
        XCTAssertEqual(result.user.name, "testuser")
        XCTAssertEqual(result.accessToken, "abc-token-xyz")
    }

    // MARK: - EmbyItem

    func testItem_movieAllFields() throws {
        let data = Data(EmbyFixtures.moviesResponse.utf8)
        let response = try decoder.decode(EmbyItemsResponse.self, from: data)
        let movie = response.items[0]

        XCTAssertEqual(movie.id, "movie-1")
        XCTAssertEqual(movie.name, "Inception")
        XCTAssertEqual(movie.type, "Movie")
        XCTAssertEqual(movie.overview, "A mind-bending thriller")
        XCTAssertEqual(movie.productionYear, 2010)
        XCTAssertEqual(movie.communityRating, 8.8)
        XCTAssertEqual(movie.runTimeTicks, 88800000000)
        XCTAssertEqual(movie.imageTags?["Primary"], "tag-abc")
        XCTAssertEqual(movie.genreItems?.map(\.name), ["Action", "Sci-Fi"])
    }

    func testItem_movieMinimalFields() throws {
        let data = Data(EmbyFixtures.movieMinimal.utf8)
        let item = try decoder.decode(EmbyItem.self, from: data)

        XCTAssertEqual(item.id, "m-min")
        XCTAssertEqual(item.name, "Minimal Movie")
        XCTAssertEqual(item.type, "Movie")
        XCTAssertNil(item.overview)
        XCTAssertNil(item.productionYear)
        XCTAssertNil(item.communityRating)
        XCTAssertNil(item.runTimeTicks)
        XCTAssertNil(item.imageTags)
        XCTAssertNil(item.genreItems)
    }

    func testItem_episodeWithSeasonAndNumber() throws {
        let data = Data(EmbyFixtures.episodesResponse.utf8)
        let response = try decoder.decode(EmbyItemsResponse.self, from: data)
        let ep = response.items[0]

        XCTAssertEqual(ep.type, "Episode")
        XCTAssertEqual(ep.seriesId, "series-1")
        XCTAssertEqual(ep.seriesName, "Breaking Bad")
        XCTAssertEqual(ep.parentIndexNumber, 1)
        XCTAssertEqual(ep.indexNumber, 1)
    }

    // MARK: - Computed Properties

    func testItem_durationSeconds_computed() {
        let item = EmbyItem(id: "1", name: "Test", type: "Movie", runTimeTicks: 72000000000)
        XCTAssertEqual(item.durationSeconds, 7200) // 2 hours
    }

    func testItem_durationSeconds_nilWhenNoTicks() {
        let item = EmbyItem(id: "1", name: "Test", type: "Movie")
        XCTAssertNil(item.durationSeconds)
    }

    func testItem_resumePositionMs_computed() {
        let userData = EmbyItem.UserData(playbackPositionTicks: 36000000000, played: false)
        let item = EmbyItem(id: "1", name: "Test", type: "Movie", userData: userData)
        XCTAssertEqual(item.resumePositionMs, 3600000) // 1 hour in ms
    }

    func testItem_resumePositionMs_nilWhenZero() {
        let userData = EmbyItem.UserData(playbackPositionTicks: 0, played: false)
        let item = EmbyItem(id: "1", name: "Test", type: "Movie", userData: userData)
        XCTAssertNil(item.resumePositionMs)
    }

    func testItem_resumePositionMs_nilWhenNoUserData() {
        let item = EmbyItem(id: "1", name: "Test", type: "Movie")
        XCTAssertNil(item.resumePositionMs)
    }

    // MARK: - EmbyLibrary

    func testLibraries_decodesCorrectly() throws {
        let data = Data(EmbyFixtures.librariesResponse.utf8)
        let response = try decoder.decode(EmbyLibrariesResponse.self, from: data)

        XCTAssertEqual(response.items.count, 3)
        XCTAssertEqual(response.items[0].id, "lib-1")
        XCTAssertEqual(response.items[0].collectionType, "movies")
        XCTAssertEqual(response.items[2].collectionType, "music")
    }
}
