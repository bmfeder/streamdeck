import XCTest
import GRDB
import Database
@testable import Repositories

final class VodRepositoryTests: XCTestCase {
    var dbManager: DatabaseManager!
    var repo: VodRepository!

    override func setUpWithError() throws {
        try super.setUpWithError()
        dbManager = try DatabaseManager()
        repo = VodRepository(dbManager: dbManager)

        // Insert a default playlist for FK references
        let playlist = PlaylistRecord(id: "pl-1", name: "Test", type: "m3u", url: "http://example.com/pl.m3u")
        try dbManager.dbQueue.write { db in try playlist.insert(db) }
    }

    override func tearDown() {
        repo = nil
        dbManager = nil
        super.tearDown()
    }

    // MARK: - Helpers

    private func makeVodItem(
        id: String = "vod-1",
        playlistID: String = "pl-1",
        title: String = "Test Movie",
        type: String = "movie",
        streamURL: String? = "http://example.com/movie.mp4",
        posterURL: String? = nil,
        year: Int? = nil,
        rating: Double? = nil,
        genre: String? = nil,
        seriesID: String? = nil,
        seasonNum: Int? = nil,
        episodeNum: Int? = nil,
        durationS: Int? = nil
    ) -> VodItemRecord {
        VodItemRecord(
            id: id,
            playlistID: playlistID,
            title: title,
            type: type,
            streamURL: streamURL,
            posterURL: posterURL,
            year: year,
            rating: rating,
            genre: genre,
            seriesID: seriesID,
            seasonNum: seasonNum,
            episodeNum: episodeNum,
            durationS: durationS
        )
    }

    // MARK: - CRUD

    func testCreate_andFetch() throws {
        let item = makeVodItem()
        try repo.create(item)

        let fetched = try repo.get(id: "vod-1")
        XCTAssertEqual(fetched?.title, "Test Movie")
        XCTAssertEqual(fetched?.type, "movie")
        XCTAssertEqual(fetched?.streamURL, "http://example.com/movie.mp4")
    }

    func testUpdate_modifiesRecord() throws {
        var item = makeVodItem()
        try repo.create(item)

        item.title = "Updated Title"
        item.rating = 8.5
        try repo.update(item)

        let fetched = try repo.get(id: "vod-1")
        XCTAssertEqual(fetched?.title, "Updated Title")
        XCTAssertEqual(fetched?.rating, 8.5)
    }

    func testDelete_removesRecord() throws {
        let item = makeVodItem()
        try repo.create(item)
        try repo.delete(id: "vod-1")

        let fetched = try repo.get(id: "vod-1")
        XCTAssertNil(fetched)
    }

    // MARK: - Batch Import

    func testImportVodItems_insertsNewItems() throws {
        let items = [
            makeVodItem(id: "m1", title: "Movie A"),
            makeVodItem(id: "m2", title: "Movie B"),
        ]

        let result = try repo.importVodItems(playlistID: "pl-1", items: items)

        XCTAssertEqual(result.added, 2)
        XCTAssertEqual(result.removed, 0)
        XCTAssertEqual(try repo.getMovies(playlistID: "pl-1").count, 2)
    }

    func testImportVodItems_replacesExistingItems() throws {
        // Import initial set
        let initial = [
            makeVodItem(id: "m1", title: "Old Movie A"),
            makeVodItem(id: "m2", title: "Old Movie B"),
            makeVodItem(id: "m3", title: "Old Movie C"),
        ]
        _ = try repo.importVodItems(playlistID: "pl-1", items: initial)

        // Re-import with different set
        let updated = [
            makeVodItem(id: "m4", title: "New Movie"),
        ]
        let result = try repo.importVodItems(playlistID: "pl-1", items: updated)

        XCTAssertEqual(result.added, 1)
        XCTAssertEqual(result.removed, 3)
        let movies = try repo.getMovies(playlistID: "pl-1")
        XCTAssertEqual(movies.count, 1)
        XCTAssertEqual(movies.first?.title, "New Movie")
    }

    // MARK: - UI Queries

    func testGetMovies_filtersAndOrdersByTitle() throws {
        try repo.create(makeVodItem(id: "m1", title: "Zorro", type: "movie"))
        try repo.create(makeVodItem(id: "m2", title: "Avatar", type: "movie"))
        try repo.create(makeVodItem(id: "s1", title: "Breaking Bad", type: "series"))

        let movies = try repo.getMovies(playlistID: "pl-1")
        XCTAssertEqual(movies.count, 2)
        XCTAssertEqual(movies[0].title, "Avatar")
        XCTAssertEqual(movies[1].title, "Zorro")
    }

