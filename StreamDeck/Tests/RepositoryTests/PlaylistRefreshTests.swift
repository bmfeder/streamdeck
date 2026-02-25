import XCTest
import Foundation
import Database
import XtreamClient
@testable import Repositories

final class PlaylistRefreshTests: XCTestCase {
    var dbManager: DatabaseManager!
    var playlistRepo: PlaylistRepository!
    var channelRepo: ChannelRepository!
    var vodRepo: VodRepository!
    var httpClient: RefreshMockHTTPClient!

    override func setUpWithError() throws {
        try super.setUpWithError()
        dbManager = try DatabaseManager()
        playlistRepo = PlaylistRepository(dbManager: dbManager)
        channelRepo = ChannelRepository(dbManager: dbManager)
        vodRepo = VodRepository(dbManager: dbManager)
        httpClient = RefreshMockHTTPClient()
    }

    override func tearDown() {
        httpClient = nil
        vodRepo = nil
        channelRepo = nil
        playlistRepo = nil
        dbManager = nil
        super.tearDown()
    }

    // MARK: - Helpers

    private func makeService() -> PlaylistImportService {
        PlaylistImportService(
            playlistRepo: playlistRepo,
            channelRepo: channelRepo,
            vodRepo: vodRepo,
            httpClient: httpClient
        )
    }

    // MARK: - Not Found

    func testRefreshPlaylist_notFound_throws() async {
        let service = makeService()
        do {
            _ = try await service.refreshPlaylist(id: "nonexistent")
            XCTFail("Expected playlistNotFound error")
        } catch let error as PlaylistImportError {
            XCTAssertEqual(error, .playlistNotFound)
        } catch {
            XCTFail("Wrong error type: \(error)")
        }
    }

    // MARK: - M3U Refresh

    func testRefreshM3U_reImportsChannels() async throws {
        let service = makeService()

        // Initial import
        httpClient.nextResponse = (Data(Fixtures.m3uTwoChannels.utf8), 200)
        let initial = try await service.importM3U(
            url: URL(string: "http://example.com/playlist.m3u")!,
            name: "Test M3U"
        )
        let playlistID = initial.playlist.id
        XCTAssertEqual(initial.importResult.added, 2)

        // Refresh with updated playlist (3 channels)
        httpClient.nextResponse = (Data(Fixtures.m3uThreeChannels.utf8), 200)
        let refreshResult = try await service.refreshPlaylist(id: playlistID)

        // Should have imported new channels
        XCTAssertGreaterThan(refreshResult.importResult.added + refreshResult.importResult.updated + refreshResult.importResult.unchanged, 0)
        XCTAssertEqual(refreshResult.playlist.id, playlistID)
    }

    func testRefreshM3U_updatesLastSync() async throws {
        let service = makeService()

        httpClient.nextResponse = (Data(Fixtures.m3uTwoChannels.utf8), 200)
        let initial = try await service.importM3U(
            url: URL(string: "http://example.com/playlist.m3u")!,
            name: "Test M3U"
        )
        let playlistID = initial.playlist.id
        let initialSync = initial.playlist.lastSync

        // Small delay to ensure timestamp differs
        httpClient.nextResponse = (Data(Fixtures.m3uTwoChannels.utf8), 200)
        let refreshResult = try await service.refreshPlaylist(id: playlistID)

        // lastSync should be updated
        XCTAssertNotNil(refreshResult.playlist.lastSync)
        XCTAssertGreaterThanOrEqual(refreshResult.playlist.lastSync!, initialSync ?? 0)

        // Verify in database
        let dbPlaylist = try playlistRepo.get(id: playlistID)
        XCTAssertNotNil(dbPlaylist?.lastSync)
    }

    func testRefreshM3U_preservesFavorites() async throws {
        let service = makeService()

        // Import initial playlist
        httpClient.nextResponse = (Data(Fixtures.m3uTwoChannels.utf8), 200)
        let initial = try await service.importM3U(
            url: URL(string: "http://example.com/playlist.m3u")!,
            name: "Test M3U"
        )
        let playlistID = initial.playlist.id

        // Mark a channel as favorite
        let channels = try channelRepo.getActive(playlistID: playlistID)
        XCTAssertFalse(channels.isEmpty)
        if var channel = channels.first {
            channel.isFavorite = true
            try channelRepo.update(channel)
        }

        // Verify favorite is set
        let beforeRefresh = try channelRepo.getActive(playlistID: playlistID)
        XCTAssertTrue(beforeRefresh.contains { $0.isFavorite })

        // Refresh with same playlist
        httpClient.nextResponse = (Data(Fixtures.m3uTwoChannels.utf8), 200)
        _ = try await service.refreshPlaylist(id: playlistID)

        // Favorites should be preserved (importChannels uses identity matching)
        let afterRefresh = try channelRepo.getActive(playlistID: playlistID)
        XCTAssertTrue(afterRefresh.contains { $0.isFavorite })
    }

    func testRefreshM3U_downloadFails_throws() async throws {
        let service = makeService()

        httpClient.nextResponse = (Data(Fixtures.m3uTwoChannels.utf8), 200)
        let initial = try await service.importM3U(
            url: URL(string: "http://example.com/playlist.m3u")!,
            name: "Test M3U"
        )

        // Simulate download failure
        httpClient.nextResponse = (Data(), 500)
        do {
            _ = try await service.refreshPlaylist(id: initial.playlist.id)
            XCTFail("Expected downloadFailed error")
        } catch let error as PlaylistImportError {
            if case .downloadFailed = error {
                // Expected
            } else {
                XCTFail("Wrong error case: \(error)")
            }
        }
    }

    func testRefreshUnknownType_throws() async throws {
        // Create a playlist with unknown type directly in DB
        let playlist = PlaylistRecord(
            id: "pl-unknown", name: "Unknown", type: "unknown",
            url: "http://example.com"
        )
        try playlistRepo.create(playlist)

        let service = makeService()
        do {
            _ = try await service.refreshPlaylist(id: "pl-unknown")
            XCTFail("Expected playlistNotFound error")
        } catch let error as PlaylistImportError {
            XCTAssertEqual(error, .playlistNotFound)
        }
    }
}

// MARK: - Mock HTTP Client

final class RefreshMockHTTPClient: HTTPClient, @unchecked Sendable {
    var nextResponse: (Data, Int) = (Data(), 200)

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let response = HTTPURLResponse(
            url: request.url ?? URL(string: "http://mock.test")!,
            statusCode: nextResponse.1,
            httpVersion: nil,
            headerFields: nil
        )!
        return (nextResponse.0, response)
    }
}

// MARK: - Fixtures

private enum Fixtures {
    static let m3uTwoChannels = """
    #EXTM3U
    #EXTINF:-1 tvg-id="cnn.us" group-title="News",CNN
    http://stream.example.com/cnn
    #EXTINF:-1 tvg-id="espn.us" group-title="Sports",ESPN
    http://stream.example.com/espn
    """

    static let m3uThreeChannels = """
    #EXTM3U
    #EXTINF:-1 tvg-id="cnn.us" group-title="News",CNN
    http://stream.example.com/cnn
    #EXTINF:-1 tvg-id="espn.us" group-title="Sports",ESPN
    http://stream.example.com/espn
    #EXTINF:-1 tvg-id="bbc.uk" group-title="News",BBC World
    http://stream.example.com/bbc
    """
}
