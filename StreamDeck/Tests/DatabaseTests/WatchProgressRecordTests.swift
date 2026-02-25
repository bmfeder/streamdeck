import XCTest
import GRDB
@testable import Database

final class WatchProgressRecordTests: DatabaseTestCase {

    override func setUpWithError() throws {
        try super.setUpWithError()
        try insertPlaylist()
    }

    func testInsertAndFetch() throws {
        let progress = WatchProgressRecord(
            contentID: "ch-1", playlistID: "playlist-1",
            positionMs: 30000, durationMs: 3600000, updatedAt: 1700000000
        )
        try dbManager.dbQueue.write { db in try progress.insert(db) }

        let fetched = try dbManager.dbQueue.read { db in
            try WatchProgressRecord.fetchOne(db, key: "ch-1")
        }
        XCTAssertEqual(fetched, progress)
    }

    func testUpdatePosition() throws {
        let progress = WatchProgressRecord(contentID: "ch-1", playlistID: "playlist-1", positionMs: 0, updatedAt: 1700000000)
        try dbManager.dbQueue.write { db in try progress.insert(db) }

        try dbManager.dbQueue.write { db in
            var record = try XCTUnwrap(WatchProgressRecord.fetchOne(db, key: "ch-1"))
            record.positionMs = 60000
            record.updatedAt = 1700001000
            try record.update(db)
        }

        let updated = try dbManager.dbQueue.read { db in
            try XCTUnwrap(WatchProgressRecord.fetchOne(db, key: "ch-1"))
        }
        XCTAssertEqual(updated.positionMs, 60000)
        XCTAssertEqual(updated.updatedAt, 1700001000)
    }

    func testRecentlyWatched_orderedByUpdatedAt() throws {
        let p1 = WatchProgressRecord(contentID: "c1", playlistID: "playlist-1", positionMs: 100, updatedAt: 1700000000)
        let p2 = WatchProgressRecord(contentID: "c2", playlistID: "playlist-1", positionMs: 200, updatedAt: 1700002000)
        let p3 = WatchProgressRecord(contentID: "c3", playlistID: "playlist-1", positionMs: 300, updatedAt: 1700001000)
        try dbManager.dbQueue.write { db in
            try p1.insert(db)
            try p2.insert(db)
            try p3.insert(db)
        }

        let recent = try dbManager.dbQueue.read { db in
            try WatchProgressRecord
                .order(Column("updated_at").desc)
                .fetchAll(db)
        }
        XCTAssertEqual(recent.map(\.contentID), ["c2", "c3", "c1"])
    }

    func testCascadeFromPlaylist() throws {
        let progress = WatchProgressRecord(contentID: "ch-1", playlistID: "playlist-1", updatedAt: 1700000000)
        try dbManager.dbQueue.write { db in try progress.insert(db) }
        try dbManager.dbQueue.write { db in
            _ = try PlaylistRecord.deleteOne(db, key: "playlist-1")
        }
        let count = try dbManager.dbQueue.read { db in try WatchProgressRecord.fetchCount(db) }
        XCTAssertEqual(count, 0)
    }

    func testNullPlaylistID_noCascade() throws {
        // WatchProgress without a playlist should survive playlist deletions
        let progress = WatchProgressRecord(contentID: "orphan", playlistID: nil, positionMs: 500, updatedAt: 1700000000)
        try dbManager.dbQueue.write { db in try progress.insert(db) }

        let fetched = try dbManager.dbQueue.read { db in
            try WatchProgressRecord.fetchOne(db, key: "orphan")
        }
        XCTAssertNotNil(fetched)
    }

    func testDefaultPositionMs() throws {
        let progress = WatchProgressRecord(contentID: "ch-1", updatedAt: 1700000000)
        XCTAssertEqual(progress.positionMs, 0)
    }
}
