import Foundation
import Database

/// Errors specific to the playlist import orchestration.
public enum PlaylistImportError: Error, Equatable, Sendable {
    case downloadFailed(String)
    case emptyPlaylist
    case authenticationFailed
    case accountExpired
    case networkError(String)
    case playlistNotFound
}

/// Result of importing a playlist (M3U or Xtream) into the database.
public struct PlaylistImportResult: Equatable, Sendable {
    /// The created or updated playlist record.
    public let playlist: PlaylistRecord
    /// Channel import statistics (added, updated, softDeleted, unchanged).
    public let importResult: ImportResult
    /// VOD import statistics (nil if no VOD content found).
    public let vodImportResult: VodImportResult?
    /// Non-fatal parse error summaries (M3U only; empty for Xtream).
    public let parseErrors: [String]

    /// Total channels successfully processed (added + updated + unchanged).
    public var totalChannels: Int {
        importResult.added + importResult.updated + importResult.unchanged
    }

    public init(
        playlist: PlaylistRecord,
        importResult: ImportResult,
        vodImportResult: VodImportResult? = nil,
        parseErrors: [String] = []
    ) {
        self.playlist = playlist
        self.importResult = importResult
        self.vodImportResult = vodImportResult
        self.parseErrors = parseErrors
    }
}
