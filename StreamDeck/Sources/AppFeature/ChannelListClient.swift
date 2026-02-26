import ComposableArchitecture
import Foundation
import Database
import Repositories

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
}

// MARK: - Dependency Registration

extension ChannelListClient: DependencyKey {
    public static var liveValue: ChannelListClient {
        let dbManager = try! DatabaseManager(path: Self.databasePath())
        let channelRepo = ChannelRepository(dbManager: dbManager)
        let playlistRepo = PlaylistRepository(dbManager: dbManager)
        return ChannelListClient(
            fetchPlaylists: {
                try playlistRepo.getAll()
            },
            fetchGroupedChannels: { playlistID in
                let dict = try channelRepo.getActiveGrouped(playlistID: playlistID)
                let sortedGroups = dict.keys.sorted { lhs, rhs in
                    if lhs.isEmpty { return false }
                    if rhs.isEmpty { return true }
                    return lhs.localizedCaseInsensitiveCompare(rhs) == .orderedAscending
                }
                return GroupedChannels(groups: sortedGroups, channelsByGroup: dict)
            },
            searchChannels: { query, playlistID in
                try channelRepo.search(query: query, playlistID: playlistID)
            },
            fetchFavorites: {
                try channelRepo.getFavorites()
            },
            toggleFavorite: { id in
                try channelRepo.toggleFavorite(id: id)
            },
            fetchByNumber: { playlistID, number in
                try channelRepo.getByNumber(playlistID: playlistID, number: number)
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
            fetchByNumber: unimplemented("ChannelListClient.fetchByNumber")
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
    public var channelListClient: ChannelListClient {
        get { self[ChannelListClient.self] }
        set { self[ChannelListClient.self] = newValue }
    }
}
