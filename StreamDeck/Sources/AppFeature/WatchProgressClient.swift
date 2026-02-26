import ComposableArchitecture
import Foundation
import Database
import Repositories

/// TCA dependency client for watch progress tracking.
/// Wraps WatchProgressRepository for use in reducers.
public struct WatchProgressClient: Sendable {

    public var saveProgress: @Sendable (_ contentID: String, _ playlistID: String?, _ positionMs: Int, _ durationMs: Int?) async throws -> Void

    public var getProgress: @Sendable (_ contentID: String) async throws -> WatchProgressRecord?

    public var getProgressBatch: @Sendable (_ contentIDs: [String]) async throws -> [String: WatchProgressRecord]

    public var getUnfinished: @Sendable (_ limit: Int) async throws -> [WatchProgressRecord]

    public var deleteProgress: @Sendable (_ contentID: String) async throws -> Void

    public var clearAll: @Sendable () async throws -> Void

    public var getRecentlyWatched: @Sendable (_ limit: Int) async throws -> [WatchProgressRecord]
}

// MARK: - Dependency Registration

extension WatchProgressClient: DependencyKey {
    public static var liveValue: WatchProgressClient {
        let dbManager = try! DatabaseManager(path: Self.databasePath())
        let repo = WatchProgressRepository(dbManager: dbManager)
        return WatchProgressClient(
            saveProgress: { contentID, playlistID, positionMs, durationMs in
                let record = WatchProgressRecord(
                    contentID: contentID,
                    playlistID: playlistID,
                    positionMs: positionMs,
                    durationMs: durationMs,
                    updatedAt: Int(Date().timeIntervalSince1970)
                )
                try repo.upsert(record)
            },
            getProgress: { contentID in
                try repo.get(contentID: contentID)
            },
            getProgressBatch: { contentIDs in
                try repo.getBatch(contentIDs: contentIDs)
            },
            getUnfinished: { limit in
                try repo.getUnfinished(limit: limit)
            },
            deleteProgress: { contentID in
                try repo.delete(contentID: contentID)
            },
            clearAll: {
                try repo.deleteAll()
            },
            getRecentlyWatched: { limit in
                try repo.getRecentlyWatched(limit: limit)
            }
        )
    }

    public static var testValue: WatchProgressClient {
        WatchProgressClient(
            saveProgress: unimplemented("WatchProgressClient.saveProgress"),
            getProgress: unimplemented("WatchProgressClient.getProgress"),
            getProgressBatch: unimplemented("WatchProgressClient.getProgressBatch"),
            getUnfinished: unimplemented("WatchProgressClient.getUnfinished"),
            deleteProgress: unimplemented("WatchProgressClient.deleteProgress"),
            clearAll: unimplemented("WatchProgressClient.clearAll"),
            getRecentlyWatched: unimplemented("WatchProgressClient.getRecentlyWatched")
        )
    }

    private static func databasePath() -> String {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first!
        let dir = appSupport.appendingPathComponent("StreamDeck", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("streamdeck.db").path
    }
}

extension DependencyValues {
    public var watchProgressClient: WatchProgressClient {
        get { self[WatchProgressClient.self] }
        set { self[WatchProgressClient.self] = newValue }
    }
}
