import XCTest
@testable import XtreamClient

final class XtreamVODTests: XCTestCase {

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
    // MARK: - VOD Categories
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    func testGetVODCategories_parsesCorrectly() async throws {
        mockHTTP.enqueue(for: "get_vod_categories", json: XtreamFixtures.vodCategories)

        let categories = try await client.getVODCategories()

        XCTAssertEqual(categories.count, 2)
        XCTAssertEqual(categories[0].categoryId.value, "10")
        XCTAssertEqual(categories[0].categoryName, "Action Movies")
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - VOD Streams
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    func testGetVODStreams_parsesAllFields() async throws {
        mockHTTP.enqueue(for: "get_vod_streams", json: XtreamFixtures.vodStreams)

        let streams = try await client.getVODStreams()

        XCTAssertEqual(streams.count, 2)

        let matrix = streams[0]
        XCTAssertEqual(matrix.name, "The Matrix")
        XCTAssertEqual(matrix.streamId.value, 5001)
        XCTAssertEqual(matrix.rating?.value, 8.7)
        XCTAssertEqual(matrix.containerExtension, "mkv")
        XCTAssertNotNil(matrix.posterURL)

        // Second item has rating as number (not string)
        let inception = streams[1]
        XCTAssertEqual(inception.name, "Inception")
        XCTAssertEqual(inception.rating?.value, 8.8)
        XCTAssertEqual(inception.containerExtension, "mp4")
    }

    func testGetVODStreams_withCategoryFilter() async throws {
        mockHTTP.enqueue(for: "get_vod_streams", json: XtreamFixtures.vodStreams)

        _ = try await client.getVODStreams(categoryId: "10")

        let url = mockHTTP.requestsMade[0].url?.absoluteString ?? ""
        XCTAssertTrue(url.contains("action=get_vod_streams"))
        XCTAssertTrue(url.contains("category_id=10"))
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - VOD Info
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    func testGetVODInfo_parsesFullMetadata() async throws {
        mockHTTP.enqueue(for: "get_vod_info", json: XtreamFixtures.vodInfo)

        let info = try await client.getVODInfo(vodId: "5001")

        XCTAssertEqual(info.info?.genre, "Action, Sci-Fi")
        XCTAssertEqual(info.info?.cast, "Keanu Reeves, Laurence Fishburne")
        XCTAssertEqual(info.info?.director, "Lana Wachowski")
        XCTAssertEqual(info.info?.rating?.value, 8.7)
        XCTAssertEqual(info.info?.durationSecs?.value, 8177)
        XCTAssertEqual(info.info?.backdropPath?.values.count, 2)

        XCTAssertEqual(info.movieData?.streamId.value, 5001)
        XCTAssertEqual(info.movieData?.name, "The Matrix")
        XCTAssertEqual(info.movieData?.containerExtension, "mkv")
    }

    func testGetVODInfo_backdropAsString_parsesAsArray() async throws {
        mockHTTP.enqueue(for: "get_vod_info", json: XtreamFixtures.vodInfoBackdropString)

        let info = try await client.getVODInfo(vodId: "9999")

        XCTAssertEqual(info.info?.backdropPath?.values.count, 1)
        XCTAssertEqual(info.info?.backdropPath?.values.first, "https://cdn.example.com/backdrop.jpg")
    }

    func testGetVODInfo_emptyRating_parsesAsNil() async throws {
        mockHTTP.enqueue(for: "get_vod_info", json: XtreamFixtures.vodInfoBackdropString)

        let info = try await client.getVODInfo(vodId: "9999")

        XCTAssertNil(info.info?.rating?.value)
    }

    func testGetVODInfo_requestURL_containsVodId() async throws {
        mockHTTP.enqueue(for: "get_vod_info", json: XtreamFixtures.vodInfo)

        _ = try await client.getVODInfo(vodId: "5001")

        let url = mockHTTP.requestsMade[0].url?.absoluteString ?? ""
        XCTAssertTrue(url.contains("action=get_vod_info"))
        XCTAssertTrue(url.contains("vod_id=5001"))
    }
}
