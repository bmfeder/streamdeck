import XCTest
@testable import XtreamClient

final class XtreamURLBuilderTests: XCTestCase {

    private var client: XtreamClient!

    override func setUp() {
        super.setUp()
        let creds = XtreamCredentials(
            serverURL: URL(string: "http://provider.example.com:8080")!,
            username: "testuser",
            password: "testpass"
        )
        client = XtreamClient(credentials: creds, httpClient: MockHTTPClient())
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - Live Stream URLs
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    func testLiveStreamURL_m3u8Format() {
        let url = client.liveStreamURL(streamId: 1001, format: .m3u8)
        XCTAssertEqual(url.absoluteString, "http://provider.example.com:8080/live/testuser/testpass/1001.m3u8")
    }

    func testLiveStreamURL_tsFormat() {
        let url = client.liveStreamURL(streamId: 1001, format: .ts)
        XCTAssertEqual(url.absoluteString, "http://provider.example.com:8080/live/testuser/testpass/1001.ts")
    }

    func testLiveStreamURL_defaultFormat_isM3U8() {
        let url = client.liveStreamURL(streamId: 1001)
        XCTAssertTrue(url.absoluteString.hasSuffix("1001.m3u8"))
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - VOD Stream URLs
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    func testVODStreamURL_mkv() {
        let url = client.vodStreamURL(streamId: 5001, containerExtension: "mkv")
        XCTAssertEqual(url.absoluteString, "http://provider.example.com:8080/movie/testuser/testpass/5001.mkv")
    }

    func testVODStreamURL_mp4() {
        let url = client.vodStreamURL(streamId: 5002, containerExtension: "mp4")
        XCTAssertEqual(url.absoluteString, "http://provider.example.com:8080/movie/testuser/testpass/5002.mp4")
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - Series Stream URLs
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    func testSeriesStreamURL_mkv() {
        let url = client.seriesStreamURL(episodeId: 45678, containerExtension: "mkv")
        XCTAssertEqual(url.absoluteString, "http://provider.example.com:8080/series/testuser/testpass/45678.mkv")
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - HTTPS Server
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    func testStreamURL_httpsServer() {
        let creds = XtreamCredentials(
            serverURL: URL(string: "https://secure.example.com")!,
            username: "user",
            password: "pass"
        )
        let secureClient = XtreamClient(credentials: creds, httpClient: MockHTTPClient())

        let url = secureClient.liveStreamURL(streamId: 100, format: .ts)
        XCTAssertTrue(url.absoluteString.hasPrefix("https://"))
        XCTAssertEqual(url.absoluteString, "https://secure.example.com/live/user/pass/100.ts")
    }
}
