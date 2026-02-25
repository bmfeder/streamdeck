import XCTest
import Foundation
import Database
import XtreamClient
@testable import Repositories

// MARK: - Mock HTTP Client

/// Mock HTTP client for testing import service. Duplicated from XtreamClientTests
/// since test targets can't share code.
final class MockHTTPClient: HTTPClient, @unchecked Sendable {
    private var responses: [(matcher: String, data: Data, statusCode: Int)] = []
    private(set) var requestsMade: [URLRequest] = []
    var errorToThrow: Error?

    func enqueue(for urlContaining: String, json: String, statusCode: Int = 200) {
        responses.append((urlContaining, Data(json.utf8), statusCode))
    }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requestsMade.append(request)
        if let error = errorToThrow {
            throw error
        }
        let urlString = request.url?.absoluteString ?? ""
        for (index, entry) in responses.enumerated() {
            if urlString.contains(entry.matcher) {
                responses.remove(at: index)
                let httpResponse = HTTPURLResponse(
                    url: request.url ?? URL(string: "http://mock.test")!,
                    statusCode: entry.statusCode,
                    httpVersion: nil,
                    headerFields: nil
                )!
                return (entry.data, httpResponse)
            }
        }
        let httpResponse = HTTPURLResponse(
            url: request.url ?? URL(string: "http://mock.test")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!
        return (Data("{}".utf8), httpResponse)
    }
}

// MARK: - Test Fixtures

private enum Fixtures {
    static let m3uPlaylist = """
    #EXTM3U x-tvg-url="http://epg.example.com/guide.xml"
    #EXTINF:-1 tvg-id="cnn.us" tvg-logo="http://logo.com/cnn.png" group-title="News",CNN International
    http://stream.example.com/cnn
    #EXTINF:-1 tvg-id="espn.us" tvg-logo="http://logo.com/espn.png" group-title="Sports",ESPN HD
    http://stream.example.com/espn
    #EXTINF:-1 group-title="News",BBC World
    http://stream.example.com/bbc
    """

    static let m3uEmpty = """
    #EXTM3U
    """

    static let m3uWithErrors = """
    #EXTM3U
    #EXTINF:-1,Good Channel
    http://stream.example.com/good
    #EXTINF:-1,Bad Channel
    not a valid url
    """

    static let xtreamAuthSuccess = """
    {
        "user_info": {
            "username": "testuser",
            "password": "testpass",
            "status": "Active",
            "auth": 1,
            "exp_date": "1893456000",
            "is_trial": "0",
            "active_cons": "1",
            "max_connections": "2",
            "created_at": "1704067200",
            "allowed_output_formats": ["m3u8", "ts"]
        },
        "server_info": {
            "url": "provider.example.com",
            "port": "8080",
            "https_port": "8443",
            "server_protocol": "http",
            "rtmp_port": "8088",
            "timezone": "UTC",
            "timestamp_now": "1709251200",
            "time_now": "2024-03-01 12:00:00"
        }
    }
    """

    static let xtreamAuthFailed = """
    {
        "user_info": {
            "username": "baduser",
            "password": "badpass",
            "status": "Disabled",
            "auth": 0,
            "exp_date": null,
            "is_trial": "0",
            "active_cons": "0",
            "max_connections": "0",
            "allowed_output_formats": []
        },
        "server_info": {
            "url": "",
            "port": "0",
            "https_port": "0",
            "server_protocol": "http",
            "rtmp_port": "0",
            "timezone": "UTC"
        }
    }
    """

    static let xtreamAuthExpired = """
    {
        "user_info": {
            "username": "testuser",
            "password": "testpass",
            "status": "Expired",
            "auth": 1,
            "exp_date": "1609459200",
            "is_trial": "0",
            "active_cons": "0",
            "max_connections": "1",
            "created_at": "1577836800",
            "allowed_output_formats": ["m3u8"]
        },
        "server_info": {
            "url": "provider.example.com",
            "port": "8080",
            "https_port": "8443",
            "server_protocol": "http",
            "rtmp_port": "8088",
            "timezone": "UTC",
            "timestamp_now": "1709251200",
            "time_now": "2024-03-01 12:00:00"
        }
    }
    """

