import ComposableArchitecture
import Foundation
import Database
import Repositories
import SyncDatabase

/// TCA dependency client for VOD listing queries.
/// Wraps VodRepository + PlaylistRepository for use in reducers.
public struct VodListClient: Sendable {

    public var fetchPlaylists: @Sendable () async throws -> [PlaylistRecord]

    public var fetchMovies: @Sendable (_ playlistID: String) async throws -> [VodItemRecord]

    public var fetchSeries: @Sendable (_ playlistID: String) async throws -> [VodItemRecord]

    public var fetchEpisodes: @Sendable (_ seriesID: String) async throws -> [VodItemRecord]

    public var searchVod: @Sendable (_ query: String, _ playlistID: String?, _ type: String?) async throws -> [VodItemRecord]

    public var fetchGenres: @Sendable (_ playlistID: String, _ type: String) async throws -> [String]

    public var fetchVodItemsByIDs: @Sendable (_ ids: [String]) async throws -> [VodItemRecord]
}

// MARK: - Dependency Registration

extension VodListClient: DependencyKey {
    public static var liveValue: VodListClient {
        let db = SyncDatabaseManager.shared.db
        let vodRepo = SyncVodRepository(db: db)
        let playlistRepo = SyncPlaylistRepository(db: db)
        return VodListClient(
            fetchPlaylists: {
                try await playlistRepo.getAll()
            },
            fetchMovies: { playlistID in
                try await vodRepo.getMovies(playlistID: playlistID)
            },
            fetchSeries: { playlistID in
                try await vodRepo.getSeries(playlistID: playlistID)
            },
            fetchEpisodes: { seriesID in
                try await vodRepo.getEpisodes(seriesID: seriesID)
            },
            searchVod: { query, playlistID, type in
                try await vodRepo.searchVod(query: query, playlistID: playlistID, type: type)
            },
            fetchGenres: { playlistID, type in
                try await vodRepo.getGenres(playlistID: playlistID, type: type)
            },
            fetchVodItemsByIDs: { ids in
                try await vodRepo.getByIDs(ids: ids)
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
            fetchGenres: unimplemented("VodListClient.fetchGenres"),
            fetchVodItemsByIDs: unimplemented("VodListClient.fetchVodItemsByIDs")
        )
    }
}

extension DependencyValues {
    public var vodListClient: VodListClient {
        get { self[VodListClient.self] }
        set { self[VodListClient.self] = newValue }
    }
}
