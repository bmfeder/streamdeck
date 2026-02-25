import Database
import Foundation
import GRDB

public struct EpgRepository: Sendable {
    private let dbManager: DatabaseManager

    public init(dbManager: DatabaseManager) {
        self.dbManager = dbManager
    }

    // MARK: - Batch Upsert

    public func importPrograms(_ programs: [EpgProgramRecord]) throws -> Int {
        try dbManager.dbQueue.write { db in
            var count = 0
            for program in programs {
                try program.save(db)
                count += 1
            }
            return count
        }
    }

    // MARK: - Time-Based Queries

    public func getCurrentProgram(channelEpgID: String, at: Int) throws -> EpgProgramRecord? {
        try dbManager.dbQueue.read { db in
            try EpgProgramRecord
                .filter(Column("channel_epg_id") == channelEpgID)
                .filter(Column("start_time") <= at)
                .filter(Column("end_time") > at)
                .order(Column("start_time").desc)
                .fetchOne(db)
        }
    }

    public func getNextProgram(channelEpgID: String, after: Int) throws -> EpgProgramRecord? {
        try dbManager.dbQueue.read { db in
            try EpgProgramRecord
                .filter(Column("channel_epg_id") == channelEpgID)
                .filter(Column("start_time") > after)
                .order(Column("start_time").asc)
                .fetchOne(db)
        }
    }

    public func getPrograms(channelEpgID: String, from: Int, to: Int) throws -> [EpgProgramRecord] {
        try dbManager.dbQueue.read { db in
            try EpgProgramRecord
                .filter(Column("channel_epg_id") == channelEpgID)
                .filter(Column("start_time") >= from)
                .filter(Column("start_time") < to)
                .order(Column("start_time").asc)
                .fetchAll(db)
        }
    }

    // MARK: - Purge

    @discardableResult
    public func purgeOldPrograms(olderThan: Int) throws -> Int {
        try dbManager.dbQueue.write { db in
            try EpgProgramRecord
                .filter(Column("end_time") < olderThan)
                .deleteAll(db)
        }
    }

    // MARK: - Count

    public func count() throws -> Int {
        try dbManager.dbQueue.read { db in
            try EpgProgramRecord.fetchCount(db)
        }
    }

    public func count(channelEpgID: String) throws -> Int {
        try dbManager.dbQueue.read { db in
            try EpgProgramRecord
                .filter(Column("channel_epg_id") == channelEpgID)
                .fetchCount(db)
        }
    }
}
