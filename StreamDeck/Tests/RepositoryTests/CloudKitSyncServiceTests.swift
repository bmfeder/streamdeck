import CloudKit
import Database
import XCTest
@testable import Repositories

// MARK: - Mock CloudKit Database

final class MockCloudKitDatabase: CloudKitDatabaseProtocol, @unchecked Sendable {
    var records: [String: CKRecord] = [:]
    var saveCallCount = 0
    var lastSavedRecord: CKRecord?

    func save(_ record: CKRecord) async throws -> CKRecord {
        saveCallCount += 1
        lastSavedRecord = record
        records[record.recordID.recordName] = record
        return record
    }

    func record(for recordID: CKRecord.ID) async throws -> CKRecord {
        guard let record = records[recordID.recordName] else {
            throw CKError(.unknownItem)
        }
        return record
    }

    func fetchRecords(matching query: CKQuery) async throws -> [CKRecord] {
        records.values.filter { $0.recordType == query.recordType }
    }
}

// MARK: - Tests

final class CloudKitSyncServiceTests: XCTestCase {
    var dbManager: DatabaseManager!
    var mockDB: MockCloudKitDatabase!
    var service: CloudKitSyncService!

    override func setUpWithError() throws {
        try super.setUpWithError()
        dbManager = try DatabaseManager()
        mockDB = MockCloudKitDatabase()
        service = CloudKitSyncService(
            database: mockDB,
            dbManager: dbManager,
            deviceID: "test-device-1"
        )

        // Insert a default playlist for FK references
        let playlist = PlaylistRecord(id: "pl-1", name: "Test", type: "m3u", url: "http://example.com/pl.m3u")
        try dbManager.dbQueue.write { db in try playlist.insert(db) }
    }

    override func tearDown() {
        service = nil
        mockDB = nil
        dbManager = nil
        super.tearDown()
    }

    // MARK: - Push: Playlists

    func testPushPlaylist_createsCorrectCKRecord() async throws {
        let playlist = PlaylistRecord(
            id: "pl-1", name: "My IPTV", type: "m3u", url: "http://example.com/pl.m3u",
            username: "user1", epgURL: "http://example.com/epg.xml",
            refreshHrs: 12, isActive: true, sortOrder: 2
        )

        try await service.pushPlaylist(playlist)

        let saved = try XCTUnwrap(mockDB.lastSavedRecord)
        XCTAssertEqual(saved.recordType, "SDPlaylist")
        XCTAssertEqual(saved.recordID.recordName, "pl-1")
        XCTAssertEqual(saved["name"] as? String, "My IPTV")
        XCTAssertEqual(saved["type"] as? String, "m3u")
        XCTAssertEqual(saved["url"] as? String, "http://example.com/pl.m3u")
        XCTAssertEqual(saved["username"] as? String, "user1")
        XCTAssertEqual(saved["epgURL"] as? String, "http://example.com/epg.xml")
        XCTAssertEqual((saved["refreshHrs"] as? NSNumber)?.intValue, 12)
        XCTAssertEqual((saved["isActive"] as? NSNumber)?.intValue, 1)
        XCTAssertEqual((saved["sortOrder"] as? NSNumber)?.intValue, 2)
        XCTAssertEqual((saved["isDeleted"] as? NSNumber)?.intValue, 0)
        XCTAssertEqual(saved["deviceID"] as? String, "test-device-1")
    }

    func testPushPlaylist_excludesPasswordRef() async throws {
        let playlist = PlaylistRecord(
            id: "pl-1", name: "Test", type: "xtream", url: "http://example.com",
            passwordRef: "keychain-ref-123"
        )

        try await service.pushPlaylist(playlist)

        let saved = try XCTUnwrap(mockDB.lastSavedRecord)
        XCTAssertNil(saved["passwordRef"])
        XCTAssertNil(saved["password_ref"])
    }

    func testPushPlaylistDeletion_setsSoftDeleteFlag() async throws {
        // First push a playlist
        let ckRecord = CKRecord(recordType: "SDPlaylist", recordID: CKRecord.ID(recordName: "pl-del"))
        ckRecord["name"] = "To Delete"
        ckRecord["isDeleted"] = 0 as NSNumber
        mockDB.records["pl-del"] = ckRecord

        try await service.pushPlaylistDeletion("pl-del")

        let updated = try XCTUnwrap(mockDB.records["pl-del"])
        XCTAssertEqual((updated["isDeleted"] as? NSNumber)?.intValue, 1)
        XCTAssertEqual(updated["deviceID"] as? String, "test-device-1")
    }

