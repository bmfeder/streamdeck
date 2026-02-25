import XCTest
import GRDB
import Database
@testable import Repositories

final class ChannelRepositoryTests: XCTestCase {
    var dbManager: DatabaseManager!
    var repo: ChannelRepository!

    override func setUpWithError() throws {
        try super.setUpWithError()
        dbManager = try DatabaseManager()
        repo = ChannelRepository(dbManager: dbManager)

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

    private func makeChannel(
        id: String = "ch-1",
        playlistID: String = "pl-1",
        sourceChannelID: String? = nil,
        name: String = "Test Channel",
        groupName: String? = nil,
        streamURL: String = "http://example.com/stream",
        logoURL: String? = nil,
        tvgID: String? = nil,
        channelNum: Int? = nil,
        isFavorite: Bool = false,
        isDeleted: Bool = false,
        deletedAt: Int? = nil
    ) -> ChannelRecord {
        ChannelRecord(
            id: id,
            playlistID: playlistID,
            sourceChannelID: sourceChannelID,
            name: name,
            groupName: groupName,
            streamURL: streamURL,
            logoURL: logoURL,
            tvgID: tvgID,
            channelNum: channelNum,
            isFavorite: isFavorite,
            isDeleted: isDeleted,
            deletedAt: deletedAt
        )
    }

    private func insertSecondPlaylist() throws {
        let playlist = PlaylistRecord(id: "pl-2", name: "Other", type: "xtream", url: "http://example.com/pl2")
        try dbManager.dbQueue.write { db in try playlist.insert(db) }
    }

    // MARK: - CRUD

    func testCreate_andGet() throws {
        let channel = makeChannel()
        try repo.create(channel)

        let fetched = try repo.get(id: "ch-1")
        XCTAssertEqual(fetched, channel)
    }

    func testUpdate() throws {
        try repo.create(makeChannel())

        var updated = try XCTUnwrap(repo.get(id: "ch-1"))
        updated.streamURL = "http://example.com/new-stream"
        try repo.update(updated)

        let fetched = try XCTUnwrap(repo.get(id: "ch-1"))
        XCTAssertEqual(fetched.streamURL, "http://example.com/new-stream")
    }

    func testDelete_hardDelete() throws {
        try repo.create(makeChannel())
        try repo.delete(id: "ch-1")

        XCTAssertNil(try repo.get(id: "ch-1"))
    }

    // MARK: - Identity Matching

    func testFindBySourceID_tier1() throws {
        try repo.create(makeChannel(id: "ch-1", sourceChannelID: "src-42"))

        let found = try repo.findBySourceID(playlistID: "pl-1", sourceChannelID: "src-42")
        XCTAssertEqual(found?.id, "ch-1")
    }

    func testFindBySourceID_wrongPlaylist_returnsNil() throws {
        try insertSecondPlaylist()
        try repo.create(makeChannel(id: "ch-1", sourceChannelID: "src-42"))

        let found = try repo.findBySourceID(playlistID: "pl-2", sourceChannelID: "src-42")
        XCTAssertNil(found)
    }

    func testFindByTvgID_tier2() throws {
        try repo.create(makeChannel(id: "ch-1", tvgID: "bbc.uk"))

        let found = try repo.findByTvgID(playlistID: "pl-1", tvgID: "bbc.uk")
        XCTAssertEqual(found?.id, "ch-1")
    }

    func testFindByNameAndGroup_tier3_withGroup() throws {
        try repo.create(makeChannel(id: "ch-1", name: "CNN", groupName: "News"))

        let found = try repo.findByNameAndGroup(playlistID: "pl-1", name: "CNN", groupName: "News")
        XCTAssertEqual(found?.id, "ch-1")
    }

    func testFindByNameAndGroup_tier3_nilGroup() throws {
        try repo.create(makeChannel(id: "ch-1", name: "CNN"))

        let found = try repo.findByNameAndGroup(playlistID: "pl-1", name: "CNN", groupName: nil)
        XCTAssertEqual(found?.id, "ch-1")
    }

    func testFindByNameAndGroup_wrongGroup_returnsNil() throws {
        try repo.create(makeChannel(id: "ch-1", name: "CNN", groupName: "News"))

        let found = try repo.findByNameAndGroup(playlistID: "pl-1", name: "CNN", groupName: "Sports")
        XCTAssertNil(found)
    }

    // MARK: - Batch Import

    func testImportChannels_insertNew() throws {
        let channels = [
            makeChannel(id: "ch-1", name: "CNN", streamURL: "http://x.com/cnn"),
            makeChannel(id: "ch-2", name: "BBC", streamURL: "http://x.com/bbc"),
        ]

        let result = try repo.importChannels(playlistID: "pl-1", channels: channels, now: 1700000000)

        XCTAssertEqual(result.added, 2)
        XCTAssertEqual(result.updated, 0)
        XCTAssertEqual(result.softDeleted, 0)
        XCTAssertEqual(result.unchanged, 0)

        let active = try repo.getActive(playlistID: "pl-1")
        XCTAssertEqual(active.count, 2)
    }

    func testImportChannels_updateExisting_bySourceID() throws {
        // Pre-existing channel
        try repo.create(makeChannel(
            id: "existing-id",
            sourceChannelID: "src-1",
            name: "Old Name",
            streamURL: "http://old.com/stream"
        ))

        // Import with same sourceChannelID but updated fields
        let incoming = [makeChannel(
            id: "new-id",
            sourceChannelID: "src-1",
            name: "New Name",
            streamURL: "http://new.com/stream"
        )]

        let result = try repo.importChannels(playlistID: "pl-1", channels: incoming, now: 1700000000)

        XCTAssertEqual(result.added, 0)
        XCTAssertEqual(result.updated, 1)
        XCTAssertEqual(result.softDeleted, 0)

        // Should keep the original canonical ID
        let fetched = try XCTUnwrap(repo.get(id: "existing-id"))
        XCTAssertEqual(fetched.name, "New Name")
        XCTAssertEqual(fetched.streamURL, "http://new.com/stream")
    }

    func testImportChannels_updateExisting_byTvgID() throws {
        try repo.create(makeChannel(
            id: "existing-id",
            name: "ESPN",
            streamURL: "http://old.com/espn",
            tvgID: "espn.us"
        ))

        let incoming = [makeChannel(
            id: "new-id",
            name: "ESPN HD",
            streamURL: "http://new.com/espn",
            tvgID: "espn.us"
        )]

        let result = try repo.importChannels(playlistID: "pl-1", channels: incoming, now: 1700000000)

        XCTAssertEqual(result.updated, 1)
        let fetched = try XCTUnwrap(repo.get(id: "existing-id"))
        XCTAssertEqual(fetched.name, "ESPN HD")
    }

    func testImportChannels_updateExisting_byNameAndGroup() throws {
        try repo.create(makeChannel(
            id: "existing-id",
            name: "Fox News",
            groupName: "News",
            streamURL: "http://old.com/fox"
        ))

        let incoming = [makeChannel(
            id: "new-id",
            name: "Fox News",
            groupName: "News",
            streamURL: "http://new.com/fox"
        )]

        let result = try repo.importChannels(playlistID: "pl-1", channels: incoming, now: 1700000000)

        XCTAssertEqual(result.updated, 1)
        let fetched = try XCTUnwrap(repo.get(id: "existing-id"))
        XCTAssertEqual(fetched.streamURL, "http://new.com/fox")
    }

    func testImportChannels_unchanged() throws {
        let channel = makeChannel(id: "ch-1", name: "CNN", streamURL: "http://x.com/cnn")
        try repo.create(channel)

        let incoming = [makeChannel(id: "new-id", name: "CNN", streamURL: "http://x.com/cnn")]

        let result = try repo.importChannels(playlistID: "pl-1", channels: incoming, now: 1700000000)

        XCTAssertEqual(result.unchanged, 1)
        XCTAssertEqual(result.updated, 0)
    }

    func testImportChannels_softDeletesMissing() throws {
        try repo.create(makeChannel(id: "ch-1", name: "CNN", streamURL: "http://x.com/cnn"))
        try repo.create(makeChannel(id: "ch-2", name: "BBC", streamURL: "http://x.com/bbc"))

        // Only import CNN — BBC should be soft-deleted
        let incoming = [makeChannel(id: "new-id", name: "CNN", streamURL: "http://x.com/cnn")]

        let result = try repo.importChannels(playlistID: "pl-1", channels: incoming, now: 1700000000)

        XCTAssertEqual(result.softDeleted, 1)

        let bbc = try XCTUnwrap(repo.get(id: "ch-2"))
        XCTAssertTrue(bbc.isDeleted)
        XCTAssertEqual(bbc.deletedAt, 1700000000)
    }

    func testImportChannels_reactivatesSoftDeleted() throws {
        // Insert a soft-deleted channel
        try repo.create(makeChannel(
            id: "ch-1",
            sourceChannelID: "src-1",
            name: "CNN",
            streamURL: "http://x.com/cnn",
            isDeleted: true,
            deletedAt: 1699000000
        ))

        // Re-import the same channel
        let incoming = [makeChannel(
            id: "new-id",
            sourceChannelID: "src-1",
            name: "CNN",
            streamURL: "http://x.com/cnn"
        )]

        let result = try repo.importChannels(playlistID: "pl-1", channels: incoming, now: 1700000000)

        XCTAssertEqual(result.updated, 1) // re-activation counts as update
        let fetched = try XCTUnwrap(repo.get(id: "ch-1"))
        XCTAssertFalse(fetched.isDeleted)
        XCTAssertNil(fetched.deletedAt)
    }

    // MARK: - Soft Delete

    func testSoftDeleteMissing() throws {
        try repo.create(makeChannel(id: "ch-1", name: "CNN"))
        try repo.create(makeChannel(id: "ch-2", name: "BBC"))

        let count = try repo.softDeleteMissing(playlistID: "pl-1", activeIDs: ["ch-1"], now: 1700000000)

        XCTAssertEqual(count, 1)
        let bbc = try XCTUnwrap(repo.get(id: "ch-2"))
        XCTAssertTrue(bbc.isDeleted)
        XCTAssertEqual(bbc.deletedAt, 1700000000)
    }

    func testPurgeDeleted() throws {
        try repo.create(makeChannel(id: "ch-old", isDeleted: true, deletedAt: 1699000000))
        try repo.create(makeChannel(id: "ch-recent", name: "Recent", isDeleted: true, deletedAt: 1700000000))
        try repo.create(makeChannel(id: "ch-active", name: "Active"))

        // Purge channels deleted before 1699500000
        let purged = try repo.purgeDeleted(olderThan: 1699500000)

        XCTAssertEqual(purged, 1)
        XCTAssertNil(try repo.get(id: "ch-old"))
        XCTAssertNotNil(try repo.get(id: "ch-recent"))
        XCTAssertNotNil(try repo.get(id: "ch-active"))
    }

    // MARK: - UI Queries

    func testGetActive_excludesDeleted() throws {
        try repo.create(makeChannel(id: "ch-1", name: "Active"))
        try repo.create(makeChannel(id: "ch-2", name: "Deleted", isDeleted: true, deletedAt: 1700000000))

        let active = try repo.getActive(playlistID: "pl-1")
        XCTAssertEqual(active.count, 1)
        XCTAssertEqual(active.first?.id, "ch-1")
    }

    func testGetActive_orderedByName() throws {
        try repo.create(makeChannel(id: "ch-z", name: "Zebra"))
        try repo.create(makeChannel(id: "ch-a", name: "Alpha"))

        let active = try repo.getActive(playlistID: "pl-1")
        XCTAssertEqual(active.map(\.name), ["Alpha", "Zebra"])
    }

    func testGetActiveGrouped() throws {
        try repo.create(makeChannel(id: "ch-1", name: "CNN", groupName: "News"))
        try repo.create(makeChannel(id: "ch-2", name: "ESPN", groupName: "Sports"))
        try repo.create(makeChannel(id: "ch-3", name: "BBC", groupName: "News"))
        try repo.create(makeChannel(id: "ch-4", name: "No Group"))

        let grouped = try repo.getActiveGrouped(playlistID: "pl-1")
        XCTAssertEqual(grouped["News"]?.count, 2)
        XCTAssertEqual(grouped["Sports"]?.count, 1)
        XCTAssertEqual(grouped[""]?.count, 1) // nil group → empty string key
    }

    func testGetFavorites_acrossPlaylists() throws {
        try insertSecondPlaylist()
        try repo.create(makeChannel(id: "ch-1", name: "CNN", isFavorite: true))
        try repo.create(makeChannel(id: "ch-2", playlistID: "pl-2", name: "BBC", isFavorite: true))
        try repo.create(makeChannel(id: "ch-3", name: "Not Fav"))

        let favorites = try repo.getFavorites()
        XCTAssertEqual(favorites.count, 2)
        XCTAssertEqual(Set(favorites.map(\.id)), ["ch-1", "ch-2"])
    }

    func testGetFavorites_excludesDeleted() throws {
        try repo.create(makeChannel(id: "ch-1", name: "Fav Active", isFavorite: true))
        try repo.create(makeChannel(id: "ch-2", name: "Fav Deleted", isFavorite: true, isDeleted: true, deletedAt: 1700000000))

        let favorites = try repo.getFavorites()
        XCTAssertEqual(favorites.count, 1)
        XCTAssertEqual(favorites.first?.id, "ch-1")
    }

    func testSearch_byName() throws {
        try repo.create(makeChannel(id: "ch-1", name: "CNN International"))
        try repo.create(makeChannel(id: "ch-2", name: "BBC World News"))
        try repo.create(makeChannel(id: "ch-3", name: "ESPN"))

        let results = try repo.search(query: "CNN")
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.id, "ch-1")
    }

