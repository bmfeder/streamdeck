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
    public static var liveValue: CloudKitSyncClient {
        let container = CKContainer(identifier: "iCloud.net.lctechnology.StreamDeck")
        let dbManager = try! DatabaseManager(path: Self.databasePath())
        let service = CloudKitSyncService(
            database: container.privateCloudDatabase,
            dbManager: dbManager
        )

        return CloudKitSyncClient(
            isAvailable: {
                await CloudKitSyncService.checkAccountStatus(container: container)
            },
            pullAll: {
                try await service.pullAll()
            },
            pushPlaylist: { record in
                try await service.pushPlaylist(record)
            },
            pushPlaylistDeletion: { playlistID in
                try await service.pushPlaylistDeletion(playlistID)
            },
            pushFavorite: { channelID, playlistID, isFavorite in
                try await service.pushFavorite(
                    channelID: channelID, playlistID: playlistID, isFavorite: isFavorite
                )
            },
            pushWatchProgress: { record in
                try await service.pushWatchProgress(record)
            },
            pushPreferences: { prefs in
                try await service.pushPreferences(prefs)
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
