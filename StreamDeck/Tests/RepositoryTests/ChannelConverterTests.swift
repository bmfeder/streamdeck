import XCTest
import Foundation
import M3UParser
import XtreamClient
import Database
@testable import Repositories

final class ChannelConverterTests: XCTestCase {

    // MARK: - Helpers

    /// Creates an XtreamLiveStream via JSON decoding (no memberwise init available).
    private func makeXtreamStream(
        num: Int = 1,
        name: String = "Test",
        streamType: String? = nil,
        streamId: Int = 1,
        streamIcon: String? = nil,
        epgChannelId: String? = nil,
        added: Int? = nil,
        categoryId: String = "",
        customSid: String? = nil,
        tvArchive: Int = 0,
        directSource: String? = nil,
        tvArchiveDuration: Int? = nil
    ) throws -> XtreamLiveStream {
        var dict: [String: Any] = [
            "num": num,
            "name": name,
            "stream_id": streamId,
            "category_id": categoryId,
            "tv_archive": tvArchive,
        ]
        if let streamType { dict["stream_type"] = streamType }
        if let streamIcon { dict["stream_icon"] = streamIcon }
        if let epgChannelId { dict["epg_channel_id"] = epgChannelId }
        if let added { dict["added"] = added }
        if let customSid { dict["custom_sid"] = customSid }
        if let directSource { dict["direct_source"] = directSource }
        if let tvArchiveDuration { dict["tv_archive_duration"] = tvArchiveDuration }

        let data = try JSONSerialization.data(withJSONObject: dict)
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(XtreamLiveStream.self, from: data)
    }

    // MARK: - M3U → ChannelRecord

    func testFromParsedChannel_allFields() {
        let parsed = ParsedChannel(
            name: "CNN International",
            streamURL: URL(string: "http://example.com/cnn.m3u8")!,
            groupTitle: "News",
            tvgId: "cnn.us",
            tvgName: "CNN",
            tvgLogo: URL(string: "http://example.com/cnn.png"),
            channelNumber: 42
        )

        let record = ChannelConverter.fromParsedChannel(parsed, playlistID: "pl-1", id: "fixed-id")

        XCTAssertEqual(record.id, "fixed-id")
        XCTAssertEqual(record.playlistID, "pl-1")
        XCTAssertEqual(record.sourceChannelID, "cnn.us")
        XCTAssertEqual(record.name, "CNN International")
        XCTAssertEqual(record.groupName, "News")
        XCTAssertEqual(record.streamURL, "http://example.com/cnn.m3u8")
        XCTAssertEqual(record.logoURL, "http://example.com/cnn.png")
        XCTAssertEqual(record.tvgID, "cnn.us")
        XCTAssertEqual(record.channelNum, 42)
        XCTAssertNil(record.epgID)
        XCTAssertFalse(record.isFavorite)
        XCTAssertFalse(record.isDeleted)
        XCTAssertNil(record.deletedAt)
    }

    func testFromParsedChannel_minimalFields() {
        let parsed = ParsedChannel(
            name: "Test",
            streamURL: URL(string: "http://example.com/stream")!
        )

        let record = ChannelConverter.fromParsedChannel(parsed, playlistID: "pl-1", id: "id-1")

        XCTAssertEqual(record.name, "Test")
        XCTAssertEqual(record.streamURL, "http://example.com/stream")
        XCTAssertNil(record.sourceChannelID)
        XCTAssertNil(record.groupName)
        XCTAssertNil(record.logoURL)
        XCTAssertNil(record.tvgID)
        XCTAssertNil(record.channelNum)
    }

    func testFromParsedChannel_generatesUUID_whenNoIDProvided() {
        let parsed = ParsedChannel(
            name: "Test",
            streamURL: URL(string: "http://example.com/stream")!
        )

        let record = ChannelConverter.fromParsedChannel(parsed, playlistID: "pl-1")

        XCTAssertFalse(record.id.isEmpty)
        XCTAssertNotNil(UUID(uuidString: record.id))
    }

    func testFromParsedChannel_tvgIdUsedForBothSourceAndTvg() {
        let parsed = ParsedChannel(
            name: "BBC",
            streamURL: URL(string: "http://example.com/bbc")!,
            tvgId: "bbc.uk"
        )

        let record = ChannelConverter.fromParsedChannel(parsed, playlistID: "pl-1", id: "id-1")

        XCTAssertEqual(record.sourceChannelID, "bbc.uk")
        XCTAssertEqual(record.tvgID, "bbc.uk")
    }

    // MARK: - Xtream → ChannelRecord

    func testFromXtreamLiveStream_allFields() throws {
        let stream = try makeXtreamStream(
            num: 1,
            name: "ESPN",
            streamType: "live",
            streamId: 500,
            streamIcon: "http://example.com/espn.png",
            epgChannelId: "espn.us",
            added: 1700000000,
            categoryId: "5"
        )

        let record = ChannelConverter.fromXtreamLiveStream(
            stream,
            playlistID: "pl-2",
            categoryName: "Sports",
            streamURL: "http://server.com/live/user/pass/500.m3u8",
            id: "fixed-id"
        )

        XCTAssertEqual(record.id, "fixed-id")
        XCTAssertEqual(record.playlistID, "pl-2")
        XCTAssertEqual(record.sourceChannelID, "500")
        XCTAssertEqual(record.name, "ESPN")
        XCTAssertEqual(record.groupName, "Sports")
        XCTAssertEqual(record.streamURL, "http://server.com/live/user/pass/500.m3u8")
        XCTAssertEqual(record.logoURL, "http://example.com/espn.png")
        XCTAssertEqual(record.epgID, "espn.us")
        XCTAssertEqual(record.tvgID, "espn.us")
        XCTAssertNil(record.channelNum)
        XCTAssertFalse(record.isFavorite)
        XCTAssertFalse(record.isDeleted)
    }

    func testFromXtreamLiveStream_nilOptionals() throws {
        let stream = try makeXtreamStream(
            name: "Unknown",
            streamId: 99
        )

        let record = ChannelConverter.fromXtreamLiveStream(
            stream,
            playlistID: "pl-2",
            categoryName: nil,
            streamURL: "http://server.com/live/user/pass/99.m3u8",
            id: "id-1"
        )

        XCTAssertEqual(record.sourceChannelID, "99")
        XCTAssertEqual(record.name, "Unknown")
        XCTAssertNil(record.groupName)
        XCTAssertNil(record.logoURL)
        XCTAssertNil(record.epgID)
        XCTAssertNil(record.tvgID)
    }

    func testFromXtreamLiveStream_generatesUUID_whenNoIDProvided() throws {
        let stream = try makeXtreamStream(name: "Test", streamId: 1)

        let record = ChannelConverter.fromXtreamLiveStream(
            stream,
            playlistID: "pl-2",
            categoryName: nil,
            streamURL: "http://example.com/stream"
        )

        XCTAssertFalse(record.id.isEmpty)
        XCTAssertNotNil(UUID(uuidString: record.id))
    }
}
