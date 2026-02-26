import Foundation

/// Preferences that can be synced via CloudKit.
/// Decoupled from TCA UserPreferences to keep Repositories module dependency-free.
public struct SyncablePreferences: Equatable, Sendable {
    public let preferredEngine: String
    public let resumePlaybackEnabled: Bool
    public let bufferTimeoutSeconds: Int
    public let updatedAt: Int

    public init(
        preferredEngine: String,
        resumePlaybackEnabled: Bool,
        bufferTimeoutSeconds: Int,
        updatedAt: Int
    ) {
        self.preferredEngine = preferredEngine
        self.resumePlaybackEnabled = resumePlaybackEnabled
        self.bufferTimeoutSeconds = bufferTimeoutSeconds
        self.updatedAt = updatedAt
    }
}