    // MARK: - Push: Favorites

    func testPushFavorite_mapsFieldsCorrectly() async throws {
        try await service.pushFavorite(channelID: "ch-1", playlistID: "pl-1", isFavorite: true)

        let saved = try XCTUnwrap(mockDB.lastSavedRecord)
        XCTAssertEqual(saved.recordType, "SDFavorite")
        XCTAssertEqual(saved.recordID.recordName, "ch-1")
        XCTAssertEqual(saved["channelID"] as? String, "ch-1")
        XCTAssertEqual(saved["playlistID"] as? String, "pl-1")
        XCTAssertEqual((saved["isFavorite"] as? NSNumber)?.intValue, 1)
    }

    // MARK: - Push: Watch Progress

    func testPushWatchProgress_mapsFieldsCorrectly() async throws {
        let record = WatchProgressRecord(
            contentID: "ch-1", playlistID: "pl-1",
            positionMs: 60000, durationMs: 120000, updatedAt: 1_700_000_000
        )

        try await service.pushWatchProgress(record)

        let saved = try XCTUnwrap(mockDB.lastSavedRecord)
        XCTAssertEqual(saved.recordType, "SDWatchProgress")
        XCTAssertEqual(saved.recordID.recordName, "ch-1")
        XCTAssertEqual((saved["positionMs"] as? NSNumber)?.intValue, 60000)
        XCTAssertEqual((saved["durationMs"] as? NSNumber)?.intValue, 120000)
        XCTAssertEqual((saved["updatedAt"] as? NSNumber)?.intValue, 1_700_000_000)
    }

    // MARK: - Push: Preferences

    func testPushPreferences_mapsFieldsCorrectly() async throws {
        let prefs = SyncablePreferences(
            preferredEngine: "vlcKit",
            resumePlaybackEnabled: false,
            bufferTimeoutSeconds: 20,
            updatedAt: 1_700_000_000
        )

        try await service.pushPreferences(prefs)

        let saved = try XCTUnwrap(mockDB.lastSavedRecord)
        XCTAssertEqual(saved.recordType, "SDUserPreference")
        XCTAssertEqual(saved.recordID.recordName, "userPreferences")
        XCTAssertEqual(saved["preferredEngine"] as? String, "vlcKit")
        XCTAssertEqual((saved["resumePlaybackEnabled"] as? NSNumber)?.intValue, 0)
        XCTAssertEqual((saved["bufferTimeoutSeconds"] as? NSNumber)?.intValue, 20)
    }

    // MARK: - Pull: Playlists

    func testPullPlaylists_createsNewLocalRecord() async throws {
        let ckRecord = CKRecord(recordType: "SDPlaylist", recordID: CKRecord.ID(recordName: "pl-remote"))
        ckRecord["name"] = "Remote Playlist"
        ckRecord["type"] = "xtream"
        ckRecord["url"] = "http://remote.com/pl"
        ckRecord["refreshHrs"] = 6 as NSNumber
        ckRecord["isActive"] = 1 as NSNumber
        ckRecord["sortOrder"] = 1 as NSNumber
        ckRecord["isDeleted"] = 0 as NSNumber
        mockDB.records["pl-remote"] = ckRecord

        let count = try await service.pullPlaylists()

        XCTAssertEqual(count, 1)
        let repo = PlaylistRepository(dbManager: dbManager)
        let local = try XCTUnwrap(repo.get(id: "pl-remote"))
        XCTAssertEqual(local.name, "Remote Playlist")
        XCTAssertEqual(local.type, "xtream")
        XCTAssertEqual(local.refreshHrs, 6)
    }

    func testPullPlaylists_updatesExistingRecord() async throws {
        let ckRecord = CKRecord(recordType: "SDPlaylist", recordID: CKRecord.ID(recordName: "pl-1"))
        ckRecord["name"] = "Updated Name"
        ckRecord["type"] = "m3u"
        ckRecord["url"] = "http://new-url.com/pl.m3u"
        ckRecord["refreshHrs"] = 48 as NSNumber
        ckRecord["isActive"] = 1 as NSNumber
        ckRecord["sortOrder"] = 5 as NSNumber
        ckRecord["isDeleted"] = 0 as NSNumber
        mockDB.records["pl-1"] = ckRecord

        let count = try await service.pullPlaylists()

        XCTAssertEqual(count, 1)
        let repo = PlaylistRepository(dbManager: dbManager)
        let local = try XCTUnwrap(repo.get(id: "pl-1"))
        XCTAssertEqual(local.name, "Updated Name")
        XCTAssertEqual(local.url, "http://new-url.com/pl.m3u")
        XCTAssertEqual(local.refreshHrs, 48)
    }

