import XCTest
import GRDB
@testable import Database

final class PlaylistRecordTests: DatabaseTestCase {

    func testInsertAndFetch() throws {
        let playlist = try insertPlaylist()
        let fetched = try dbManager.dbQueue.read { db in
            try PlaylistRecord.fetchOne(db, key: playlist.id)
        }
        XCTAssertEqual(fetched, playlist)
    }

    func testDefaults() throws {
        let playlist = try insertPlaylist()
        XCTAssertEqual(playlist.refreshHrs, 24)
        XCTAssertEqual(playlist.isActive, true)
        XCTAssertEqual(playlist.sortOrder, 0)
        XCTAssertNil(playlist.lastSync)
        XCTAssertNil(playlist.epgURL)
    }

    func testUpdate() throws {
        try insertPlaylist()
        try dbManager.dbQueue.write { db in
            var record = try XCTUnwrap(PlaylistRecord.fetchOne(db, key: "playlist-1"))
            record.name = "Updated Name"
            record.lastSync = 1700000000
            try record.update(db)
        }
        let updated = try dbManager.dbQueue.read { db in
            try PlaylistRecord.fetchOne(db, key: "playlist-1")
        }
        XCTAssertEqual(updated?.name, "Updated Name")
        XCTAssertEqual(updated?.lastSync, 1700000000)
    }

    func testDelete() throws {
        try insertPlaylist()
        try dbManager.dbQueue.write { db in
            _ = try PlaylistRecord.deleteOne(db, key: "playlist-1")
        }
        let count = try dbManager.dbQueue.read { db in
            try PlaylistRecord.fetchCount(db)
        }
        XCTAssertEqual(count, 0)
    }

    func testCascadeDelete_removesChannels() throws {
        try insertPlaylist()
        try insertChannel()
        try dbManager.dbQueue.write { db in
            _ = try PlaylistRecord.deleteOne(db, key: "playlist-1")
        }
        let channelCount = try dbManager.dbQueue.read { db in
            try ChannelRecord.fetchCount(db)
        }
        XCTAssertEqual(channelCount, 0)
    }

    func testCascadeDelete_removesVodItems() throws {
        try insertPlaylist()
        let vod = VodItemRecord(id: "vod-1", playlistID: "playlist-1", title: "Movie", type: "movie")
        try dbManager.dbQueue.write { db in
            try vod.insert(db)
        }
        try dbManager.dbQueue.write { db in
            _ = try PlaylistRecord.deleteOne(db, key: "playlist-1")
        }
        let vodCount = try dbManager.dbQueue.read { db in
            try VodItemRecord.fetchCount(db)
        }
        XCTAssertEqual(vodCount, 0)
    }

    func testCascadeDelete_removesWatchProgress() throws {
        try insertPlaylist()
        let progress = WatchProgressRecord(contentID: "ch-1", playlistID: "playlist-1", positionMs: 5000, updatedAt: 1700000000)
        try dbManager.dbQueue.write { db in
            try progress.insert(db)
        }
        try dbManager.dbQueue.write { db in
            _ = try PlaylistRecord.deleteOne(db, key: "playlist-1")
        }
        let progressCount = try dbManager.dbQueue.read { db in
            try WatchProgressRecord.fetchCount(db)
        }
        XCTAssertEqual(progressCount, 0)
    }

    func testFetchAll_orderedBySortOrder() throws {
        let p1 = PlaylistRecord(id: "p1", name: "Second", type: "m3u", url: "http://a.com", sortOrder: 2)
        let p2 = PlaylistRecord(id: "p2", name: "First", type: "m3u", url: "http://b.com", sortOrder: 1)
        try dbManager.dbQueue.write { db in
            try p1.insert(db)
            try p2.insert(db)
        }
        let all = try dbManager.dbQueue.read { db in
            try PlaylistRecord.order(Column("sort_order")).fetchAll(db)
        }
        XCTAssertEqual(all.map(\.id), ["p2", "p1"])
    }

    func testAllFieldsPersist() throws {
        let playlist = PlaylistRecord(
            id: "full",
            name: "Full Playlist",
            type: "xtream",
            url: "http://provider.com/api",
            username: "user",
            passwordRef: "keychain-ref-123",
            epgURL: "http://provider.com/epg.xml",
            refreshHrs: 12,
            lastSync: 1700000000,
            lastEpgSync: 1700001000,
            lastSyncEtag: "abc123",
            lastSyncHash: "hash456",
            isActive: false,
            sortOrder: 5
        )
        try dbManager.dbQueue.write { db in try playlist.insert(db) }
        let fetched = try dbManager.dbQueue.read { db in
            try XCTUnwrap(PlaylistRecord.fetchOne(db, key: "full"))
        }
        XCTAssertEqual(fetched, playlist)
    }
}