    func testGetSeries_filtersAndOrdersByTitle() throws {
        try repo.create(makeVodItem(id: "s1", title: "Yellowstone", type: "series"))
        try repo.create(makeVodItem(id: "s2", title: "Atlanta", type: "series"))
        try repo.create(makeVodItem(id: "m1", title: "Inception", type: "movie"))

        let series = try repo.getSeries(playlistID: "pl-1")
        XCTAssertEqual(series.count, 2)
        XCTAssertEqual(series[0].title, "Atlanta")
        XCTAssertEqual(series[1].title, "Yellowstone")
    }

    func testGetEpisodes_filteredBySeriesID_orderedBySeasonEpisode() throws {
        try repo.create(makeVodItem(id: "e1", title: "S01E01", type: "episode", seriesID: "s1", seasonNum: 1, episodeNum: 1))
        try repo.create(makeVodItem(id: "e2", title: "S02E01", type: "episode", seriesID: "s1", seasonNum: 2, episodeNum: 1))
        try repo.create(makeVodItem(id: "e3", title: "S01E02", type: "episode", seriesID: "s1", seasonNum: 1, episodeNum: 2))
        try repo.create(makeVodItem(id: "e4", title: "Other", type: "episode", seriesID: "s2", seasonNum: 1, episodeNum: 1))

        let episodes = try repo.getEpisodes(seriesID: "s1")
        XCTAssertEqual(episodes.count, 3)
        XCTAssertEqual(episodes[0].title, "S01E01")
        XCTAssertEqual(episodes[1].title, "S01E02")
        XCTAssertEqual(episodes[2].title, "S02E01")
    }

    func testSearchVod_matchesByTitle() throws {
        try repo.create(makeVodItem(id: "m1", title: "The Matrix"))
        try repo.create(makeVodItem(id: "m2", title: "Inception"))
        try repo.create(makeVodItem(id: "m3", title: "The Matrix Reloaded"))

        let results = try repo.searchVod(query: "Matrix", playlistID: "pl-1")
        XCTAssertEqual(results.count, 2)
    }

    func testSearchVod_filtersByType() throws {
        try repo.create(makeVodItem(id: "m1", title: "Matrix", type: "movie"))
        try repo.create(makeVodItem(id: "s1", title: "Matrix Series", type: "series"))

        let results = try repo.searchVod(query: "Matrix", type: "movie")
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.type, "movie")
    }

    func testGetGenres_returnsDistinctSplitValues() throws {
        try repo.create(makeVodItem(id: "m1", title: "Movie A", genre: "Action, Sci-Fi"))
        try repo.create(makeVodItem(id: "m2", title: "Movie B", genre: "Drama"))
        try repo.create(makeVodItem(id: "m3", title: "Movie C", genre: "Action, Drama"))

        let genres = try repo.getGenres(playlistID: "pl-1", type: "movie")
        XCTAssertEqual(genres, ["Action", "Drama", "Sci-Fi"])
    }

    func testGetByIDs_returnsMatchingItems() throws {
        try repo.create(makeVodItem(id: "m1", title: "Movie A"))
        try repo.create(makeVodItem(id: "m2", title: "Movie B"))
        try repo.create(makeVodItem(id: "m3", title: "Movie C"))

        let results = try repo.getByIDs(ids: ["m1", "m3", "m999"])
        XCTAssertEqual(results.count, 2)
        let ids = Set(results.map(\.id))
        XCTAssertTrue(ids.contains("m1"))
        XCTAssertTrue(ids.contains("m3"))
    }

    func testGetByIDs_emptyInput_returnsEmpty() throws {
        try repo.create(makeVodItem(id: "m1", title: "Movie A"))
        let results = try repo.getByIDs(ids: [])
        XCTAssertTrue(results.isEmpty)
    }

    func testCascadeDelete_removesItemsWithPlaylist() throws {
        try repo.create(makeVodItem(id: "m1", title: "Movie"))

        // Delete the playlist — CASCADE should remove VOD items
        try dbManager.dbQueue.write { db in
            _ = try PlaylistRecord.deleteOne(db, key: "pl-1")
        }

        let fetched = try repo.get(id: "m1")
        XCTAssertNil(fetched)
    }
}
