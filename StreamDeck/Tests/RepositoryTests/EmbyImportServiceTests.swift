import XCTest
import Database
import EmbyClient
@testable import XtreamClient
@testable import Repositories

final class EmbyImportServiceTests: XCTestCase {

    private var dbManager: DatabaseManager!
    private var service: PlaylistImportService!
    private var mockHTTP: EmbyImportMockHTTPClient!

    override func setUp() {
        super.setUp()
        dbManager = try! DatabaseManager()
        mockHTTP = EmbyImportMockHTTPClient()
        service = PlaylistImportService(
            playlistRepo: PlaylistRepository(dbManager: dbManager),
            channelRepo: ChannelRepository(dbManager: dbManager),
            vodRepo: VodRepository(dbManager: dbManager),
            httpClient: mockHTTP,
            uuidGenerator: { UUID().uuidString }
        )
    }

    override func tearDown() {
        dbManager = nil
        service = nil
        mockHTTP = nil
        super.tearDown()
    }

    private let serverURL = URL(string: "http://emby.local:8096")!

    // MARK: - Tests

    func testImportEmby_valid_createsPlaylistAndVodItems() async throws {
        mockHTTP.enqueue(for: "AuthenticateByName", json: EmbyImportFixtures.authResponse)
        mockHTTP.enqueue(for: "Views", json: EmbyImportFixtures.librariesResponse)
        mockHTTP.enqueue(for: "Items", json: EmbyImportFixtures.moviesResponse)

        let result = try await service.importEmby(
            serverURL: serverURL, username: "user", password: "pass", name: "My Emby"
        )

        XCTAssertEqual(result.playlist.type, "emby")
        XCTAssertEqual(result.playlist.name, "My Emby")
        XCTAssertEqual(result.playlist.url, serverURL.absoluteString)
        XCTAssertEqual(result.playlist.username, "user")
        XCTAssertNotNil(result.playlist.passwordRef)
        XCTAssertEqual(result.importResult.added, 0) // No channels for Emby
        XCTAssertNotNil(result.vodImportResult)
        XCTAssertEqual(result.vodImportResult?.added, 2) // 2 movies
    }

    func testImportEmby_authFailed_throwsAuthFailed() async {
        mockHTTP.enqueue(for: "AuthenticateByName", json: "{}", statusCode: 401)

        do {
            _ = try await service.importEmby(
                serverURL: serverURL, username: "bad", password: "bad", name: "Test"
            )
            XCTFail("Expected authenticationFailed")
        } catch let error as PlaylistImportError {
            XCTAssertEqual(error, .authenticationFailed)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testImportEmby_emptyLibraries_createsPlaylistNoItems() async throws {
        mockHTTP.enqueue(for: "AuthenticateByName", json: EmbyImportFixtures.authResponse)
        mockHTTP.enqueue(for: "Views", json: """
        {"Items": []}
        """)

        let result = try await service.importEmby(
            serverURL: serverURL, username: "user", password: "pass", name: "Empty"
        )

        XCTAssertEqual(result.playlist.type, "emby")
        XCTAssertNil(result.vodImportResult)
    }

    func testImportEmby_filtersNonVideoLibraries() async throws {
        mockHTTP.enqueue(for: "AuthenticateByName", json: EmbyImportFixtures.authResponse)
        mockHTTP.enqueue(for: "Views", json: """
        {"Items": [{"Id": "lib-music", "Name": "Music", "CollectionType": "music"}]}
        """)

        let result = try await service.importEmby(
            serverURL: serverURL, username: "user", password: "pass", name: "Music Only"
        )

        XCTAssertNil(result.vodImportResult)
    }

    func testImportEmby_playlistType_isEmby() async throws {
        mockHTTP.enqueue(for: "AuthenticateByName", json: EmbyImportFixtures.authResponse)
        mockHTTP.enqueue(for: "Views", json: """
        {"Items": []}
        """)

        let result = try await service.importEmby(
            serverURL: serverURL, username: "user", password: "pass", name: "Test"
        )

        XCTAssertEqual(result.playlist.type, "emby")
    }

    func testImportEmby_movieFieldsMappedCorrectly() async throws {
        mockHTTP.enqueue(for: "AuthenticateByName", json: EmbyImportFixtures.authResponse)
        mockHTTP.enqueue(for: "Views", json: EmbyImportFixtures.librariesResponse)
        mockHTTP.enqueue(for: "Items", json: EmbyImportFixtures.moviesResponse)

        let result = try await service.importEmby(
            serverURL: serverURL, username: "user", password: "pass", name: "Test"
        )

        // Verify VOD items were persisted
        let vodRepo = VodRepository(dbManager: dbManager)
        let movies = try vodRepo.getMovies(playlistID: result.playlist.id)
        XCTAssertEqual(movies.count, 2)

        let inception = movies.first { $0.title == "Inception" }
        XCTAssertNotNil(inception)
        XCTAssertEqual(inception?.type, "movie")
        XCTAssertNotNil(inception?.streamURL)
    }
}

// MARK: - Test Helpers

private final class EmbyImportMockHTTPClient: HTTPClient, @unchecked Sendable {
    private var responses: [(matcher: String, data: Data, statusCode: Int)] = []

    func enqueue(for urlContaining: String, json: String, statusCode: Int = 200) {
        responses.append((urlContaining, Data(json.utf8), statusCode))
    }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
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
        return (Data("{\"Items\": [], \"TotalRecordCount\": 0}".utf8), httpResponse)
    }
}

private enum EmbyImportFixtures {
    static let authResponse = """
    {"User": {"Id": "user-123", "Name": "testuser"}, "AccessToken": "abc-token"}
    """

    static let librariesResponse = """
    {"Items": [{"Id": "lib-1", "Name": "Movies", "CollectionType": "movies"}]}
    """

    static let moviesResponse = """
    {
        "Items": [
            {"Id": "m1", "Name": "Inception", "Type": "Movie", "ProductionYear": 2010},
            {"Id": "m2", "Name": "Avatar", "Type": "Movie", "ProductionYear": 2009}
        ],
        "TotalRecordCount": 2
    }
    """
}
