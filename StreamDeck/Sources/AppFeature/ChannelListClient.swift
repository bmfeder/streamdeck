import ComposableArchitecture
import Foundation
import Database
import Repositories
import SyncDatabase

/// Grouped channels with sorted group names for UI rendering.
public struct GroupedChannels: Equatable, Sendable {
    public let groups: [String]
    public let channelsByGroup: [String: [ChannelRecord]]

    public var allChannels: [ChannelRecord] {
        groups.flatMap { channelsByGroup[$0] ?? [] }
    }

    public init(groups: [String], channelsByGroup: [String: [ChannelRecord]]) {
        self.groups = groups
        self.channelsByGroup = channelsByGroup
    }
}

/// TCA dependency client for channel listing and playlist queries.
/// Wraps ChannelRepository + PlaylistRepository for use in reducers.
public struct ChannelListClient: Sendable {

    public var fetchPlaylists: @Sendable () async throws -> [PlaylistRecord]

    public var fetchGroupedChannels: @Sendable (_ playlistID: String) async throws -> GroupedChannels

    public var searchChannels: @Sendable (_ query: String, _ playlistID: String?) async throws -> [ChannelRecord]

    public var fetchFavorites: @Sendable () async throws -> [ChannelRecord]

    public var toggleFavorite: @Sendable (_ id: String) async throws -> Void

    public var fetchByNumber: @Sendable (_ playlistID: String, _ number: Int) async throws -> ChannelRecord?

    public var fetchByIDs: @Sendable (_ ids: [String]) async throws -> [ChannelRecord]

    public var fetchByEpgID: @Sendable (_ epgID: String) async throws -> ChannelRecord?
}

// MARK: - Dependency Registration

extension ChannelListClient: DependencyKey {
    public static var liveValue: ChannelListClient {
        let db = SyncDatabaseManager.shared.db
        let channelRepo = SyncChannelRepository(db: db)
        let playlistRepo = SyncPlaylistRepository(db: db)
        return ChannelListClient(
            fetchPlaylists: {
                try await playlistRepo.getAll()
            },
            fetchGroupedChannels: { playlistID in
                let channels = try await channelRepo.getActive(playlistID: playlistID)
                let dict = Dictionary(grouping: channels) { $0.groupName ?? "" }
                let sortedGroups = dict.keys.sorted { lhs, rhs in
                    if lhs.isEmpty { return false }
                    if rhs.isEmpty { return true }
                    return lhs.localizedCaseInsensitiveCompare(rhs) == .orderedAscending
                }
                return GroupedChannels(groups: sortedGroups, channelsByGroup: dict)
            },
            searchChannels: { query, playlistID in
                try await channelRepo.search(query: query, playlistID: playlistID)
            },
            fetchFavorites: {
                try await channelRepo.getFavorites()
            },
            toggleFavorite: { id in
                try await channelRepo.toggleFavorite(id: id)
            },
            fetchByNumber: { playlistID, number in
                try await channelRepo.getByNumber(playlistID: playlistID, number: number)
            },
            fetchByIDs: { ids in
                try await channelRepo.getBatch(ids: ids)
            },
            fetchByEpgID: { epgID in
                try await channelRepo.getByEpgID(epgID)
            }
        )
    }

    public static var testValue: ChannelListClient {
        ChannelListClient(
            fetchPlaylists: unimplemented("ChannelListClient.fetchPlaylists"),
            fetchGroupedChannels: unimplemented("ChannelListClient.fetchGroupedChannels"),
            searchChannels: unimplemented("ChannelListClient.searchChannels"),
            fetchFavorites: unimplemented("ChannelListClient.fetchFavorites"),
            toggleFavorite: unimplemented("ChannelListClient.toggleFavorite"),
            fetchByNumber: unimplemented("ChannelListClient.fetchByNumber"),
            fetchByIDs: unimplemented("ChannelListClient.fetchByIDs"),
            fetchByEpgID: unimplemented("ChannelListClient.fetchByEpgID")
        )
    }
}

extension DependencyValues {
    public var channelListClient: ChannelListClient {
        get { self[ChannelListClient.self] }
        set { self[ChannelListClient.self] = newValue }
    }
}
