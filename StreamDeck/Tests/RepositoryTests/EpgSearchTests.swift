import XCTest
import Database
@testable import Repositories

final class EpgSearchTests: XCTestCase {

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
        channelEpgID: String = "CNN.us",
        title: String,
        startTime: Int,
        endTime: Int
    ) -> EpgProgramRecord {
        EpgProgramRecord(
            id: id, channelEpgID: channelEpgID, title: title,
            startTime: startTime, endTime: endTime
        )
    }

    // MARK: - Search Programs

    func testSearchPrograms_matchesByTitle() throws {
        let p1 = makeProgram(id: "p1", title: "Morning News", startTime: 100, endTime: 200)
        let p2 = makeProgram(id: "p2", title: "Sports Center", startTime: 200, endTime: 300)
        let p3 = makeProgram(id: "p3", title: "Evening News", startTime: 300, endTime: 400)
        try repo.importPrograms([p1, p2, p3])

        let results = try repo.searchPrograms(query: "News", after: 0)

        XCTAssertEqual(results.count, 2)
        XCTAssertEqual(results[0].title, "Morning News")
        XCTAssertEqual(results[1].title, "Evening News")
    }

    func testSearchPrograms_excludesPastPrograms() throws {
        let past = makeProgram(id: "p1", title: "Old News", startTime: 100, endTime: 200)
        let future = makeProgram(id: "p2", title: "Future News", startTime: 300, endTime: 400)
        try repo.importPrograms([past, future])

        let results = try repo.searchPrograms(query: "News", after: 250)

        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].id, "p2")
    }

    func testSearchPrograms_includesCurrentlyAiring() throws {
        // Program that started at 100 and ends at 300, queried at after=200
        let current = makeProgram(id: "p1", title: "Live News", startTime: 100, endTime: 300)
        try repo.importPrograms([current])

        let results = try repo.searchPrograms(query: "News", after: 200)

        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].id, "p1")
    }

    func testSearchPrograms_respectsLimit() throws {
        var programs: [EpgProgramRecord] = []
        for i in 0..<30 {
            programs.append(makeProgram(
                id: "p\(i)", title: "News \(i)",
                startTime: 1000 + i * 100, endTime: 1000 + (i + 1) * 100
            ))
        }
        try repo.importPrograms(programs)

        let results = try repo.searchPrograms(query: "News", after: 0, limit: 5)

        XCTAssertEqual(results.count, 5)
    }
}
