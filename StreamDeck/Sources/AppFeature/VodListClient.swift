import ComposableArchitecture
import Foundation
import Database
import Repositories

/// TCA dependency client for VOD listing queries.
/// Wraps VodRepository + PlaylistRepository for use in reducers.
public struct VodListClient: Sendable {

    public var fetchPlaylists: @Sendable () async throws -> [PlaylistRecord]

    public var fetchMovies: @Sendable (_ playlistID: String) async throws -> [VodItemRecord]

    public var fetchSeries: @Sendable (_ playlistID: String) async throws -> [VodItemRecord]

    public var fetchEpisodes: @Sendable (_ seriesID: String) async throws -> [VodItemRecord]

    public var searchVod: @Sendable (_ query: String, _ playlistID: String?, _ type: String?) async throws -> [VodItemRecord]

    public var fetchGenres: @Sendable (_ playlistID: String, _ type: String) async throws -> [String]
}

// MARK: - Dependency Registration

extension VodListClient: DependencyKey {
    public static var liveValue: VodListClient {
        let dbManager = try! DatabaseManager(path: Self.databasePath())
        let vodRepo = VodRepository(dbManager: dbManager)
        let playlistRepo = PlaylistRepository(dbManager: dbManager)
        return VodListClient(
            fetchPlaylists: {
                try playlistRepo.getAll()
            },
            fetchMovies: { playlistID in
                try vodRepo.getMovies(playlistID: playlistID)
            },
            fetchSeries: { playlistID in
                try vodRepo.getSeries(playlistID: playlistID)
            },
            fetchEpisodes: { seriesID in
                try vodRepo.getEpisodes(seriesID: seriesID)
            },
            searchVod: { query, playlistID, type in
                try vodRepo.searchVod(query: query, playlistID: playlistID, type: type)
            },
            fetchGenres: { playlistID, type in
                try vodRepo.getGenres(playlistID: playlistID, type: type)
            }
        )
    }

    public static var testValue: VodListClient {
        VodListClient(
            fetchPlaylists: unimplemented("VodListClient.fetchPlaylists"),
            fetchMovies: unimplemented("VodListClient.fetchMovies"),
            fetchSeries: unimplemented("VodListClient.fetchSeries"),
            fetchEpisodes: unimplemented("VodListClient.fetchEpisodes"),
            searchVod: unimplemented("VodListClient.searchVod"),
            fetchGenres: unimplemented("VodListClient.fetchGenres")
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
    public var vodListClient: VodListClient {
        get { self[VodListClient.self] }
        set { self[VodListClient.self] = newValue }
    }
}
