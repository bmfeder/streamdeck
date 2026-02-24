import XCTest
@testable import XtreamClient

final class XtreamClientTests: XCTestCase {

    private var mockHTTP: MockHTTPClient!
    private var client: XtreamClient!

    override func setUp() {
        super.setUp()
        mockHTTP = MockHTTPClient()
        let creds = XtreamCredentials(
            serverURL: URL(string: "http://provider.example.com:8080")!,
            username: "testuser",
            password: "testpass"
        )
        client = XtreamClient(credentials: creds, httpClient: mockHTTP)
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - Authentication
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    func testAuthenticate_success_returnsUserAndServerInfo() async throws {
        mockHTTP.enqueue(for: "player_api.php", json: XtreamFixtures.authSuccess)

        let response = try await client.authenticate()

        XCTAssertTrue(response.isAuthenticated)
        XCTAssertFalse(response.isExpired)
        XCTAssertEqual(response.userInfo.username, "testuser")
        XCTAssertEqual(response.userInfo.status, "Active")
        XCTAssertEqual(response.userInfo.maxConnections?.value, 2)
        XCTAssertEqual(response.userInfo.allowedOutputFormats, ["m3u8", "ts"])
        XCTAssertEqual(response.serverInfo.port?.value, "8080")
        XCTAssertEqual(response.serverInfo.timezone, "America/New_York")
    }

    func testAuthenticate_failed_throwsAuthenticationFailed() async {
        mockHTTP.enqueue(for: "player_api.php", json: XtreamFixtures.authFailed)

        do {
            _ = try await client.authenticate()
            XCTFail("Expected authenticationFailed error")
        } catch {
            XCTAssertEqual(error as? XtreamError, .authenticationFailed)
        }
    }

    func testAuthenticate_expired_throwsAccountExpired() async {
        mockHTTP.enqueue(for: "player_api.php", json: XtreamFixtures.authExpired)

        do {
            _ = try await client.authenticate()
            XCTFail("Expected accountExpired error")
        } catch {
            XCTAssertEqual(error as? XtreamError, .accountExpired)
        }
    }

    func testAuthenticate_numericFields_decodesCorrectly() async throws {
        mockHTTP.enqueue(for: "player_api.php", json: XtreamFixtures.authNumericFields)

        let response = try await client.authenticate()

        XCTAssertTrue(response.isAuthenticated)
        XCTAssertEqual(response.userInfo.isTrial?.value, 0)
        XCTAssertEqual(response.userInfo.activeCons?.value, 1)
        XCTAssertEqual(response.serverInfo.port?.value, "8080")
    }

    func testAuthenticate_nullExpDate_isNotExpired() async throws {
        mockHTTP.enqueue(for: "player_api.php", json: XtreamFixtures.authNullExpDate)

        let response = try await client.authenticate()

        XCTAssertTrue(response.isAuthenticated)
        XCTAssertFalse(response.isExpired)
        XCTAssertNil(response.userInfo.expDate?.value)
    }

    func testAuthenticate_requestURL_containsCredentials() async throws {
        mockHTTP.enqueue(for: "player_api.php", json: XtreamFixtures.authSuccess)

        _ = try await client.authenticate()

        XCTAssertEqual(mockHTTP.requestsMade.count, 1)
        let url = mockHTTP.requestsMade[0].url?.absoluteString ?? ""
        XCTAssertTrue(url.contains("username=testuser"))
        XCTAssertTrue(url.contains("password=testpass"))
        XCTAssertTrue(url.contains("player_api.php"))
        // Auth request has no action param
        XCTAssertFalse(url.contains("action="))
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - Live Categories
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    func testGetLiveCategories_parsesAllCategories() async throws {
        mockHTTP.enqueue(for: "get_live_categories", json: XtreamFixtures.liveCategories)

        let categories = try await client.getLiveCategories()

        XCTAssertEqual(categories.count, 3)
        XCTAssertEqual(categories[0].categoryId.value, "1")
        XCTAssertEqual(categories[0].categoryName, "Sports")
        XCTAssertEqual(categories[0].parentId.value, 0)
        XCTAssertEqual(categories[2].categoryName, "Football")
        XCTAssertEqual(categories[2].parentId.value, 1)
    }

    func testGetLiveCategories_emptyArray_returnsEmpty() async throws {
        mockHTTP.enqueue(for: "get_live_categories", json: XtreamFixtures.emptyArray)

        let categories = try await client.getLiveCategories()

        XCTAssertTrue(categories.isEmpty)
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - Live Streams
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    func testGetLiveStreams_parsesAllFields() async throws {
        mockHTTP.enqueue(for: "get_live_streams", json: XtreamFixtures.liveStreams)

        let streams = try await client.getLiveStreams()

        XCTAssertEqual(streams.count, 2)

        let espn = streams[0]
        XCTAssertEqual(espn.name, "ESPN HD")
        XCTAssertEqual(espn.streamId.value, 1001)
        XCTAssertEqual(espn.epgChannelId, "ESPN.us")
        XCTAssertEqual(espn.categoryId.value, "1")
        XCTAssertEqual(espn.tvArchive.value, 0)
        XCTAssertNotNil(espn.logoURL)

        let cnn = streams[1]
        XCTAssertEqual(cnn.name, "CNN International")
        XCTAssertEqual(cnn.tvArchive.value, 1)
        XCTAssertNil(cnn.logoURL) // empty string icon
    }

    func testGetLiveStreams_withCategoryFilter_sendsCorrectParam() async throws {
        mockHTTP.enqueue(for: "get_live_streams", json: XtreamFixtures.liveStreams)

        _ = try await client.getLiveStreams(categoryId: "1")

        let url = mockHTTP.requestsMade[0].url?.absoluteString ?? ""
        XCTAssertTrue(url.contains("action=get_live_streams"))
        XCTAssertTrue(url.contains("category_id=1"))
    }

    func testGetLiveStreams_withoutCategoryFilter_noCategoryParam() async throws {
        mockHTTP.enqueue(for: "get_live_streams", json: XtreamFixtures.liveStreams)

        _ = try await client.getLiveStreams()

        let url = mockHTTP.requestsMade[0].url?.absoluteString ?? ""
        XCTAssertTrue(url.contains("action=get_live_streams"))
        XCTAssertFalse(url.contains("category_id"))
    }
}
