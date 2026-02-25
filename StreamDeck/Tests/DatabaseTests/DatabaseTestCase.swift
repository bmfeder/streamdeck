import XCTest
import GRDB
@testable import Database

/// Base class for database tests. Provides a fresh in-memory database for each test.
class DatabaseTestCase: XCTestCase {
    var dbManager: DatabaseManager!

    override func setUpWithError() throws {
        try super.setUpWithError()
        dbManager = try DatabaseManager()
    }

    override func tearDown() {
        dbManager = nil
        super.tearDown()
    }

    // MARK: - Helpers

    /// Inserts a default playlist and returns it. Many tests need a playlist for FK references.
    @discardableResult
    func insertPlaylist(
        id: String = "playlist-1",
        name: String = "Test Playlist",
        type: String = "m3u",
        url: String = "http://example.com/playlist.m3u"
    ) throws -> PlaylistRecord {
        let record = PlaylistRecord(id: id, name: name, type: type, url: url)
        try dbManager.dbQueue.write { db in
            try record.insert(db)
        }
        return record
    }

    /// Inserts a default channel and returns it.
    @discardableResult
    func insertChannel(
        id: String = "channel-1",
        playlistID: String = "playlist-1",
        name: String = "Test Channel",
        streamURL: String = "http://example.com/stream"
    ) throws -> ChannelRecord {
        let record = ChannelRecord(id: id, playlistID: playlistID, name: name, streamURL: streamURL)
        try dbManager.dbQueue.write { db in
            try record.insert(db)
        }
        return record
    }
}
