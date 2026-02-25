import XCTest
import Database
import XMLTVParser
@testable import Repositories

final class EpgConverterTests: XCTestCase {

    func testFromParsedProgram_mapsAllFields() {
        let parsed = ParsedProgram(
            channelID: "CNN.us",
            startTimestamp: 1_000_000,
            stopTimestamp: 1_003_600,
            title: "News Hour",
            description: "Breaking news",
            category: "News",
            categories: ["News", "Current Affairs"],
            iconURL: URL(string: "http://example.com/icon.png")
        )

        let record = EpgConverter.fromParsedProgram(parsed, id: "epg-1")

        XCTAssertEqual(record.id, "epg-1")
        XCTAssertEqual(record.channelEpgID, "CNN.us")
        XCTAssertEqual(record.title, "News Hour")
        XCTAssertEqual(record.description, "Breaking news")
        XCTAssertEqual(record.startTime, 1_000_000)
        XCTAssertEqual(record.endTime, 1_003_600)
        XCTAssertEqual(record.category, "News")
        XCTAssertEqual(record.iconURL, "http://example.com/icon.png")
    }

    func testFromParsedProgram_nilOptionalFields() {
        let parsed = ParsedProgram(
            channelID: "BBC.uk",
            startTimestamp: 2_000_000,
            stopTimestamp: 2_003_600,
            title: "Show"
        )

        let record = EpgConverter.fromParsedProgram(parsed, id: "epg-2")

        XCTAssertNil(record.description)
        XCTAssertNil(record.category)
        XCTAssertNil(record.iconURL)
    }

    func testFromParsedProgram_preservesTimestamps() {
        let parsed = ParsedProgram(
            channelID: "ch-1",
            startTimestamp: 1_740_000_000,
            stopTimestamp: 1_740_003_600,
            title: "Test"
        )

        let record = EpgConverter.fromParsedProgram(parsed, id: "id")

        XCTAssertEqual(record.startTime, 1_740_000_000)
        XCTAssertEqual(record.endTime, 1_740_003_600)
    }

    func testFromParsedPrograms_batch_generatesUniqueIDs() {
        let programs = [
            ParsedProgram(channelID: "ch-1", startTimestamp: 100, stopTimestamp: 200, title: "A"),
            ParsedProgram(channelID: "ch-1", startTimestamp: 200, stopTimestamp: 300, title: "B"),
            ParsedProgram(channelID: "ch-2", startTimestamp: 100, stopTimestamp: 200, title: "C"),
        ]

        var counter = 0
        let records = EpgConverter.fromParsedPrograms(programs) {
            counter += 1
            return "id-\(counter)"
        }

        XCTAssertEqual(records.count, 3)
        XCTAssertEqual(records[0].id, "id-1")
        XCTAssertEqual(records[1].id, "id-2")
        XCTAssertEqual(records[2].id, "id-3")
        XCTAssertEqual(records[0].title, "A")
        XCTAssertEqual(records[2].channelEpgID, "ch-2")
    }

    func testFromParsedPrograms_emptyArray_returnsEmpty() {
        let records = EpgConverter.fromParsedPrograms([])
        XCTAssertTrue(records.isEmpty)
    }

    func testFromParsedProgram_iconURLConvertsToString() {
        let parsed = ParsedProgram(
            channelID: "ch-1",
            startTimestamp: 100,
            stopTimestamp: 200,
            title: "Show",
            iconURL: URL(string: "https://cdn.example.com/img/show.jpg?w=300")
        )

        let record = EpgConverter.fromParsedProgram(parsed, id: "id")

        XCTAssertEqual(record.iconURL, "https://cdn.example.com/img/show.jpg?w=300")
    }
}
