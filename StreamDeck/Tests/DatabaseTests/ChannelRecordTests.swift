import XCTest
import GRDB
@testable import Database

final class ChannelRecordTests: DatabaseTestCase {

    override func setUpWithError() throws {
        try super.setUpWithError()
        try insertPlaylist()
    }

    // MARK: - CRUD

    func testInsertAndFetch() throws {
        let channel = try insertChannel()
        let fetched = try dbManager.dbQueue.read { db in
            try ChannelRecord.fetchOne(db, key: channel.id)
        }
        XCTAssertEqual(fetched, channel)
    }

    func testUpdate_streamURL() throws {
        try insertChannel()
        try dbManager.dbQueue.write { db in
            var record = try XCTUnwrap(ChannelRecord.fetchOne(db, key: "channel-1"))
            record.streamURL = "http://example.com/new-stream"
            try record.update(db)
        }
        let updated = try dbManager.dbQueue.read { db in
            try ChannelRecord.fetchOne(db, key: "channel-1")
        }
        XCTAssertEqual(updated?.streamURL, "http://example.com/new-stream")
    }

    // MARK: - Soft Delete

    func testSoftDelete() throws {
        try insertChannel()
        let now = 1700000000
        try dbManager.dbQueue.write { db in
            var record = try XCTUnwrap(ChannelRecord.fetchOne(db, key: "channel-1"))
            record.isDeleted = true
            record.deletedAt = now
            try record.update(db)
        }
        let fetched = try dbManager.dbQueue.read { db in
            try XCTUnwrap(ChannelRecord.fetchOne(db, key: "channel-1"))
        }
        XCTAssertTrue(fetched.isDeleted)
        XCTAssertEqual(fetched.deletedAt, now)
    }

    func testFetchActive_excludesSoftDeleted() throws {
        try insertChannel(id: "ch-active", name: "Active")
        var deleted = ChannelRecord(id: "ch-deleted", playlistID: "playlist-1", name: "Deleted", streamURL: "http://x.com")
        deleted.isDeleted = true
        deleted.deletedAt = 1700000000
        try dbManager.dbQueue.write { db in try deleted.insert(db) }

        let active = try dbManager.dbQueue.read { db in
            try ChannelRecord
                .filter(Column("is_deleted") == false)
                .fetchAll(db)
        }
        XCTAssertEqual(active.count, 1)
        XCTAssertEqual(active.first?.id, "ch-active")
    }

    // MARK: - Favorites

    func testFavorite() throws {
        var channel = ChannelRecord(id: "ch-fav", playlistID: "playlist-1", name: "Fav", streamURL: "http://x.com", isFavorite: true)
        try dbManager.dbQueue.write { db in try channel.insert(db) }

        let favorites = try dbManager.dbQueue.read { db in
            try ChannelRecord
                .filter(Column("is_favorite") == true && Column("is_deleted") == false)
                .fetchAll(db)
        }
        XCTAssertEqual(favorites.count, 1)
        XCTAssertEqual(favorites.first?.id, "ch-fav")
    }

    // MARK: - Identity Strategy

    func testFetchBySourceChannelID() throws {
        let channel = ChannelRecord(
            id: "ch-1", playlistID: "playlist-1", sourceChannelID: "provider-123",
            name: "CNN", streamURL: "http://x.com"
        )
        try dbManager.dbQueue.write { db in try channel.insert(db) }

        let found = try dbManager.dbQueue.read { db in
            try ChannelRecord
                .filter(Column("playlist_id") == "playlist-1" && Column("source_channel_id") == "provider-123")
                .fetchOne(db)
        }
        XCTAssertEqual(found?.id, "ch-1")
    }

    func testFetchByTvgID() throws {
        let channel = ChannelRecord(
            id: "ch-1", playlistID: "playlist-1",
            name: "BBC", streamURL: "http://x.com", tvgID: "bbc.uk"
        )
        try dbManager.dbQueue.write { db in try channel.insert(db) }

        let found = try dbManager.dbQueue.read { db in
            try ChannelRecord
                .filter(Column("tvg_id") == "bbc.uk")
                .fetchOne(db)
        }
        XCTAssertEqual(found?.id, "ch-1")
    }

    // MARK: - Fetch by Playlist

    func testFetchByPlaylist() throws {
        try insertPlaylist(id: "playlist-2", name: "Other")
        try insertChannel(id: "ch-1", playlistID: "playlist-1", name: "Ch1")
        try insertChannel(id: "ch-2", playlistID: "playlist-2", name: "Ch2")

        let playlist1Channels = try dbManager.dbQueue.read { db in
            try ChannelRecord
                .filter(Column("playlist_id") == "playlist-1")
                .fetchAll(db)
        }
        XCTAssertEqual(playlist1Channels.count, 1)
        XCTAssertEqual(playlist1Channels.first?.name, "Ch1")
    }

    // MARK: - All Fields

    func testAllFieldsPersist() throws {
        let channel = ChannelRecord(
            id: "full-ch",
            playlistID: "playlist-1",
            sourceChannelID: "src-42",
            name: "Full Channel",
            groupName: "Sports",
            streamURL: "http://x.com/stream",
            logoURL: "http://x.com/logo.png",
            epgID: "epg-42",
            tvgID: "tvg-42",
            channelNum: 42,
            isFavorite: true,
            isDeleted: false,
            deletedAt: nil
        )
        try dbManager.dbQueue.write { db in try channel.insert(db) }
        let fetched = try dbManager.dbQueue.read { db in
            try XCTUnwrap(ChannelRecord.fetchOne(db, key: "full-ch"))
        }
        XCTAssertEqual(fetched, channel)
    }
}
