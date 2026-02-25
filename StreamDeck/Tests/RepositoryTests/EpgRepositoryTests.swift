import XCTest
import Database
@testable import Repositories

final class EpgRepositoryTests: XCTestCase {

    var dbManager: DatabaseManager!
    var repo: EpgRepository!

    override func setUpWithError() throws {
        dbManager = try DatabaseManager()
        repo = EpgRepository(dbManager: dbManager)
    }

    override func tearDown() {
        repo = nil
        dbManager = nil
    }

    private func makeProgram(
        id: String = "epg-1",
        channelEpgID: String = "CNN.us",
        title: String = "News Hour",
        description: String? = "Breaking news",
        startTime: Int = 1000,
        endTime: Int = 2000,
        category: String? = "News",
        iconURL: String? = nil
    ) -> EpgProgramRecord {
        EpgProgramRecord(
            id: id,
            channelEpgID: channelEpgID,
            title: title,
            description: description,
            startTime: startTime,
            endTime: endTime,
            category: category,
            iconURL: iconURL
        )
    }

    // MARK: - Import

    func testImportPrograms_insertsRecords() throws {
        let programs = [
            makeProgram(id: "p1", startTime: 1000, endTime: 2000),
            makeProgram(id: "p2", startTime: 2000, endTime: 3000),
        ]

        let count = try repo.importPrograms(programs)

        XCTAssertEqual(count, 2)
        XCTAssertEqual(try repo.count(), 2)
    }

    func testImportPrograms_upsertOnDuplicateKey() throws {
        let original = makeProgram(id: "p1", title: "Old Title", startTime: 1000, endTime: 2000)
        try repo.importPrograms([original])

        let updated = makeProgram(id: "p1", title: "New Title", startTime: 1000, endTime: 2000)
        try repo.importPrograms([updated])

        XCTAssertEqual(try repo.count(), 1)
        let fetched = try repo.getCurrentProgram(channelEpgID: "CNN.us", at: 1500)
        XCTAssertEqual(fetched?.title, "New Title")
    }

    func testImportPrograms_emptyArray_returnsZero() throws {
        let count = try repo.importPrograms([])
        XCTAssertEqual(count, 0)
    }

    // MARK: - getCurrentProgram

    func testGetCurrentProgram_matchesTimeRange() throws {
        try repo.importPrograms([
            makeProgram(id: "p1", startTime: 1000, endTime: 2000),
            makeProgram(id: "p2", startTime: 2000, endTime: 3000),
        ])

        let current = try repo.getCurrentProgram(channelEpgID: "CNN.us", at: 1500)
        XCTAssertEqual(current?.id, "p1")
    }

    func testGetCurrentProgram_noMatch_returnsNil() throws {
        try repo.importPrograms([
            makeProgram(id: "p1", startTime: 1000, endTime: 2000),
        ])

        let current = try repo.getCurrentProgram(channelEpgID: "CNN.us", at: 500)
        XCTAssertNil(current)
    }

    func testGetCurrentProgram_boundaryStartTimeEquals() throws {
        try repo.importPrograms([
            makeProgram(id: "p1", startTime: 1000, endTime: 2000),
        ])

        let current = try repo.getCurrentProgram(channelEpgID: "CNN.us", at: 1000)
        XCTAssertEqual(current?.id, "p1")
    }

    func testGetCurrentProgram_boundaryEndTimeEquals_returnsNil() throws {
        try repo.importPrograms([
            makeProgram(id: "p1", startTime: 1000, endTime: 2000),
        ])

        let current = try repo.getCurrentProgram(channelEpgID: "CNN.us", at: 2000)
        XCTAssertNil(current)
    }

    // MARK: - getNextProgram

    func testGetNextProgram_returnsFirstAfterTimestamp() throws {
        try repo.importPrograms([
            makeProgram(id: "p1", startTime: 1000, endTime: 2000),
            makeProgram(id: "p2", startTime: 2000, endTime: 3000),
            makeProgram(id: "p3", startTime: 3000, endTime: 4000),
        ])

        let next = try repo.getNextProgram(channelEpgID: "CNN.us", after: 1500)
        XCTAssertEqual(next?.id, "p2")
    }

    func testGetNextProgram_noFuturePrograms_returnsNil() throws {
        try repo.importPrograms([
            makeProgram(id: "p1", startTime: 1000, endTime: 2000),
        ])

        let next = try repo.getNextProgram(channelEpgID: "CNN.us", after: 2000)
        XCTAssertNil(next)
    }

    // MARK: - getPrograms (time range)

    func testGetPrograms_timeRange_returnsOrdered() throws {
        try repo.importPrograms([
            makeProgram(id: "p1", startTime: 1000, endTime: 2000),
            makeProgram(id: "p2", startTime: 2000, endTime: 3000),
            makeProgram(id: "p3", startTime: 3000, endTime: 4000),
            makeProgram(id: "p4", startTime: 4000, endTime: 5000),
        ])

        let programs = try repo.getPrograms(channelEpgID: "CNN.us", from: 1500, to: 3500)
        XCTAssertEqual(programs.count, 2)
        XCTAssertEqual(programs[0].id, "p2")
        XCTAssertEqual(programs[1].id, "p3")
    }

    func testGetPrograms_emptyRange_returnsEmpty() throws {
        try repo.importPrograms([
            makeProgram(id: "p1", startTime: 1000, endTime: 2000),
        ])

        let programs = try repo.getPrograms(channelEpgID: "CNN.us", from: 5000, to: 6000)
        XCTAssertTrue(programs.isEmpty)
    }

    // MARK: - Purge

    func testPurgeOldPrograms_deletesExpired() throws {
        try repo.importPrograms([
            makeProgram(id: "p1", startTime: 100, endTime: 200),
            makeProgram(id: "p2", startTime: 200, endTime: 300),
            makeProgram(id: "p3", startTime: 1000, endTime: 2000),
        ])

        let deleted = try repo.purgeOldPrograms(olderThan: 500)
        XCTAssertEqual(deleted, 2)
        XCTAssertEqual(try repo.count(), 1)
    }

    func testPurgeOldPrograms_keepsRecent() throws {
        try repo.importPrograms([
            makeProgram(id: "p1", startTime: 1000, endTime: 2000),
        ])

        let deleted = try repo.purgeOldPrograms(olderThan: 500)
        XCTAssertEqual(deleted, 0)
        XCTAssertEqual(try repo.count(), 1)
    }

    // MARK: - Count

    func testCount_returnsTotal() throws {
        try repo.importPrograms([
            makeProgram(id: "p1", channelEpgID: "CNN.us", startTime: 1000, endTime: 2000),
            makeProgram(id: "p2", channelEpgID: "BBC.uk", startTime: 1000, endTime: 2000),
        ])

        XCTAssertEqual(try repo.count(), 2)
    }

    func testCount_channelSpecific() throws {
        try repo.importPrograms([
            makeProgram(id: "p1", channelEpgID: "CNN.us", startTime: 1000, endTime: 2000),
            makeProgram(id: "p2", channelEpgID: "CNN.us", startTime: 2000, endTime: 3000),
            makeProgram(id: "p3", channelEpgID: "BBC.uk", startTime: 1000, endTime: 2000),
        ])

        XCTAssertEqual(try repo.count(channelEpgID: "CNN.us"), 2)
        XCTAssertEqual(try repo.count(channelEpgID: "BBC.uk"), 1)
    }
}
