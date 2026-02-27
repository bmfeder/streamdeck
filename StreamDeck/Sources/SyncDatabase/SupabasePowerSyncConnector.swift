import Foundation
import PowerSync
import Supabase

/// PowerSync backend connector that uses Supabase for auth and data upload.
/// Mirrors the web connector at `web/app/lib/connector.ts`.
public struct SupabasePowerSyncConnector: PowerSyncBackendConnectorProtocol, Sendable {
    private let supabase: SupabaseClient
    private let powersyncURL: String

    /// Tables that require user_id injection on PUT operations.
    private static let tablesWithUserID: Set<String> = [
        "playlists", "channels", "vod_items", "watch_progress", "user_preferences",
    ]

    public init(supabase: SupabaseClient, powersyncURL: String) {
        self.supabase = supabase
        self.powersyncURL = powersyncURL
    }

    public func fetchCredentials() async throws -> PowerSyncCredentials? {
        let session = try await supabase.auth.session
        return PowerSyncCredentials(
            endpoint: powersyncURL,
            token: session.accessToken
        )
    }

    public func uploadData(database: PowerSyncDatabaseProtocol) async throws {
        guard let batch = try await database.getCrudBatch() else { return }

        let session = try await supabase.auth.session
        let userId = session.user.id.uuidString

        for op in batch.crud {
            let table = op.table
            let id = op.id
            var opData = op.opData ?? [:]

            // Inject user_id for inserts on tables that need it
            if op.op == .put && Self.tablesWithUserID.contains(table) {
                opData["user_id"] = userId
            }

            switch op.op {
            case .put:
                var record: [String: String?] = opData
                record["id"] = id
                try await supabase.from(table).upsert(record).execute()
            case .patch:
                try await supabase.from(table).update(opData).eq("id", value: id).execute()
            case .delete:
                try await supabase.from(table).delete().eq("id", value: id).execute()
            }
        }

        try await batch.complete(writeCheckpoint: nil)
    }
}
