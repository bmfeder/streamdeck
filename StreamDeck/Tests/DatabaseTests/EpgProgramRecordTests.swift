import XCTest
import GRDB
@testable import Database

final class EpgProgramRecordTests: DatabaseTestCase {

    func testInsertAndFetch() throws {
        let program = EpgProgramRecord(
            id: "epg-1", channelEpgID: "bbc.uk", title: "News at 10",
            startTime: 1700000000, endTime: 1700003600
        )
        try dbManager.dbQueue.write { db in try program.insert(db) }

        let fetched = try dbManager.dbQueue.read { db in
            try EpgProgramRecord.fetchOne(db, key: "epg-1")
        }
        XCTAssertEqual(fetched, program)
    }

    func testUpsert_replacesExisting() throws {
        let original = EpgProgramRecord(
            id: "epg-1", channelEpgID: "bbc.uk", title: "Original Title",
            startTime: 1700000000, endTime: 1700003600
        )
        try dbManager.dbQueue.write { db in try original.insert(db) }

        // Update via save (INSERT OR REPLACE by primary key)
        let updated = EpgProgramRecord(
            id: "epg-1", channelEpgID: "bbc.uk", title: "Updated Title",
            startTime: 1700000000, endTime: 1700003600
        )
        try dbManager.dbQueue.write { db in try updated.save(db) }

        let fetched = try dbManager.dbQueue.read { db in
            try XCTUnwrap(EpgProgramRecord.fetchOne(db, key: "epg-1"))
        }
        XCTAssertEqual(fetched.title, "Updated Title")

        let count = try dbManager.dbQueue.read { db in try EpgProgramRecord.fetchCount(db) }
        XCTAssertEqual(count, 1)
    }

    func testUniqueConstraint_channelAndStartTime() throws {
        let p1 = EpgProgramRecord(
            id: "epg-1", channelEpgID: "bbc.uk", title: "Show A",
            startTime: 1700000000, endTime: 1700003600
        )
        let p2 = EpgProgramRecord(
            id: "epg-2", channelEpgID: "bbc.uk", title: "Show B",
            startTime: 1700000000, endTime: 1700003600
        )
        try dbManager.dbQueue.write { db in try p1.insert(db) }

        // Inserting a different ID with same (channel_epg_id, start_time) should fail
        XCTAssertThrowsError(try dbManager.dbQueue.write { db in
            try p2.insert(db)
        })
    }

    func testTimeRangeQuery() throws {
        let programs = [
            EpgProgramRecord(id: "e1", channelEpgID: "ch1", title: "Morning", startTime: 1000, endTime: 2000),
            EpgProgramRecord(id: "e2", channelEpgID: "ch1", title: "Noon", startTime: 2000, endTime: 3000),
            EpgProgramRecord(id: "e3", channelEpgID: "ch1", title: "Evening", startTime: 3000, endTime: 4000),
            EpgProgramRecord(id: "e4", channelEpgID: "ch2", title: "Other", startTime: 1000, endTime: 2000),
        ]
        try dbManager.dbQueue.write { db in
            for p in programs { try p.insert(db) }
        }

        // Query: ch1 programs overlapping with range 1500..2500
        let results = try dbManager.dbQueue.read { db in
            try EpgProgramRecord
                .filter(Column("channel_epg_id") == "ch1")
                .filter(Column("start_time") < 2500 && Column("end_time") > 1500)
                .order(Column("start_time"))
                .fetchAll(db)
        }
        XCTAssertEqual(results.map(\.title), ["Morning", "Noon"])
    }

    func testFetchByChannel() throws {
        let p1 = EpgProgramRecord(id: "e1", channelEpgID: "ch1", title: "A", startTime: 1000, endTime: 2000)
        let p2 = EpgProgramRecord(id: "e2", channelEpgID: "ch2", title: "B", startTime: 1000, endTime: 2000)
        try dbManager.dbQueue.write { db in
            try p1.insert(db)
            try p2.insert(db)
        }

        let ch1Programs = try dbManager.dbQueue.read { db in
            try EpgProgramRecord
                .filter(Column("channel_epg_id") == "ch1")
                .fetchAll(db)
        }
        XCTAssertEqual(ch1Programs.count, 1)
        XCTAssertEqual(ch1Programs.first?.title, "A")
    }

    func testAllFieldsPersist() throws {
        let program = EpgProgramRecord(
            id: "full-epg",
            channelEpgID: "bbc.uk",
            title: "Full Program",
            description: "A detailed description",
            startTime: 1700000000,
            endTime: 1700003600,
            category: "News",
            iconURL: "http://x.com/icon.png"
        )
        try dbManager.dbQueue.write { db in try program.insert(db) }
        let fetched = try dbManager.dbQueue.read { db in
            try XCTUnwrap(EpgProgramRecord.fetchOne(db, key: "full-epg"))
        }
        XCTAssertEqual(fetched, program)
    }

    func testNoForeignKeyToChannel() throws {
        // EPG programs use channel_epg_id (string), not FK to channel table
        // Should insert fine without any channel record existing
        let program = EpgProgramRecord(
            id: "epg-orphan", channelEpgID: "nonexistent-channel",
            title: "Show", startTime: 1000, endTime: 2000
        )
        XCTAssertNoThrow(try dbManager.dbQueue.write { db in
            try program.insert(db)
        })
    }
}