    static let xtreamCategories = """
    [
        {"category_id": "1", "category_name": "Sports", "parent_id": 0},
        {"category_id": "2", "category_name": "News", "parent_id": 0}
    ]
    """

    static let xtreamStreams = """
    [
        {
            "num": 1,
            "name": "ESPN HD",
            "stream_type": "live",
            "stream_id": 1001,
            "stream_icon": "https://cdn.example.com/espn.png",
            "epg_channel_id": "ESPN.us",
            "added": "1704067200",
            "category_id": "1",
            "custom_sid": "",
            "tv_archive": 0,
            "direct_source": "",
            "tv_archive_duration": 0
        },
        {
            "num": 2,
            "name": "CNN International",
            "stream_type": "live",
            "stream_id": 1002,
            "stream_icon": "",
            "epg_channel_id": "CNN.us",
            "added": "1704067200",
            "category_id": "2",
            "custom_sid": "",
            "tv_archive": 1,
            "direct_source": "",
            "tv_archive_duration": "72"
        }
    ]
    """
}

// MARK: - Thread-safe Counter

private final class AtomicCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var _value: Int = 0

    func next() -> Int {
        lock.lock()
        defer { lock.unlock() }
        _value += 1
        return _value
    }
}

// MARK: - Tests

final class PlaylistImportServiceTests: XCTestCase {
    var dbManager: DatabaseManager!
    var playlistRepo: PlaylistRepository!
    var channelRepo: ChannelRepository!
    var mockHTTP: MockHTTPClient!

    override func setUpWithError() throws {
        try super.setUpWithError()
        dbManager = try DatabaseManager()
        playlistRepo = PlaylistRepository(dbManager: dbManager)
        channelRepo = ChannelRepository(dbManager: dbManager)
        mockHTTP = MockHTTPClient()
    }

    override func tearDown() {
        dbManager = nil
        playlistRepo = nil
        channelRepo = nil
        mockHTTP = nil
        super.tearDown()
    }

    private func makeService() -> PlaylistImportService {
        let counter = AtomicCounter()
        return PlaylistImportService(
            playlistRepo: playlistRepo,
            channelRepo: channelRepo,
            httpClient: mockHTTP,
            uuidGenerator: {
                "uuid-\(counter.next())"
            }
        )
    }

    // MARK: - M3U Import (from Data)

    func testImportM3UData_validPlaylist_createsPlaylistAndChannels() throws {
        let service = makeService()
        let data = Data(Fixtures.m3uPlaylist.utf8)

        let result = try service.importM3UData(data, name: "Test Playlist", sourceURL: "http://example.com/pl.m3u")

        XCTAssertEqual(result.playlist.name, "Test Playlist")
        XCTAssertEqual(result.playlist.type, "m3u")
        XCTAssertEqual(result.playlist.url, "http://example.com/pl.m3u")
        XCTAssertEqual(result.importResult.added, 3)
        XCTAssertEqual(result.totalChannels, 3)

        // Verify playlist persisted
        let playlist = try playlistRepo.get(id: result.playlist.id)
        XCTAssertNotNil(playlist)

        // Verify channels persisted
        let channels = try channelRepo.getActive(playlistID: result.playlist.id)
        XCTAssertEqual(channels.count, 3)
    }

    func testImportM3UData_emptyPlaylist_throws() throws {
        let service = makeService()
        let data = Data(Fixtures.m3uEmpty.utf8)

        XCTAssertThrowsError(
            try service.importM3UData(data, name: "Empty", sourceURL: "http://example.com/empty.m3u")
        ) { error in
            XCTAssertEqual(error as? PlaylistImportError, .emptyPlaylist)
        }
    }

    func testImportM3UData_autoDetectsEPGFromMetadata() throws {
        let service = makeService()
        let data = Data(Fixtures.m3uPlaylist.utf8)

        let result = try service.importM3UData(data, name: "Test", sourceURL: "http://example.com/pl.m3u")

        XCTAssertEqual(result.playlist.epgURL, "http://epg.example.com/guide.xml")
    }