    func testSearch_caseInsensitive() throws {
        try repo.create(makeChannel(id: "ch-1", name: "CNN"))

        let results = try repo.search(query: "cnn")
        XCTAssertEqual(results.count, 1)
    }

    func testSearch_scopedToPlaylist() throws {
        try insertSecondPlaylist()
        try repo.create(makeChannel(id: "ch-1", name: "CNN"))
        try repo.create(makeChannel(id: "ch-2", playlistID: "pl-2", name: "CNN HD"))

        let results = try repo.search(query: "CNN", playlistID: "pl-1")
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.id, "ch-1")
    }

    func testSearch_excludesDeleted() throws {
        try repo.create(makeChannel(id: "ch-1", name: "CNN", isDeleted: true, deletedAt: 1700000000))

        let results = try repo.search(query: "CNN")
        XCTAssertEqual(results.count, 0)
    }

    func testGetByNumber() throws {
        try repo.create(makeChannel(id: "ch-1", name: "CNN", channelNum: 42))

        let found = try repo.getByNumber(playlistID: "pl-1", number: 42)
        XCTAssertEqual(found?.id, "ch-1")
    }

    func testGetByNumber_excludesDeleted() throws {
        try repo.create(makeChannel(id: "ch-1", name: "CNN", channelNum: 42, isDeleted: true, deletedAt: 1700000000))

        let found = try repo.getByNumber(playlistID: "pl-1", number: 42)
        XCTAssertNil(found)
    }

    // MARK: - Favorites

    func testToggleFavorite() throws {
        try repo.create(makeChannel(id: "ch-1"))

        try repo.toggleFavorite(id: "ch-1")
        let toggled = try XCTUnwrap(repo.get(id: "ch-1"))
        XCTAssertTrue(toggled.isFavorite)

        try repo.toggleFavorite(id: "ch-1")
        let unToggled = try XCTUnwrap(repo.get(id: "ch-1"))
        XCTAssertFalse(unToggled.isFavorite)
    }
}
