import XCTest
import GRDB
@testable import Database

final class VodItemRecordTests: DatabaseTestCase {

    override func setUpWithError() throws {
        try super.setUpWithError()
        try insertPlaylist()
    }

    func testInsertAndFetch() throws {
        let vod = VodItemRecord(id: "vod-1", playlistID: "playlist-1", title: "Inception", type: "movie")
        try dbManager.dbQueue.write { db in try vod.insert(db) }

        let fetched = try dbManager.dbQueue.read { db in
            try VodItemRecord.fetchOne(db, key: "vod-1")
        }
        XCTAssertEqual(fetched, vod)
    }

    func testFetchByType() throws {
        let movie = VodItemRecord(id: "v1", playlistID: "playlist-1", title: "Movie", type: "movie")
        let series = VodItemRecord(id: "v2", playlistID: "playlist-1", title: "Series", type: "series")
        let episode = VodItemRecord(id: "v3", playlistID: "playlist-1", title: "Episode", type: "episode")
        try dbManager.dbQueue.write { db in
            try movie.insert(db)
            try series.insert(db)
            try episode.insert(db)
        }

        let movies = try dbManager.dbQueue.read { db in
            try VodItemRecord
                .filter(Column("type") == "movie")
                .fetchAll(db)
        }
        XCTAssertEqual(movies.count, 1)
        XCTAssertEqual(movies.first?.title, "Movie")
    }

    func testCascadeFromPlaylist() throws {
        let vod = VodItemRecord(id: "vod-1", playlistID: "playlist-1", title: "Movie", type: "movie")
        try dbManager.dbQueue.write { db in try vod.insert(db) }
        try dbManager.dbQueue.write { db in
            _ = try PlaylistRecord.deleteOne(db, key: "playlist-1")
        }
        let count = try dbManager.dbQueue.read { db in try VodItemRecord.fetchCount(db) }
        XCTAssertEqual(count, 0)
    }

    func testAllFieldsPersist() throws {
        let vod = VodItemRecord(
            id: "full-vod",
            playlistID: "playlist-1",
            title: "Full Movie",
            type: "movie",
            streamURL: "http://x.com/movie.mp4",
            posterURL: "http://x.com/poster.jpg",
            backdropURL: "http://x.com/backdrop.jpg",
            description: "A great movie",
            year: 2024,
            rating: 8.5,
            genre: "Action,Sci-Fi",
            seriesID: nil,
            seasonNum: nil,
            episodeNum: nil,
            durationS: 7200
        )
        try dbManager.dbQueue.write { db in try vod.insert(db) }
        let fetched = try dbManager.dbQueue.read { db in
            try XCTUnwrap(VodItemRecord.fetchOne(db, key: "full-vod"))
        }
        XCTAssertEqual(fetched, vod)
    }

    func testEpisodeFields() throws {
        let episode = VodItemRecord(
            id: "ep-1",
            playlistID: "playlist-1",
            title: "Pilot",
            type: "episode",
            seriesID: "series-1",
            seasonNum: 1,
            episodeNum: 1
        )
        try dbManager.dbQueue.write { db in try episode.insert(db) }
        let fetched = try dbManager.dbQueue.read { db in
            try XCTUnwrap(VodItemRecord.fetchOne(db, key: "ep-1"))
        }
        XCTAssertEqual(fetched.seriesID, "series-1")
        XCTAssertEqual(fetched.seasonNum, 1)
        XCTAssertEqual(fetched.episodeNum, 1)
    }
}