    func testImportM3UData_providedEPGURL_overridesAutoDetect() throws {
        let service = makeService()
        let data = Data(Fixtures.m3uPlaylist.utf8)
        let epgURL = URL(string: "http://custom-epg.com/guide.xml")

        let result = try service.importM3UData(
            data, name: "Test", sourceURL: "http://example.com/pl.m3u", epgURL: epgURL
        )

        XCTAssertEqual(result.playlist.epgURL, "http://custom-epg.com/guide.xml")
    }

    func testImportM3UData_reportsParseErrors() throws {
        let service = makeService()
        let data = Data(Fixtures.m3uWithErrors.utf8)

        let result = try service.importM3UData(data, name: "Test", sourceURL: "http://example.com/pl.m3u")

        XCTAssertEqual(result.importResult.added, 1) // only the good channel
        XCTAssertFalse(result.parseErrors.isEmpty)
    }

    func testImportM3UData_setsInitialSyncTimestamp() throws {
        let service = makeService()
        let data = Data(Fixtures.m3uPlaylist.utf8)

        let result = try service.importM3UData(data, name: "Test", sourceURL: "http://example.com/pl.m3u")

        XCTAssertNotNil(result.playlist.lastSync)
    }

    func testImportM3UData_channelFieldsMappedCorrectly() throws {
        let service = makeService()
        let data = Data(Fixtures.m3uPlaylist.utf8)

        let result = try service.importM3UData(data, name: "Test", sourceURL: "http://example.com/pl.m3u")
        let channels = try channelRepo.getActive(playlistID: result.playlist.id)

        // Find CNN channel
        let cnn = channels.first { $0.name == "CNN International" }
        XCTAssertNotNil(cnn)
        XCTAssertEqual(cnn?.sourceChannelID, "cnn.us")
        XCTAssertEqual(cnn?.tvgID, "cnn.us")
        XCTAssertEqual(cnn?.groupName, "News")
        XCTAssertEqual(cnn?.logoURL, "http://logo.com/cnn.png")
        XCTAssertEqual(cnn?.streamURL, "http://stream.example.com/cnn")
    }

    // MARK: - M3U Import (from URL)

    func testImportM3U_validURL_downloadsAndImports() async throws {
        let service = makeService()
        mockHTTP.enqueue(for: "example.com/pl.m3u", json: Fixtures.m3uPlaylist)

        let result = try await service.importM3U(url: URL(string: "http://example.com/pl.m3u")!, name: "Remote")

        XCTAssertEqual(result.importResult.added, 3)
        XCTAssertEqual(result.playlist.name, "Remote")
    }

    func testImportM3U_httpError_throwsDownloadFailed() async {
        let service = makeService()
        mockHTTP.enqueue(for: "example.com", json: "Not Found", statusCode: 404)

        do {
            _ = try await service.importM3U(url: URL(string: "http://example.com/pl.m3u")!, name: "Test")
            XCTFail("Expected error")
        } catch {
            XCTAssertEqual(error as? PlaylistImportError, .downloadFailed("HTTP 404"))
        }
    }

    func testImportM3U_networkError_throwsNetworkError() async {
        let service = makeService()
        mockHTTP.errorToThrow = URLError(.notConnectedToInternet)

        do {
            _ = try await service.importM3U(url: URL(string: "http://example.com/pl.m3u")!, name: "Test")
            XCTFail("Expected error")
        } catch {
            guard case .networkError = error as? PlaylistImportError else {
                XCTFail("Expected networkError, got \(error)")
                return
            }
        }
    }

    // MARK: - Xtream Import

    func testImportXtream_valid_createsPlaylistAndChannels() async throws {
        let service = makeService()
        mockHTTP.enqueue(for: "player_api.php", json: Fixtures.xtreamAuthSuccess)
        mockHTTP.enqueue(for: "get_live_categories", json: Fixtures.xtreamCategories)
        mockHTTP.enqueue(for: "get_live_streams", json: Fixtures.xtreamStreams)

        let result = try await service.importXtream(
            serverURL: URL(string: "http://provider.example.com:8080")!,
            username: "testuser",
            password: "testpass",
            name: "My Xtream"
        )

        XCTAssertEqual(result.playlist.name, "My Xtream")
        XCTAssertEqual(result.playlist.type, "xtream")
        XCTAssertEqual(result.playlist.username, "testuser")
        XCTAssertNotNil(result.playlist.passwordRef)
        XCTAssertEqual(result.importResult.added, 2)
        XCTAssertTrue(result.parseErrors.isEmpty)
    }

