import XCTest
@testable import XtreamClient

final class XtreamErrorTests: XCTestCase {

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
    // MARK: - HTTP Errors
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    func testHTTPError_401_throwsHttpError() async {
        mockHTTP.enqueue(for: "player_api.php", json: "", statusCode: 401)

        do {
            _ = try await client.getLiveCategories()
            XCTFail("Expected httpError")
        } catch {
            XCTAssertEqual(error as? XtreamError, .httpError(statusCode: 401))
        }
    }

    func testHTTPError_500_throwsHttpError() async {
        mockHTTP.enqueue(for: "player_api.php", json: "", statusCode: 500)

        do {
            _ = try await client.getLiveStreams()
            XCTFail("Expected httpError")
        } catch {
            XCTAssertEqual(error as? XtreamError, .httpError(statusCode: 500))
        }
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - Decoding Errors
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    func testMalformedJSON_throwsDecodingFailed() async {
        mockHTTP.enqueue(for: "player_api.php", json: XtreamFixtures.malformedJSON)

        do {
            _ = try await client.getLiveCategories()
            XCTFail("Expected decodingFailed")
        } catch {
            guard case .decodingFailed = error as? XtreamError else {
                XCTFail("Expected decodingFailed, got \(error)")
                return
            }
        }
    }

    func testHTMLErrorPage_throwsDecodingFailed() async {
        mockHTTP.enqueue(for: "player_api.php", json: XtreamFixtures.htmlErrorPage)

        do {
            _ = try await client.getLiveStreams()
            XCTFail("Expected decodingFailed")
        } catch {
            guard case .decodingFailed = error as? XtreamError else {
                XCTFail("Expected decodingFailed, got \(error)")
                return
            }
        }
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - Network Errors
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    func testNetworkError_throwsNetworkError() async {
        mockHTTP.errorToThrow = URLError(.notConnectedToInternet)

        do {
            _ = try await client.getLiveCategories()
            XCTFail("Expected networkError")
        } catch {
            guard case .networkError = error as? XtreamError else {
                XCTFail("Expected networkError, got \(error)")
                return
            }
        }
    }

    func testNetworkTimeout_throwsNetworkError() async {
        mockHTTP.errorToThrow = URLError(.timedOut)

        do {
            _ = try await client.getLiveStreams()
            XCTFail("Expected networkError")
        } catch {
            guard case .networkError = error as? XtreamError else {
                XCTFail("Expected networkError, got \(error)")
                return
            }
        }
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - EPG
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    func testGetShortEPG_emptyListings_returnsEmpty() async throws {
        mockHTTP.enqueue(for: "get_short_epg", json: XtreamFixtures.emptyEPG)

        let listings = try await client.getShortEPG(streamId: "1001")

        XCTAssertTrue(listings.isEmpty)
    }

    func testGetShortEPG_withLimit_sendsLimitParam() async throws {
        mockHTTP.enqueue(for: "get_short_epg", json: XtreamFixtures.emptyEPG)

        _ = try await client.getShortEPG(streamId: "1001", limit: 5)

        let url = mockHTTP.requestsMade[0].url?.absoluteString ?? ""
        XCTAssertTrue(url.contains("limit=5"))
        XCTAssertTrue(url.contains("stream_id=1001"))
    }
}
