import XCTest
import GRDB
@testable import Database

final class MigrationTests: DatabaseTestCase {

    // MARK: - Table Existence

    func testMigration_createsAllTables() throws {
        try dbManager.dbQueue.read { db in
            XCTAssertTrue(try db.tableExists("playlist"))
            XCTAssertTrue(try db.tableExists("channel"))
            XCTAssertTrue(try db.tableExists("vod_item"))
            XCTAssertTrue(try db.tableExists("watch_progress"))
            XCTAssertTrue(try db.tableExists("epg_program"))
        }
    }

    // MARK: - Column Verification

    func testPlaylistTable_hasExpectedColumns() throws {
        try dbManager.dbQueue.read { db in
            let columns = try db.columns(in: "playlist")
            let names = columns.map(\.name)
            XCTAssertTrue(names.contains("id"))
            XCTAssertTrue(names.contains("name"))
            XCTAssertTrue(names.contains("type"))
            XCTAssertTrue(names.contains("url"))
            XCTAssertTrue(names.contains("username"))
            XCTAssertTrue(names.contains("password_ref"))
            XCTAssertTrue(names.contains("epg_url"))
            XCTAssertTrue(names.contains("refresh_hrs"))
            XCTAssertTrue(names.contains("last_sync"))
            XCTAssertTrue(names.contains("last_epg_sync"))
            XCTAssertTrue(names.contains("last_sync_etag"))
            XCTAssertTrue(names.contains("last_sync_hash"))
            XCTAssertTrue(names.contains("is_active"))
            XCTAssertTrue(names.contains("sort_order"))
        }
    }

    func testChannelTable_hasExpectedColumns() throws {
        try dbManager.dbQueue.read { db in
            let columns = try db.columns(in: "channel")
            let names = columns.map(\.name)
            XCTAssertTrue(names.contains("id"))
            XCTAssertTrue(names.contains("playlist_id"))
            XCTAssertTrue(names.contains("source_channel_id"))
            XCTAssertTrue(names.contains("name"))
            XCTAssertTrue(names.contains("stream_url"))
            XCTAssertTrue(names.contains("is_favorite"))
            XCTAssertTrue(names.contains("is_deleted"))
            XCTAssertTrue(names.contains("deleted_at"))
        }
    }

    func testEpgProgramTable_hasExpectedColumns() throws {
        try dbManager.dbQueue.read { db in
            let columns = try db.columns(in: "epg_program")
            let names = columns.map(\.name)
            XCTAssertTrue(names.contains("id"))
            XCTAssertTrue(names.contains("channel_epg_id"))
            XCTAssertTrue(names.contains("title"))
            XCTAssertTrue(names.contains("start_time"))
            XCTAssertTrue(names.contains("end_time"))
        }
    }

    // MARK: - Indexes

    func testMigration_createsExpectedIndexes() throws {
        try dbManager.dbQueue.read { db in
            let indexes = try db.indexes(on: "channel")
            let indexNames = indexes.map(\.name)
            XCTAssertTrue(indexNames.contains("idx_channel_playlist"))
            XCTAssertTrue(indexNames.contains("idx_channel_source"))
            XCTAssertTrue(indexNames.contains("idx_channel_number"))
            XCTAssertTrue(indexNames.contains("idx_channel_tvg"))
            XCTAssertTrue(indexNames.contains("idx_channel_favorite"))
            XCTAssertTrue(indexNames.contains("idx_channel_active"))
        }
    }

    func testMigration_createsEpgIndex() throws {
        try dbManager.dbQueue.read { db in
            let indexes = try db.indexes(on: "epg_program")
            let indexNames = indexes.map(\.name)
            XCTAssertTrue(indexNames.contains("idx_epg_channel_time"))
        }
    }

    func testMigration_createsVodIndex() throws {
        try dbManager.dbQueue.read { db in
            let indexes = try db.indexes(on: "vod_item")
            let indexNames = indexes.map(\.name)
            XCTAssertTrue(indexNames.contains("idx_vod_type"))
        }
    }

    func testMigration_createsProgressIndex() throws {
        try dbManager.dbQueue.read { db in
            let indexes = try db.indexes(on: "watch_progress")
            let indexNames = indexes.map(\.name)
            XCTAssertTrue(indexNames.contains("idx_progress_updated"))
        }
    }

    // MARK: - Foreign Keys

    func testForeignKeysEnabled() throws {
        try dbManager.dbQueue.read { db in
            let fkEnabled = try Bool.fetchOne(db, sql: "PRAGMA foreign_keys")
            XCTAssertEqual(fkEnabled, true)
        }
    }
}