    func testImportXtream_authFailed_throws() async {
        let service = makeService()
        mockHTTP.enqueue(for: "player_api.php", json: Fixtures.xtreamAuthFailed)

        do {
            _ = try await service.importXtream(
                serverURL: URL(string: "http://provider.example.com:8080")!,
                username: "bad", password: "bad", name: "Test"
            )
            XCTFail("Expected error")
        } catch {
            XCTAssertEqual(error as? PlaylistImportError, .authenticationFailed)
        }
    }

    func testImportXtream_accountExpired_throws() async {
        let service = makeService()
        mockHTTP.enqueue(for: "player_api.php", json: Fixtures.xtreamAuthExpired)

        do {
            _ = try await service.importXtream(
                serverURL: URL(string: "http://provider.example.com:8080")!,
                username: "test", password: "test", name: "Test"
            )
            XCTFail("Expected error")
        } catch {
            XCTAssertEqual(error as? PlaylistImportError, .accountExpired)
        }
    }

    func testImportXtream_storesPasswordInKeychain() async throws {
        let service = makeService()
        mockHTTP.enqueue(for: "player_api.php", json: Fixtures.xtreamAuthSuccess)
        mockHTTP.enqueue(for: "get_live_categories", json: Fixtures.xtreamCategories)
        mockHTTP.enqueue(for: "get_live_streams", json: Fixtures.xtreamStreams)

        let result = try await service.importXtream(
            serverURL: URL(string: "http://provider.example.com:8080")!,
            username: "testuser", password: "supersecret", name: "Test"
        )

        let keychainKey = result.playlist.passwordRef
        XCTAssertNotNil(keychainKey)
        let storedPassword = KeychainHelper.load(key: keychainKey!)
        XCTAssertEqual(storedPassword, "supersecret")

        // Clean up
        KeychainHelper.delete(key: keychainKey!)
    }

    func testImportXtream_resolvesCategoryNames() async throws {
        let service = makeService()
        mockHTTP.enqueue(for: "player_api.php", json: Fixtures.xtreamAuthSuccess)
        mockHTTP.enqueue(for: "get_live_categories", json: Fixtures.xtreamCategories)
        mockHTTP.enqueue(for: "get_live_streams", json: Fixtures.xtreamStreams)

        let result = try await service.importXtream(
            serverURL: URL(string: "http://provider.example.com:8080")!,
            username: "testuser", password: "testpass", name: "Test"
        )

        let channels = try channelRepo.getActive(playlistID: result.playlist.id)
        let espn = channels.first { $0.name == "ESPN HD" }
        let cnn = channels.first { $0.name == "CNN International" }

        XCTAssertEqual(espn?.groupName, "Sports")
        XCTAssertEqual(cnn?.groupName, "News")

        // Clean up Keychain
        if let key = result.playlist.passwordRef {
            KeychainHelper.delete(key: key)
        }
    }

    func testImportXtream_buildsStreamURLsCorrectly() async throws {
        let service = makeService()
        mockHTTP.enqueue(for: "player_api.php", json: Fixtures.xtreamAuthSuccess)
        mockHTTP.enqueue(for: "get_live_categories", json: Fixtures.xtreamCategories)
        mockHTTP.enqueue(for: "get_live_streams", json: Fixtures.xtreamStreams)

        let result = try await service.importXtream(
            serverURL: URL(string: "http://provider.example.com:8080")!,
            username: "testuser", password: "testpass", name: "Test"
        )

        let channels = try channelRepo.getActive(playlistID: result.playlist.id)
        let espn = channels.first { $0.name == "ESPN HD" }

        // Stream URL format: {server}/live/{user}/{pass}/{streamId}.m3u8
        XCTAssertTrue(espn?.streamURL.contains("/live/testuser/testpass/1001.m3u8") ?? false)

        // Clean up Keychain
        if let key = result.playlist.passwordRef {
            KeychainHelper.delete(key: key)
        }
    }
}
