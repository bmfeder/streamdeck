import XCTest
import Database
import XMLTVParser
import XtreamClient
@testable import Repositories

// MARK: - Mock HTTP Client (duplicated — can't share across test targets)

final class EpgMockHTTPClient: HTTPClient, @unchecked Sendable {
    private var responses: [(matcher: String, data: Data, statusCode: Int)] = []
    var errorToThrow: Error?

    func enqueue(for urlContaining: String, data: Data, statusCode: Int = 200) {
        responses.append((urlContaining, data, statusCode))
    }

    func enqueue(for urlContaining: String, string: String, statusCode: Int = 200) {
        enqueue(for: urlContaining, data: Data(string.utf8), statusCode: statusCode)
    }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
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
        fatalError("No mock response for \(urlString)")
    }
}

// MARK: - Fixtures

private enum Fixtures {
    static let xmltvSmall = """
    <?xml version="1.0" encoding="UTF-8"?>
    <tv generator-info-name="test">
      <channel id="CNN.us">
        <display-name>CNN</display-name>
      </channel>
      <programme start="20260225120000 +0000" stop="20260225130000 +0000" channel="CNN.us">
        <title>News Hour</title>
        <desc>Breaking news coverage</desc>
        <category>News</category>
      </programme>
      <programme start="20260225130000 +0000" stop="20260225140000 +0000" channel="CNN.us">
        <title>Afternoon Report</title>
      </programme>
    </tv>
    """

    static let xmltvEmpty = """
    <?xml version="1.0" encoding="UTF-8"?>
    <tv generator-info-name="test">
    </tv>
    """
}

// MARK: - Tests

final class EpgImportServiceTests: XCTestCase {

    var dbManager: DatabaseManager!
    var epgRepo: EpgRepository!
    var playlistRepo: PlaylistRepository!
    var mockHTTP: EpgMockHTTPClient!

    override func setUpWithError() throws {
        dbManager = try DatabaseManager()
        epgRepo = EpgRepository(dbManager: dbManager)
        playlistRepo = PlaylistRepository(dbManager: dbManager)
        mockHTTP = EpgMockHTTPClient()
    }

    override func tearDown() {
        dbManager = nil
        epgRepo = nil
        playlistRepo = nil
        mockHTTP = nil
    }

    private func makeService(
        now: Int = 1_740_000_000
    ) -> EpgImportService {
        nonisolated(unsafe) var counter = 0
        return EpgImportService(
            epgRepo: epgRepo,
            playlistRepo: playlistRepo,
            httpClient: mockHTTP,
            uuidGenerator: {
                counter += 1
                return "uuid-\(counter)"
            },
            nowProvider: { now }
        )
    }

    private func insertPlaylist(
        id: String = "pl-1",
        epgURL: String? = "http://example.com/epg.xml"
    ) throws {
        let playlist = PlaylistRecord(
            id: id,
            name: "Test",
            type: "m3u",
            url: "http://example.com/pl.m3u",
            epgURL: epgURL
        )
        try playlistRepo.create(playlist)
    }

    // MARK: - Import by playlist ID

    func testImportEPG_validPlaylistWithEpgURL_downloadsAndImports() async throws {
        try insertPlaylist(epgURL: "http://example.com/epg.xml")
        mockHTTP.enqueue(for: "epg.xml", string: Fixtures.xmltvSmall)

        let service = makeService()
        let result = try await service.importEPG(playlistID: "pl-1")

        XCTAssertEqual(result.programsImported, 2)
        XCTAssertEqual(result.parseErrorCount, 0)
        XCTAssertEqual(try epgRepo.count(), 2)
    }

    func testImportEPG_noEpgURL_throwsNoEpgURL() async throws {
        try insertPlaylist(epgURL: nil)

        let service = makeService()

        do {
            _ = try await service.importEPG(playlistID: "pl-1")
            XCTFail("Expected EpgImportError.noEpgURL")
        } catch let error as EpgImportError {
            XCTAssertEqual(error, .noEpgURL)
        }
    }

    func testImportEPG_noPlaylist_throwsNoEpgURL() async throws {
        let service = makeService()

        do {
            _ = try await service.importEPG(playlistID: "nonexistent")
            XCTFail("Expected EpgImportError.noEpgURL")
        } catch let error as EpgImportError {
            XCTAssertEqual(error, .noEpgURL)
        }
    }

    func testImportEPG_httpError_throwsDownloadFailed() async throws {
        try insertPlaylist()
        mockHTTP.enqueue(for: "epg.xml", string: "error", statusCode: 500)

        let service = makeService()

        do {
            _ = try await service.importEPG(playlistID: "pl-1")
            XCTFail("Expected EpgImportError.downloadFailed")
        } catch let error as EpgImportError {
            XCTAssertEqual(error, .downloadFailed("HTTP 500"))
        }
    }

    func testImportEPG_networkError_throwsNetworkError() async throws {
        try insertPlaylist()
        mockHTTP.errorToThrow = URLError(.notConnectedToInternet)

        let service = makeService()

        do {
            _ = try await service.importEPG(playlistID: "pl-1")
            XCTFail("Expected EpgImportError.networkError")
        } catch let error as EpgImportError {
            if case .networkError = error { } else {
                XCTFail("Expected networkError, got \(error)")
            }
        }
    }

    // MARK: - Persist EPG Data

    func testPersistEPGData_parsesAndPersists() throws {
        try insertPlaylist()
        let service = makeService()

        let result = try service.persistEPGData(
            Data(Fixtures.xmltvSmall.utf8),
            playlistID: "pl-1"
        )

        XCTAssertEqual(result.programsImported, 2)
        XCTAssertEqual(try epgRepo.count(), 2)
    }

    func testPersistEPGData_purgesOldPrograms() throws {
        try insertPlaylist()

        // Pre-insert an old program (endTime way in the past)
        let old = EpgProgramRecord(
            id: "old-1",
            channelEpgID: "OLD.ch",
            title: "Old Show",
            startTime: 100,
            endTime: 200
        )
        _ = try epgRepo.importPrograms([old])
        XCTAssertEqual(try epgRepo.count(), 1)

        let service = makeService(now: 1_740_000_000)
        let result = try service.persistEPGData(
            Data(Fixtures.xmltvSmall.utf8),
            playlistID: "pl-1"
        )

        XCTAssertEqual(result.programsPurged, 1)
    }

    func testPersistEPGData_updatesLastEpgSync() throws {
        try insertPlaylist()
        let now = 1_740_000_000
        let service = makeService(now: now)

        _ = try service.persistEPGData(
            Data(Fixtures.xmltvSmall.utf8),
            playlistID: "pl-1"
        )

        let playlist = try playlistRepo.get(id: "pl-1")
        XCTAssertEqual(playlist?.lastEpgSync, now)
    }

    func testPersistEPGData_emptyXMLTV_returnsZeroCounts() throws {
        try insertPlaylist()
        let service = makeService()

        let result = try service.persistEPGData(
            Data(Fixtures.xmltvEmpty.utf8),
            playlistID: "pl-1"
        )

        XCTAssertEqual(result.programsImported, 0)
        XCTAssertEqual(try epgRepo.count(), 0)
    }
}
