import Foundation

/// Configuration for Supabase and PowerSync connections.
/// Values are loaded from environment or plist at runtime.
public struct SyncConfig: Sendable {
    public let supabaseURL: String
    public let supabaseAnonKey: String
    public let powersyncURL: String

    public init(supabaseURL: String, supabaseAnonKey: String, powersyncURL: String) {
        self.supabaseURL = supabaseURL
        self.supabaseAnonKey = supabaseAnonKey
        self.powersyncURL = powersyncURL
    }

    /// Load config from Info.plist custom keys.
    public static func fromInfoPlist() -> SyncConfig? {
        guard let supabaseURL = Bundle.main.infoDictionary?["SUPABASE_URL"] as? String,
              let supabaseAnonKey = Bundle.main.infoDictionary?["SUPABASE_ANON_KEY"] as? String,
              let powersyncURL = Bundle.main.infoDictionary?["POWERSYNC_URL"] as? String,
              !supabaseURL.isEmpty, !supabaseAnonKey.isEmpty, !powersyncURL.isEmpty
        else {
            return nil
        }
        return SyncConfig(
            supabaseURL: supabaseURL,
            supabaseAnonKey: supabaseAnonKey,
            powersyncURL: powersyncURL
        )
    }
}
