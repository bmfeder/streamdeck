import ComposableArchitecture
import Foundation
import Database
import Repositories
import SyncDatabase

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
        let db = SyncDatabaseManager.shared.db
        let repo = SyncWatchProgressRepository(db: db)
        return WatchProgressClient(
            saveProgress: { contentID, playlistID, positionMs, durationMs in
                let record = WatchProgressRecord(
                    contentID: contentID,
                    playlistID: playlistID,
                    positionMs: positionMs,
                    durationMs: durationMs,
                    updatedAt: Int(Date().timeIntervalSince1970)
                )
                try await repo.upsert(record)
            },
            getProgress: { contentID in
                try await repo.get(contentID: contentID)
            },
            getProgressBatch: { contentIDs in
                try await repo.getBatch(contentIDs: contentIDs)
            },
            getUnfinished: { limit in
                try await repo.getUnfinished(limit: limit)
            },
            deleteProgress: { contentID in
                try await repo.delete(contentID: contentID)
            },
            clearAll: {
                try await repo.deleteAll()
            },
            getRecentlyWatched: { limit in
                try await repo.getRecentlyWatched(limit: limit)
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
}

extension DependencyValues {
    public var watchProgressClient: WatchProgressClient {
        get { self[WatchProgressClient.self] }
        set { self[WatchProgressClient.self] = newValue }
    }
}
