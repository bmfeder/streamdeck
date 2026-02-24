import XCTest
@testable import XtreamClient

final class XtreamSeriesTests: XCTestCase {

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
    // MARK: - Series Categories
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    func testGetSeriesCategories_parsesCorrectly() async throws {
        mockHTTP.enqueue(for: "get_series_categories", json: XtreamFixtures.seriesCategories)

        let categories = try await client.getSeriesCategories()

        XCTAssertEqual(categories.count, 2)
        XCTAssertEqual(categories[0].categoryId.value, "20")
        XCTAssertEqual(categories[0].categoryName, "Drama")
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - Series List
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    func testGetSeries_parsesAllFields() async throws {
        mockHTTP.enqueue(for: "action=get_series", json: XtreamFixtures.seriesList)

        let series = try await client.getSeries()

        XCTAssertEqual(series.count, 1)
        let bb = series[0]
        XCTAssertEqual(bb.name, "Breaking Bad")
        XCTAssertEqual(bb.seriesId.value, 789)
        XCTAssertEqual(bb.genre, "Crime, Drama, Thriller")
        XCTAssertEqual(bb.rating?.value, 9.5)
        XCTAssertNotNil(bb.coverURL)
        XCTAssertEqual(bb.backdropPath?.values.count, 1)
    }

    func testGetSeries_withCategoryFilter() async throws {
        mockHTTP.enqueue(for: "action=get_series", json: XtreamFixtures.seriesList)

        _ = try await client.getSeries(categoryId: "20")

        let url = mockHTTP.requestsMade[0].url?.absoluteString ?? ""
        XCTAssertTrue(url.contains("action=get_series"))
        XCTAssertTrue(url.contains("category_id=20"))
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - Series Info
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    func testGetSeriesInfo_parsesSeasonsAndEpisodes() async throws {
        mockHTTP.enqueue(for: "get_series_info", json: XtreamFixtures.seriesInfo)

        let info = try await client.getSeriesInfo(seriesId: "789")

        // Metadata
        XCTAssertEqual(info.info?.name, "Breaking Bad")
        XCTAssertEqual(info.info?.genre, "Crime, Drama, Thriller")

        // Seasons
        XCTAssertEqual(info.seasons?.count, 2)
        XCTAssertEqual(info.seasons?[0].seasonNumber.value, 1)
        XCTAssertEqual(info.seasons?[0].name, "Season 1")
        XCTAssertEqual(info.seasons?[0].episodeCount?.value, 7)
        XCTAssertEqual(info.seasons?[1].seasonNumber.value, 2)

        // Episodes keyed by season number string
        XCTAssertEqual(info.episodes?.count, 2)
        let season1Episodes = info.episodes?["1"]
        XCTAssertEqual(season1Episodes?.count, 2)
        XCTAssertEqual(season1Episodes?[0].title, "Pilot")
        XCTAssertEqual(season1Episodes?[0].id.value, "45678")
        XCTAssertEqual(season1Episodes?[0].containerExtension, "mkv")
        XCTAssertEqual(season1Episodes?[0].info?.durationSecs?.value, 3480)
        XCTAssertEqual(season1Episodes?[0].season.value, 1)

        let season2Episodes = info.episodes?["2"]
        XCTAssertEqual(season2Episodes?.count, 1)
        XCTAssertEqual(season2Episodes?[0].title, "Seven Thirty-Seven")
    }

    func testGetSeriesInfo_requestURL_containsSeriesId() async throws {
        mockHTTP.enqueue(for: "get_series_info", json: XtreamFixtures.seriesInfo)

        _ = try await client.getSeriesInfo(seriesId: "789")

        let url = mockHTTP.requestsMade[0].url?.absoluteString ?? ""
        XCTAssertTrue(url.contains("action=get_series_info"))
        XCTAssertTrue(url.contains("series_id=789"))
    }
}