    func testPullPlaylists_deletedRemotely_deletesLocally() async throws {
        let ckRecord = CKRecord(recordType: "SDPlaylist", recordID: CKRecord.ID(recordName: "pl-1"))
        ckRecord["isDeleted"] = 1 as NSNumber
        mockDB.records["pl-1"] = ckRecord

        let count = try await service.pullPlaylists()

        XCTAssertEqual(count, 1)
        let repo = PlaylistRepository(dbManager: dbManager)
        XCTAssertNil(try repo.get(id: "pl-1"))
    }

    // MARK: - Pull: Watch Progress

    func testPullWatchProgress_newerRemote_overwrites() async throws {
        // Insert local progress with updatedAt = 100
        let localProgress = WatchProgressRecord(
            contentID: "ch-1", positionMs: 5000, durationMs: 60000, updatedAt: 100
        )
        let repo = WatchProgressRepository(dbManager: dbManager)
        try repo.upsert(localProgress)

        // Remote has updatedAt = 200 (newer)
        let ckRecord = CKRecord(recordType: "SDWatchProgress", recordID: CKRecord.ID(recordName: "ch-1"))
        ckRecord["positionMs"] = 30000 as NSNumber
        ckRecord["durationMs"] = 60000 as NSNumber
        ckRecord["updatedAt"] = 200 as NSNumber
        mockDB.records["ch-1"] = ckRecord

        let count = try await service.pullWatchProgress()

        XCTAssertEqual(count, 1)
        let updated = try XCTUnwrap(repo.get(contentID: "ch-1"))
        XCTAssertEqual(updated.positionMs, 30000)
        XCTAssertEqual(updated.updatedAt, 200)
    }

    func testPullWatchProgress_newerLocal_noOverwrite() async throws {
        // Insert local progress with updatedAt = 300
        let localProgress = WatchProgressRecord(
            contentID: "ch-1", positionMs: 50000, durationMs: 60000, updatedAt: 300
        )
        let repo = WatchProgressRepository(dbManager: dbManager)
        try repo.upsert(localProgress)

        // Remote has updatedAt = 200 (older)
        let ckRecord = CKRecord(recordType: "SDWatchProgress", recordID: CKRecord.ID(recordName: "ch-1"))
        ckRecord["positionMs"] = 10000 as NSNumber
        ckRecord["durationMs"] = 60000 as NSNumber
        ckRecord["updatedAt"] = 200 as NSNumber
        mockDB.records["ch-1"] = ckRecord

        let count = try await service.pullWatchProgress()

        XCTAssertEqual(count, 0)
        let unchanged = try XCTUnwrap(repo.get(contentID: "ch-1"))
        XCTAssertEqual(unchanged.positionMs, 50000)
        XCTAssertEqual(unchanged.updatedAt, 300)
    }

    // MARK: - Pull: Favorites

    func testPullFavorites_updatesLocalChannel() async throws {
        // Insert a channel that is not favorited
        let channel = ChannelRecord(
            id: "ch-fav", playlistID: "pl-1", name: "ESPN",
            streamURL: "http://example.com/stream", isFavorite: false
        )
        let channelRepo = ChannelRepository(dbManager: dbManager)
        try channelRepo.create(channel)

        // Remote says it's favorited
        let ckRecord = CKRecord(recordType: "SDFavorite", recordID: CKRecord.ID(recordName: "ch-fav"))
        ckRecord["channelID"] = "ch-fav"
        ckRecord["playlistID"] = "pl-1"
        ckRecord["isFavorite"] = 1 as NSNumber
        mockDB.records["ch-fav"] = ckRecord

        let count = try await service.pullFavorites()

        XCTAssertEqual(count, 1)
        let updated = try XCTUnwrap(channelRepo.get(id: "ch-fav"))
        XCTAssertTrue(updated.isFavorite)
    }
}
