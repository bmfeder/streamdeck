import CloudKit
import ComposableArchitecture
import Database
import Foundation
import Repositories

/// TCA dependency client for CloudKit sync operations.
/// Wraps CloudKitSyncService for use in reducers.
public struct CloudKitSyncClient: Sendable {

    /// Check if iCloud account is available.
    public var isAvailable: @Sendable () async -> Bool

    /// Pull all synced data from CloudKit. Returns summary of changes.
    public var pullAll: @Sendable () async throws -> SyncPullResult

    /// Push a playlist to CloudKit after add/edit.
    public var pushPlaylist: @Sendable (_ record: PlaylistRecord) async throws -> Void

    /// Push a playlist deletion to CloudKit.
    public var pushPlaylistDeletion: @Sendable (_ playlistID: String) async throws -> Void

    /// Push a favorite toggle to CloudKit.
    public var pushFavorite: @Sendable (_ channelID: String, _ playlistID: String, _ isFavorite: Bool) async throws -> Void

    /// Push watch progress to CloudKit.
    public var pushWatchProgress: @Sendable (_ record: WatchProgressRecord) async throws -> Void

    /// Push user preferences to CloudKit.
    public var pushPreferences: @Sendable (_ prefs: SyncablePreferences) async throws -> Void
}

// MARK: - Dependency Registration

extension CloudKitSyncClient: DependencyKey {
    /// Lazily creates the CKContainer and CloudKitSyncService on first use.
    /// This avoids triggering the entitlements check at app launch when running
    /// in environments without CloudKit (e.g. Simulator without iCloud sign-in).
    private final class LazyService: Sendable {
        private let _service = LockIsolated<CloudKitSyncService?>(nil)
        private let _container = LockIsolated<CKContainer?>(nil)

        var container: CKContainer {
            _container.withValue { value in
                if let c = value { return c }
                let c = CKContainer(identifier: "iCloud.net.lctechnology.StreamDeck")
                value = c
                return c
            }
        }

        var service: CloudKitSyncService {
            _service.withValue { value in
                if let s = value { return s }
                let dbManager = try! DatabaseManager(path: CloudKitSyncClient.databasePath())
                let s = CloudKitSyncService(
                    database: container.privateCloudDatabase,
                    dbManager: dbManager
                )
                value = s
                return s
            }
        }
    }

    public static var liveValue: CloudKitSyncClient {
        let lazy = LazyService()

        return CloudKitSyncClient(
            isAvailable: {
                do {
                    let status = try await lazy.container.accountStatus()
                    return status == .available
                } catch {
                    return false
                }
            },
            pullAll: {
                try await lazy.service.pullAll()
            },
            pushPlaylist: { record in
                try await lazy.service.pushPlaylist(record)
            },
            pushPlaylistDeletion: { playlistID in
                try await lazy.service.pushPlaylistDeletion(playlistID)
            },
            pushFavorite: { channelID, playlistID, isFavorite in
                try await lazy.service.pushFavorite(
                    channelID: channelID, playlistID: playlistID, isFavorite: isFavorite
                )
            },
            pushWatchProgress: { record in
                try await lazy.service.pushWatchProgress(record)
            },
            pushPreferences: { prefs in
                try await lazy.service.pushPreferences(prefs)
            }
        )
    }

    public static var testValue: CloudKitSyncClient {
        CloudKitSyncClient(
            isAvailable: { false },
            pullAll: unimplemented("CloudKitSyncClient.pullAll"),
            pushPlaylist: unimplemented("CloudKitSyncClient.pushPlaylist"),
            pushPlaylistDeletion: unimplemented("CloudKitSyncClient.pushPlaylistDeletion"),
            pushFavorite: unimplemented("CloudKitSyncClient.pushFavorite"),
            pushWatchProgress: unimplemented("CloudKitSyncClient.pushWatchProgress"),
            pushPreferences: unimplemented("CloudKitSyncClient.pushPreferences")
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
    public var cloudKitSyncClient: CloudKitSyncClient {
        get { self[CloudKitSyncClient.self] }
        set { self[CloudKitSyncClient.self] = newValue }
    }
}
