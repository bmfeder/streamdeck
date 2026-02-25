import XCTest
import Database
@testable import Repositories

final class PlaylistRepositoryTests: XCTestCase {
    var dbManager: DatabaseManager!
    var repo: PlaylistRepository!

    override func setUpWithError() throws {
        try super.setUpWithError()
        dbManager = try DatabaseManager()
        repo = PlaylistRepository(dbManager: dbManager)
    }

    override func tearDown() {
        repo = nil
        dbManager = nil
        super.tearDown()
    }

    // MARK: - Helpers

    private func makePlaylist(
        id: String = "pl-1",
        name: String = "Test Playlist",
        type: String = "m3u",
        url: String = "http://example.com/playlist.m3u",
        sortOrder: Int = 0
    ) -> PlaylistRecord {
        PlaylistRecord(id: id, name: name, type: type, url: url, sortOrder: sortOrder)
    }

    // MARK: - CRUD

    func testCreate_andGet() throws {
        let playlist = makePlaylist()
        try repo.create(playlist)

        let fetched = try repo.get(id: "pl-1")
        XCTAssertEqual(fetched, playlist)
    }

    func testGet_nonExistent_returnsNil() throws {
        let fetched = try repo.get(id: "nonexistent")
        XCTAssertNil(fetched)
    }

    func testGetAll_orderedBySortOrder() throws {
        try repo.create(makePlaylist(id: "pl-c", name: "C", sortOrder: 2))
        try repo.create(makePlaylist(id: "pl-a", name: "A", sortOrder: 0))
        try repo.create(makePlaylist(id: "pl-b", name: "B", sortOrder: 1))

        let all = try repo.getAll()
        XCTAssertEqual(all.map(\.id), ["pl-a", "pl-b", "pl-c"])
    }

    func testUpdate() throws {
        var playlist = makePlaylist()
        try repo.create(playlist)

        playlist.name = "Updated Name"
        playlist.refreshHrs = 12
        try repo.update(playlist)

        let fetched = try XCTUnwrap(repo.get(id: "pl-1"))
        XCTAssertEqual(fetched.name, "Updated Name")
        XCTAssertEqual(fetched.refreshHrs, 12)
    }

    func testDelete_cascadesChannels() throws {
        try repo.create(makePlaylist())

        // Insert a channel linked to the playlist
        let channel = ChannelRecord(id: "ch-1", playlistID: "pl-1", name: "Test", streamURL: "http://x.com")
        try dbManager.dbQueue.write { db in try channel.insert(db) }

        try repo.delete(id: "pl-1")

        XCTAssertNil(try repo.get(id: "pl-1"))

        // Channel should be cascade-deleted
        let channelFetched = try dbManager.dbQueue.read { db in
            try ChannelRecord.fetchOne(db, key: "ch-1")
        }
        XCTAssertNil(channelFetched)
    }

    // MARK: - Sync Tracking

    func testUpdateSyncTimestamp() throws {
        try repo.create(makePlaylist())

        try repo.updateSyncTimestamp("pl-1", timestamp: 1700000000, etag: "abc123", hash: "sha256-xyz")

        let fetched = try XCTUnwrap(repo.get(id: "pl-1"))
        XCTAssertEqual(fetched.lastSync, 1700000000)
        XCTAssertEqual(fetched.lastSyncEtag, "abc123")
        XCTAssertEqual(fetched.lastSyncHash, "sha256-xyz")
    }

    func testUpdateSyncTimestamp_partialUpdate() throws {
        try repo.create(makePlaylist())
        try repo.updateSyncTimestamp("pl-1", timestamp: 1700000000, etag: "old-etag")

        // Update timestamp only, without new etag/hash
        try repo.updateSyncTimestamp("pl-1", timestamp: 1700001000)

        let fetched = try XCTUnwrap(repo.get(id: "pl-1"))
        XCTAssertEqual(fetched.lastSync, 1700001000)
        XCTAssertEqual(fetched.lastSyncEtag, "old-etag") // preserved
    }

    func testNeedsRefresh_neverSynced_returnsTrue() throws {
        try repo.create(makePlaylist())

        let needs = try repo.needsRefresh("pl-1")
        XCTAssertTrue(needs)
    }

    func testNeedsRefresh_recentSync_returnsFalse() throws {
        var playlist = makePlaylist()
        playlist.refreshHrs = 24
        try repo.create(playlist)

        let now = 1700000000
        try repo.updateSyncTimestamp("pl-1", timestamp: now)

        // Check 1 hour later — should not need refresh (24hr interval)
        let needs = try repo.needsRefresh("pl-1", now: now + 3600)
        XCTAssertFalse(needs)
    }

    func testNeedsRefresh_expiredSync_returnsTrue() throws {
        var playlist = makePlaylist()
        playlist.refreshHrs = 24
        try repo.create(playlist)

        let syncTime = 1700000000
        try repo.updateSyncTimestamp("pl-1", timestamp: syncTime)

        // Check 25 hours later — should need refresh
        let needs = try repo.needsRefresh("pl-1", now: syncTime + 25 * 3600)
        XCTAssertTrue(needs)
    }

    func testNeedsRefresh_nonExistentPlaylist_returnsFalse() throws {
        let needs = try repo.needsRefresh("nonexistent")
        XCTAssertFalse(needs)
    }
}
