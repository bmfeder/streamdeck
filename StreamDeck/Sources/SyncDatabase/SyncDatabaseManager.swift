import Foundation
import PowerSync

/// Manages the PowerSync database instance and connection lifecycle.
/// Used for synced tables: playlists, channels, vod_items, watch_progress, user_preferences.
/// EPG data remains in GRDB (local-only, not synced).
public final class SyncDatabaseManager: @unchecked Sendable {
    public let db: any PowerSyncDatabaseProtocol

    /// Shared instance used by all TCA client liveValues.
    public static let shared = SyncDatabaseManager()

    public init(dbFilename: String = "streamdeck-sync.sqlite") {
        self.db = PowerSyncDatabase(
            schema: syncSchema,
            dbFilename: dbFilename
        )
    }

    /// Connect to PowerSync service with the given backend connector.
    /// After connecting, all local writes are automatically synced.
    public func connect(connector: any PowerSyncBackendConnectorProtocol) async throws {
        try await db.connect(connector: connector)
    }

    /// Disconnect from PowerSync. Local data is preserved.
    public func disconnect() async throws {
        try await db.disconnect()
    }

    /// The current sync status.
    public var currentStatus: SyncStatus {
        db.currentStatus
    }
}
