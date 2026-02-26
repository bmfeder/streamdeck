import Foundation

/// Result of a CloudKit sync pull operation.
public struct SyncPullResult: Equatable, Sendable {
    public let playlistsUpdated: Int
    public let favoritesUpdated: Int
    public let progressUpdated: Int
    public let preferencesUpdated: Bool

    public init(
        playlistsUpdated: Int = 0,
        favoritesUpdated: Int = 0,
        progressUpdated: Int = 0,
        preferencesUpdated: Bool = false
    ) {
        self.playlistsUpdated = playlistsUpdated
        self.favoritesUpdated = favoritesUpdated
        self.progressUpdated = progressUpdated
        self.preferencesUpdated = preferencesUpdated
    }
}
