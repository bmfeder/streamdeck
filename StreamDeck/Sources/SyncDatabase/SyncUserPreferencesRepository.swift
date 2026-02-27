import Foundation
import PowerSync

/// PowerSync-backed user preferences repository.
/// Stores preferences as a singleton row in the `user_preferences` table.
/// Previously stored in UserDefaults, now synced via PowerSync.
public struct SyncUserPreferencesRepository: Sendable {
    private let db: any PowerSyncDatabaseProtocol

    public init(db: any PowerSyncDatabaseProtocol) {
        self.db = db
    }

    /// Load current preferences, returning defaults if no row exists.
    public func load() async throws -> SyncUserPreferences {
        guard let row = try await db.getOptional(
            sql: "SELECT * FROM user_preferences LIMIT 1",
            parameters: [],
            mapper: { cursor in
                SyncUserPreferences(
                    preferredEngine: try cursor.getStringOptional(name: "preferred_engine") ?? "auto",
                    resumePlaybackEnabled: (try cursor.getIntOptional(name: "resume_playback_enabled")) == 1,
                    bufferTimeoutSeconds: (try cursor.getIntOptional(name: "buffer_timeout_seconds")) ?? 10
                )
            }
        ) else {
            return SyncUserPreferences()
        }
        return row
    }

    /// Save preferences. Creates or updates the singleton row.
    public func save(_ prefs: SyncUserPreferences) async throws {
        let existing = try await db.getOptional(
            sql: "SELECT id FROM user_preferences LIMIT 1",
            parameters: []
        ) { cursor in
            try cursor.getString(name: "id")
        }

        let params: [Sendable?] = [
            prefs.preferredEngine,
            prefs.resumePlaybackEnabled ? 1 : 0,
            prefs.bufferTimeoutSeconds,
        ]

        if let existingID = existing {
            try await db.execute(
                sql: """
                    UPDATE user_preferences SET preferred_engine = ?,
                        resume_playback_enabled = ?, buffer_timeout_seconds = ?
                    WHERE id = ?
                    """,
                parameters: params + [existingID]
            )
        } else {
            let newID = UUID().uuidString
            try await db.execute(
                sql: """
                    INSERT INTO user_preferences (id, preferred_engine,
                        resume_playback_enabled, buffer_timeout_seconds)
                    VALUES (?, ?, ?, ?)
                    """,
                parameters: [newID] + params
            )
        }
    }
}

/// User preferences stored in PowerSync.
public struct SyncUserPreferences: Equatable, Sendable {
    public var preferredEngine: String
    public var resumePlaybackEnabled: Bool
    public var bufferTimeoutSeconds: Int

    public init(
        preferredEngine: String = "auto",
        resumePlaybackEnabled: Bool = true,
        bufferTimeoutSeconds: Int = 10
    ) {
        self.preferredEngine = preferredEngine
        self.resumePlaybackEnabled = resumePlaybackEnabled
        self.bufferTimeoutSeconds = bufferTimeoutSeconds
    }
}
