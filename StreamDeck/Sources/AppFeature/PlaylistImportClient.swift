import ComposableArchitecture
import Foundation
import Database
import Repositories

/// TCA dependency client for playlist import operations.
/// Wraps PlaylistImportService for use in reducers.
public struct PlaylistImportClient: Sendable {

    /// Import an M3U playlist from a URL.
    public var importM3U: @Sendable (
        _ url: URL,
        _ name: String,
        _ epgURL: URL?
    ) async throws -> PlaylistImportResult

    /// Import an Xtream Codes account.
    public var importXtream: @Sendable (
        _ serverURL: URL,
        _ username: String,
        _ password: String,
        _ name: String
    ) async throws -> PlaylistImportResult
}

// MARK: - Dependency Registration

extension PlaylistImportClient: DependencyKey {
    public static var liveValue: PlaylistImportClient {
        let dbManager = try! DatabaseManager(path: Self.databasePath())
        let service = PlaylistImportService(
            playlistRepo: PlaylistRepository(dbManager: dbManager),
            channelRepo: ChannelRepository(dbManager: dbManager),
            vodRepo: VodRepository(dbManager: dbManager)
        )
        return PlaylistImportClient(
            importM3U: { url, name, epgURL in
                try await service.importM3U(url: url, name: name, epgURL: epgURL)
            },
            importXtream: { serverURL, username, password, name in
                try await service.importXtream(
                    serverURL: serverURL,
                    username: username,
                    password: password,
                    name: name
                )
            }
        )
    }

    public static var testValue: PlaylistImportClient {
        PlaylistImportClient(
            importM3U: unimplemented("PlaylistImportClient.importM3U"),
            importXtream: unimplemented("PlaylistImportClient.importXtream")
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
    public var playlistImportClient: PlaylistImportClient {
        get { self[PlaylistImportClient.self] }
        set { self[PlaylistImportClient.self] = newValue }
    }
}
