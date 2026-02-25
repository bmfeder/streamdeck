import XCTest
import GRDB
import Database
@testable import Repositories

final class WatchProgressRepositoryTests: XCTestCase {
    var dbManager: DatabaseManager!
    var repo: WatchProgressRepository!

    override func setUpWithError() throws {
        try super.setUpWithError()
        dbManager = try DatabaseManager()
        repo = WatchProgressRepository(dbManager: dbManager)

        // Insert a default playlist for FK references
        let playlist = PlaylistRecord(id: "pl-1", name: "Test", type: "m3u", url: "http://example.com/pl.m3u")
        try dbManager.dbQueue.write { db in try playlist.insert(db) }
    }

    override func tearDown() {
        repo = nil
        dbManager = nil
        super.tearDown()
    }

    // MARK: - CRUD

    func testUpsert_insertsNew() throws {
        let record = WatchProgressRecord(
            contentID: "m1", playlistID: "pl-1", positionMs: 60_000,
            durationMs: 7_200_000, updatedAt: 1_700_000_000
        )
        try repo.upsert(record)

        let fetched = try repo.get(contentID: "m1")
        XCTAssertEqual(fetched, record)
    }

    func testUpsert_updatesExisting() throws {
        let record = WatchProgressRecord(
            contentID: "m1", playlistID: "pl-1", positionMs: 60_000,
            durationMs: 7_200_000, updatedAt: 1_700_000_000
        )
        try repo.upsert(record)

        var updated = record
        updated.positionMs = 120_000
        updated.updatedAt = 1_700_001_000
        try repo.upsert(updated)

        let fetched = try repo.get(contentID: "m1")
        XCTAssertEqual(fetched?.positionMs, 120_000)
        XCTAssertEqual(fetched?.updatedAt, 1_700_001_000)
    }

    func testGet_returnsNilForMissing() throws {
        let fetched = try repo.get(contentID: "nonexistent")
        XCTAssertNil(fetched)
    }

    func testDelete_removesRecord() throws {
        let record = WatchProgressRecord(contentID: "m1", positionMs: 1000, updatedAt: 1_700_000_000)
        try repo.upsert(record)
        try repo.delete(contentID: "m1")

        let fetched = try repo.get(contentID: "m1")
        XCTAssertNil(fetched)
    }

    // MARK: - Recently Watched

    func testGetRecentlyWatched_orderedByUpdatedAt() throws {
        try repo.upsert(WatchProgressRecord(contentID: "c1", positionMs: 100, updatedAt: 1_700_000_000))
        try repo.upsert(WatchProgressRecord(contentID: "c2", positionMs: 200, updatedAt: 1_700_002_000))
        try repo.upsert(WatchProgressRecord(contentID: "c3", positionMs: 300, updatedAt: 1_700_001_000))

        let recent = try repo.getRecentlyWatched()
        XCTAssertEqual(recent.map(\.contentID), ["c2", "c3", "c1"])
    }

    func testGetRecentlyWatched_respectsLimit() throws {
        for i in 0..<5 {
            try repo.upsert(WatchProgressRecord(contentID: "c\(i)", positionMs: 100, updatedAt: 1_700_000_000 + i))
        }

        let recent = try repo.getRecentlyWatched(limit: 3)
        XCTAssertEqual(recent.count, 3)
        XCTAssertEqual(recent.first?.contentID, "c4") // most recent
    }

    // MARK: - Unfinished

    func testGetUnfinished_excludesFinished() throws {
        // Finished: position near end (within 30s)
        try repo.upsert(WatchProgressRecord(contentID: "finished", positionMs: 7_180_000, durationMs: 7_200_000, updatedAt: 1_700_000_000))
        // Unfinished: position in middle
        try repo.upsert(WatchProgressRecord(contentID: "unfinished", positionMs: 3_600_000, durationMs: 7_200_000, updatedAt: 1_700_000_000))

        let unfinished = try repo.getUnfinished()
        XCTAssertEqual(unfinished.count, 1)
        XCTAssertEqual(unfinished.first?.contentID, "unfinished")
    }

    func testGetUnfinished_excludesZeroPosition() throws {
        try repo.upsert(WatchProgressRecord(contentID: "zero", positionMs: 0, durationMs: 7_200_000, updatedAt: 1_700_000_000))
        try repo.upsert(WatchProgressRecord(contentID: "started", positionMs: 60_000, durationMs: 7_200_000, updatedAt: 1_700_000_000))

        let unfinished = try repo.getUnfinished()
        XCTAssertEqual(unfinished.count, 1)
        XCTAssertEqual(unfinished.first?.contentID, "started")
    }

    // MARK: - Batch

    func testGetBatch_returnsDictionary() throws {
        try repo.upsert(WatchProgressRecord(contentID: "m1", positionMs: 1000, durationMs: 5000, updatedAt: 1_700_000_000))
        try repo.upsert(WatchProgressRecord(contentID: "m2", positionMs: 2000, durationMs: 5000, updatedAt: 1_700_000_000))
        try repo.upsert(WatchProgressRecord(contentID: "m3", positionMs: 3000, durationMs: 5000, updatedAt: 1_700_000_000))

        let batch = try repo.getBatch(contentIDs: ["m1", "m3", "nonexistent"])
        XCTAssertEqual(batch.count, 2)
        XCTAssertEqual(batch["m1"]?.positionMs, 1000)
        XCTAssertEqual(batch["m3"]?.positionMs, 3000)
        XCTAssertNil(batch["nonexistent"])
    }

    // MARK: - Purge

    func testPurgeOlderThan_removesOldRecords() throws {
        try repo.upsert(WatchProgressRecord(contentID: "old", positionMs: 100, updatedAt: 1_699_000_000))
        try repo.upsert(WatchProgressRecord(contentID: "new", positionMs: 200, updatedAt: 1_700_000_000))

        let purged = try repo.purgeOlderThan(1_699_500_000)
        XCTAssertEqual(purged, 1)

        XCTAssertNil(try repo.get(contentID: "old"))
        XCTAssertNotNil(try repo.get(contentID: "new"))
    }

    // MARK: - Cascade

    func testCascadeDelete_removesProgressWithPlaylist() throws {
        try repo.upsert(WatchProgressRecord(contentID: "m1", playlistID: "pl-1", positionMs: 100, updatedAt: 1_700_000_000))

        try dbManager.dbQueue.write { db in
            _ = try PlaylistRecord.deleteOne(db, key: "pl-1")
        }

        XCTAssertNil(try repo.get(contentID: "m1"))
    }
}
