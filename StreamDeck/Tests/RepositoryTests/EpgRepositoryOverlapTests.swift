import XCTest
import Database
@testable import Repositories

final class EpgRepositoryOverlapTests: XCTestCase {

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
        id: String,
        channelEpgID: String,
        title: String = "Show",
        startTime: Int,
        endTime: Int
    ) -> EpgProgramRecord {
        EpgProgramRecord(
            id: id,
            channelEpgID: channelEpgID,
            title: title,
            startTime: startTime,
            endTime: endTime
        )
    }

    // MARK: - getProgramsOverlapping

    func testGetProgramsOverlapping_returnsOverlappingPrograms() throws {
        // Window: 1000-2000
        // Program: 900-1500 (overlaps), 1500-2500 (overlaps), 2500-3000 (outside)
        let p1 = makeProgram(id: "p1", channelEpgID: "CNN", title: "Early", startTime: 900, endTime: 1500)
        let p2 = makeProgram(id: "p2", channelEpgID: "CNN", title: "Mid", startTime: 1500, endTime: 2500)
        let p3 = makeProgram(id: "p3", channelEpgID: "CNN", title: "Late", startTime: 2500, endTime: 3000)
        _ = try repo.importPrograms([p1, p2, p3])

        let result = try repo.getProgramsOverlapping(channelEpgIDs: ["CNN"], from: 1000, to: 2000)

        XCTAssertEqual(result["CNN"]?.count, 2)
        XCTAssertEqual(result["CNN"]?[0].title, "Early")
        XCTAssertEqual(result["CNN"]?[1].title, "Mid")
    }

    func testGetProgramsOverlapping_includesProgramStartingBeforeWindow() throws {
        // Program starts before window but ends within it
        let p = makeProgram(id: "p1", channelEpgID: "BBC", startTime: 500, endTime: 1500)
        _ = try repo.importPrograms([p])

        let result = try repo.getProgramsOverlapping(channelEpgIDs: ["BBC"], from: 1000, to: 2000)

        XCTAssertEqual(result["BBC"]?.count, 1)
        XCTAssertEqual(result["BBC"]?[0].id, "p1")
    }

    func testGetProgramsOverlapping_excludesNonOverlapping() throws {
        // Program entirely before window
        let before = makeProgram(id: "p1", channelEpgID: "CNN", startTime: 100, endTime: 500)
        // Program entirely after window
        let after = makeProgram(id: "p2", channelEpgID: "CNN", startTime: 3000, endTime: 4000)
        // Program at exact boundary (endTime == from) — NOT overlapping
        let boundary = makeProgram(id: "p3", channelEpgID: "CNN", startTime: 500, endTime: 1000)
        _ = try repo.importPrograms([before, after, boundary])

        let result = try repo.getProgramsOverlapping(channelEpgIDs: ["CNN"], from: 1000, to: 2000)

        XCTAssertEqual(result["CNN"]?.count ?? 0, 0)
    }

    func testGetProgramsOverlapping_multipleChannels_groupsCorrectly() throws {
        let p1 = makeProgram(id: "p1", channelEpgID: "CNN", title: "CNN News", startTime: 1000, endTime: 2000)
        let p2 = makeProgram(id: "p2", channelEpgID: "BBC", title: "BBC News", startTime: 1200, endTime: 1800)
        let p3 = makeProgram(id: "p3", channelEpgID: "FOX", title: "Fox Show", startTime: 5000, endTime: 6000)
        _ = try repo.importPrograms([p1, p2, p3])

        let result = try repo.getProgramsOverlapping(
            channelEpgIDs: ["CNN", "BBC", "FOX"],
            from: 1000,
            to: 2000
        )

        XCTAssertEqual(result["CNN"]?.count, 1)
        XCTAssertEqual(result["BBC"]?.count, 1)
        XCTAssertNil(result["FOX"]) // no overlapping programs
    }

    func testGetProgramsOverlapping_emptyChannelIDs_returnsEmpty() throws {
        let p = makeProgram(id: "p1", channelEpgID: "CNN", startTime: 1000, endTime: 2000)
        _ = try repo.importPrograms([p])

        let result = try repo.getProgramsOverlapping(channelEpgIDs: [], from: 1000, to: 2000)

        XCTAssertTrue(result.isEmpty)
    }

    func testGetProgramsOverlapping_noPrograms_returnsEmpty() throws {
        let result = try repo.getProgramsOverlapping(channelEpgIDs: ["CNN"], from: 1000, to: 2000)

        XCTAssertTrue(result.isEmpty)
    }
}
