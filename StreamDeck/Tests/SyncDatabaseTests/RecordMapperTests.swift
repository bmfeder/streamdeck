import XCTest
@testable import Database
@testable import SyncDatabase

final class RecordMapperTests: XCTestCase {

    // MARK: - Timestamp Conversion

    func testEpochToISO_validEpoch_returnsISOString() {
        // 2024-01-15T12:00:00Z = 1705320000
        let result = RecordMappers.epochToISO(1705320000)
        XCTAssertEqual(result, "2024-01-15T12:00:00Z")
    }

    func testEpochToISO_nil_returnsNil() {
        XCTAssertNil(RecordMappers.epochToISO(nil))
    }

    func testEpochToISO_zeroEpoch_returnsUnixEpoch() {
        let result = RecordMappers.epochToISO(0)
        XCTAssertEqual(result, "1970-01-01T00:00:00Z")
    }

    func testISOToEpoch_validISO_returnsEpoch() {
        let result = RecordMappers.isoToEpoch("2024-01-15T12:00:00Z")
        XCTAssertEqual(result, 1705320000)
    }

    func testISOToEpoch_fractionalSeconds_returnsEpoch() {
        let result = RecordMappers.isoToEpoch("2024-01-15T12:00:00.000Z")
        XCTAssertEqual(result, 1705320000)
    }

    func testISOToEpoch_nil_returnsNil() {
        XCTAssertNil(RecordMappers.isoToEpoch(nil))
    }

    func testISOToEpoch_emptyString_returnsNil() {
        XCTAssertNil(RecordMappers.isoToEpoch(""))
    }

    func testISOToEpoch_roundTrip() {
        let epoch = 1706400000
        let iso = RecordMappers.epochToISO(epoch)
        XCTAssertNotNil(iso)
        let back = RecordMappers.isoToEpoch(iso)
        XCTAssertEqual(back, epoch)
    }

    // MARK: - Playlist Params

    func testPlaylistParams_includesAllFields() {
        let record = PlaylistRecord(
            id: "pl-1",
            name: "Test Playlist",
            type: "m3u",
            url: "https://example.com/playlist.m3u",
            username: "user",
            epgURL: "https://example.com/epg.xml",
            refreshHrs: 12,
            lastSync: 1705320000,
            isActive: false,
            sortOrder: 2
        )

        let params = RecordMappers.playlistParams(record)
        // Should have 11 params: name, type, url, username, encrypted_password, epg_url,
        // refresh_hrs, is_active, sort_order, last_sync, last_epg_sync
        XCTAssertEqual(params.count, 11)
        XCTAssertEqual(params[0] as? String, "Test Playlist")
        XCTAssertEqual(params[1] as? String, "m3u")
        XCTAssertEqual(params[2] as? String, "https://example.com/playlist.m3u")
        XCTAssertEqual(params[3] as? String, "user")
        // params[4] = encrypted_password (nil)
        XCTAssertEqual(params[5] as? String, "https://example.com/epg.xml")
        XCTAssertEqual(params[6] as? Int, 12)
        XCTAssertEqual(params[7] as? Int, 0) // isActive = false → 0
        XCTAssertEqual(params[8] as? Int, 2)
        XCTAssertEqual(params[9] as? String, "2024-01-15T12:00:00Z") // epoch → ISO
    }

    // MARK: - Channel Params

    func testChannelParams_mapsColumnNames() {
        let record = ChannelRecord(
            id: "ch-1",
            playlistID: "pl-1",
            name: "Channel One",
            groupName: "News",
            streamURL: "https://stream.example.com",
            channelNum: 42,
            isFavorite: true
        )

        let params = RecordMappers.channelParams(record)
        // Should have 12 params
        XCTAssertEqual(params.count, 12)
        XCTAssertEqual(params[0] as? String, "pl-1")
        XCTAssertEqual(params[8] as? Int, 42) // channelNum → channel_number
        XCTAssertEqual(params[9] as? Int, 1) // isFavorite → 1
    }

    // MARK: - VodItem Params

    func testVodItemParams_mapsRenamedColumns() {
        let record = VodItemRecord(
            id: "vod-1",
            playlistID: "pl-1",
            title: "Movie",
            type: "movie",
            posterURL: "https://poster.jpg",
            description: "A plot description",
            rating: 8.5,
            durationS: 7200
        )

        let params = RecordMappers.vodItemParams(record)
        // Check renamed columns
        XCTAssertEqual(params[4] as? String, "https://poster.jpg") // posterURL → logo_url
        XCTAssertEqual(params[7] as? String, "8.5") // rating Double → text
        XCTAssertEqual(params[8] as? Int, 7200) // durationS → duration
        XCTAssertEqual(params[13] as? String, "A plot description") // description → plot
    }

    // MARK: - WatchProgress Params

    func testWatchProgressParams_convertsTimestamp() {
        let record = WatchProgressRecord(
            contentID: "ch-1",
            playlistID: "pl-1",
            positionMs: 120000,
            durationMs: 3600000,
            updatedAt: 1705320000
        )

        let params = RecordMappers.watchProgressParams(record)
        XCTAssertEqual(params.count, 5)
        XCTAssertEqual(params[0] as? String, "ch-1")
        XCTAssertEqual(params[1] as? String, "pl-1")
        XCTAssertEqual(params[2] as? Int, 120000)
        XCTAssertEqual(params[3] as? Int, 3600000)
        XCTAssertEqual(params[4] as? String, "2024-01-15T12:00:00Z")
    }
}
