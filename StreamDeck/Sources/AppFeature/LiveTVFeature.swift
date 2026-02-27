import ComposableArchitecture
import Database
import Repositories
import SwiftUI

@Reducer
public struct LiveTVFeature {

    @ObservableState
    public struct State: Equatable, Sendable {
        public var playlists: [PlaylistRecord] = []
        public var selectedPlaylistID: String?
        public var groupedChannels: GroupedChannels?
        public var groups: [String] = []
        public var selectedGroup: String = "All"
        public var displayedChannels: [ChannelRecord] = []

        public var searchQuery: String = ""
        public var searchResults: [ChannelRecord]?

        public var isLoading: Bool = false
        public var errorMessage: String?
        public var focusedChannelID: String?

        public var nowPlaying: [String: String] = [:]

        @Presents public var videoPlayer: VideoPlayerFeature.State?

        public var isSearching: Bool { !searchQuery.isEmpty }

        public init() {}
    }

    public enum Action: Sendable {
        case onAppear
        case playlistsLoaded(Result<[PlaylistRecord], Error>)
        case channelsLoaded(Result<GroupedChannels, Error>)
        case playlistSelected(String)
        case groupSelected(String)
        case searchQueryChanged(String)
        case searchResultsLoaded(Result<[ChannelRecord], Error>)
        case channelTapped(ChannelRecord)
        case toggleFavoriteTapped(String)
        case favoriteToggled(Result<String, Error>)
        case refreshTapped
        case retryTapped
        case epgDataLoaded(Result<[String: String], Error>)
        case epgSyncCompleted(Result<EpgImportResult, Error>)
        case videoPlayer(PresentationAction<VideoPlayerFeature.Action>)
        case delegate(Delegate)

        @CasePathable
        public enum Delegate: Sendable, Equatable {
            case playChannel(ChannelRecord)
        }
    }

    @Dependency(\.channelListClient) var channelListClient
    @Dependency(\.epgClient) var epgClient
    @Dependency(\.cloudKitSyncClient) var cloudKitSyncClient

    public init() {}

    private enum CancelID {
        case search
    }

    public var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .videoPlayer(.presented(.delegate(.dismissed))):
                state.videoPlayer = nil
                return .none

            case let .videoPlayer(.presented(.delegate(.channelSwitched(channel)))):
                state.focusedChannelID = channel.id
                return .none

            case .videoPlayer:
                return .none
            case .onAppear:
                guard state.playlists.isEmpty else { return .none }
                return loadPlaylists(&state)

            case .refreshTapped:
                state.playlists = []
                state.groupedChannels = nil
                state.groups = []
                state.selectedGroup = "All"
                state.displayedChannels = []
                state.searchQuery = ""
                state.searchResults = nil
                state.nowPlaying = [:]
                state.errorMessage = nil
                return loadPlaylists(&state)

            case let .playlistsLoaded(.success(playlists)):
                state.playlists = playlists
                if let first = playlists.first {
                    state.selectedPlaylistID = first.id
                    var effects: [Effect<Action>] = [loadChannels(playlistID: first.id)]
                    if first.epgURL != nil {
                        effects.append(syncEPG(playlistID: first.id))
                    }
                    return .merge(effects)
                }
                state.isLoading = false
                return .none

            case let .playlistsLoaded(.failure(error)):
                state.isLoading = false
                state.errorMessage = "Failed to load playlists: \(error.localizedDescription)"
                return .none

            case let .channelsLoaded(.success(grouped)):
                state.isLoading = false
                state.groupedChannels = grouped
                state.groups = ["All"] + grouped.groups
                state.selectedGroup = "All"
                state.displayedChannels = grouped.allChannels
                state.errorMessage = nil
                return fetchEPGData(for: grouped.allChannels)

            case let .channelsLoaded(.failure(error)):
                state.isLoading = false
                state.errorMessage = "Failed to load channels: \(error.localizedDescription)"
                return .none

            case let .playlistSelected(playlistID):
                guard playlistID != state.selectedPlaylistID else { return .none }
                state.selectedPlaylistID = playlistID
                state.searchQuery = ""
                state.searchResults = nil
                state.isLoading = true
                return loadChannels(playlistID: playlistID)

            case let .groupSelected(group):
                state.selectedGroup = group
                guard let grouped = state.groupedChannels else { return .none }
                if group == "All" {
                    state.displayedChannels = grouped.allChannels
                } else {
                    state.displayedChannels = grouped.channelsByGroup[group] ?? []
                }
                return .none

            case let .searchQueryChanged(query):
                state.searchQuery = query
                if query.isEmpty {
                    state.searchResults = nil
                    return .send(.groupSelected(state.selectedGroup))
                }
                let client = channelListClient
                let playlistID = state.selectedPlaylistID
                return .run { send in
                    let results = try await client.searchChannels(query, playlistID)
                    await send(.searchResultsLoaded(.success(results)))
                } catch: { error, send in
                    await send(.searchResultsLoaded(.failure(error)))
                }
                .cancellable(id: CancelID.search, cancelInFlight: true)

            case let .searchResultsLoaded(.success(results)):
                state.searchResults = results
                state.displayedChannels = results
                return .none

            case .searchResultsLoaded(.failure):
                state.searchResults = []
                state.displayedChannels = []
                return .none

            case let .channelTapped(channel):
                state.focusedChannelID = channel.id
                state.videoPlayer = VideoPlayerFeature.State(channel: channel)
                return .send(.delegate(.playChannel(channel)))

            case let .toggleFavoriteTapped(channelID):
                let client = channelListClient
                return .run { send in
                    try await client.toggleFavorite(channelID)
                    await send(.favoriteToggled(.success(channelID)))
                } catch: { error, send in
                    await send(.favoriteToggled(.failure(error)))
                }

            case let .favoriteToggled(.success(channelID)):
                if let index = state.displayedChannels.firstIndex(where: { $0.id == channelID }) {
                    state.displayedChannels[index].isFavorite.toggle()
                }
                if let grouped = state.groupedChannels {
                    var updatedDict = grouped.channelsByGroup
                    for (group, channels) in updatedDict {
                        if let idx = channels.firstIndex(where: { $0.id == channelID }) {
                            updatedDict[group]?[idx].isFavorite.toggle()
                        }
                    }
                    state.groupedChannels = GroupedChannels(
                        groups: grouped.groups,
                        channelsByGroup: updatedDict
                    )
                }
                let channel = state.displayedChannels.first { $0.id == channelID }
                let sync = cloudKitSyncClient
                if let channel {
                    return .run { _ in
                        try? await sync.pushFavorite(channel.id, channel.playlistID, channel.isFavorite)
                    }
                }
                return .none

            case .favoriteToggled(.failure):
                return .none

            case .retryTapped:
                state.errorMessage = nil
                state.isLoading = true
                if let playlistID = state.selectedPlaylistID {
                    return loadChannels(playlistID: playlistID)
                }
                let client = channelListClient
                return .run { send in
                    let playlists = try await client.fetchPlaylists()
                    await send(.playlistsLoaded(.success(playlists)))
                } catch: { error, send in
                    await send(.playlistsLoaded(.failure(error)))
                }

            case let .epgDataLoaded(.success(nowPlaying)):
                state.nowPlaying.merge(nowPlaying) { _, new in new }
                return .none

            case .epgDataLoaded(.failure):
                return .none

            case .epgSyncCompleted(.success):
                let channels = state.displayedChannels
                return fetchEPGData(for: channels)

            case .epgSyncCompleted(.failure):
                return .none

            case .delegate:
                return .none
            }
        }
        .ifLet(\.$videoPlayer, action: \.videoPlayer) {
            VideoPlayerFeature()
        }
    }

    private func loadPlaylists(_ state: inout State) -> Effect<Action> {
        state.isLoading = true
        let client = channelListClient
        return .run { send in
            let playlists = try await client.fetchPlaylists()
            await send(.playlistsLoaded(.success(playlists)))
        } catch: { error, send in
            await send(.playlistsLoaded(.failure(error)))
        }
    }

    private func loadChannels(playlistID: String) -> Effect<Action> {
        let client = channelListClient
        return .run { send in
            let grouped = try await client.fetchGroupedChannels(playlistID)
            await send(.channelsLoaded(.success(grouped)))
        } catch: { error, send in
            await send(.channelsLoaded(.failure(error)))
        }
    }

    private func fetchEPGData(for channels: [ChannelRecord]) -> Effect<Action> {
        let epgIDs = channels.compactMap { $0.epgID ?? $0.tvgID }
        guard !epgIDs.isEmpty else { return .none }
        let client = epgClient
        return .run { send in
            let programs = try await client.fetchNowPlayingBatch(epgIDs)
            let nowPlaying = programs.mapValues { $0.title }
            await send(.epgDataLoaded(.success(nowPlaying)))
        } catch: { error, send in
            await send(.epgDataLoaded(.failure(error)))
        }
    }

    private func syncEPG(playlistID: String) -> Effect<Action> {
        let client = epgClient
        return .run { send in
            let result = try await client.syncEPG(playlistID)
            await send(.epgSyncCompleted(.success(result)))
        } catch: { error, send in
            await send(.epgSyncCompleted(.failure(error)))
        }
    }
}

// MARK: - View

public struct LiveTVView: View {
    @Bindable var store: StoreOf<LiveTVFeature>
    @FocusState private var focusedChannelID: String?

    public init(store: StoreOf<LiveTVFeature>) {
        self.store = store
    }

    #if os(tvOS)
    private let columns = [GridItem(.adaptive(minimum: 300), spacing: 40)]
    #else
    private let columns = [GridItem(.adaptive(minimum: 130), spacing: 16)]
    #endif

    public var body: some View {
        NavigationStack {
            Group {
                if store.isLoading && store.displayedChannels.isEmpty {
                    loadingView
                } else if let error = store.errorMessage, store.displayedChannels.isEmpty {
                    errorView(error)
                } else if store.playlists.isEmpty {
                    emptyPlaylistView
                } else if store.displayedChannels.isEmpty && !store.isLoading {
                    emptyChannelsView
                } else {
                    channelGridContent
                }
            }
            .navigationTitle(Tab.liveTV.title)
            .onAppear { store.send(.onAppear) }
            .refreshable { store.send(.refreshTapped) }
            #if os(tvOS) || os(iOS)
            .fullScreenCover(
                item: $store.scope(state: \.videoPlayer, action: \.videoPlayer)
            ) { playerStore in
                VideoPlayerView(store: playerStore)
            }
            #else
            .sheet(
                item: $store.scope(state: \.videoPlayer, action: \.videoPlayer)
            ) { playerStore in
                VideoPlayerView(store: playerStore)
            }
            #endif
        }
    }

    // MARK: - Channel Grid Content

    private var channelGridContent: some View {
        VStack(spacing: 0) {
            if store.playlists.count > 1 {
                playlistPicker
            }

            if !store.isSearching && store.groups.count > 1 {
                groupFilterRow
            }

            searchField

            ScrollView {
                LazyVGrid(columns: columns, spacing: 32) {
                    ForEach(store.displayedChannels, id: \.id) { channel in
                        Button {
                            store.send(.channelTapped(channel))
                        } label: {
                            ChannelTileView(
                                channel: channel,
                                isFocused: focusedChannelID == channel.id,
                                nowPlaying: store.nowPlaying[channel.epgID ?? ""] ?? store.nowPlaying[channel.tvgID ?? ""]
                            )
                        }
                        .buttonStyle(.plain)
                        .focused($focusedChannelID, equals: channel.id)
                        .contextMenu {
                            Button {
                                store.send(.toggleFavoriteTapped(channel.id))
                            } label: {
                                Label(
                                    channel.isFavorite ? "Remove from Favorites" : "Add to Favorites",
                                    systemImage: channel.isFavorite ? "star.slash" : "star"
                                )
                            }
                        }
                    }
                }
                .padding(.horizontal, 40)
                .padding(.vertical, 20)
            }
        }
    }

    // MARK: - Playlist Picker

    private var playlistPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(store.playlists, id: \.id) { playlist in
                    Button {
                        store.send(.playlistSelected(playlist.id))
                    } label: {
                        Text(playlist.name)
                            .font(.body)
                            .fontWeight(store.selectedPlaylistID == playlist.id ? .bold : .regular)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(
                                store.selectedPlaylistID == playlist.id
                                    ? Color.accentColor.opacity(0.2)
                                    : Color.clear
                            )
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 40)
            .padding(.vertical, 8)
        }
    }

    // MARK: - Group Filter

    private var groupFilterRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(store.groups, id: \.self) { group in
                    groupPill(group)
                }
            }
            .padding(.horizontal, 40)
            .padding(.vertical, 8)
        }
    }

    private func groupPill(_ group: String) -> some View {
        let isSelected = store.selectedGroup == group
        return Button {
            store.send(.groupSelected(group))
        } label: {
            Text(group.isEmpty ? "Uncategorized" : group)
                #if os(tvOS)
                .font(.system(size: 29))
                #else
                .font(.subheadline)
                #endif
                .fontWeight(isSelected ? .bold : .regular)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(isSelected ? Color.accentColor.opacity(0.2) : Color.secondary.opacity(0.15))
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Search

    private var searchField: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField(
                "Search channels...",
                text: Binding(
                    get: { store.searchQuery },
                    set: { store.send(.searchQueryChanged($0)) }
                )
            )
            .autocorrectionDisabled()
            if !store.searchQuery.isEmpty {
                Button {
                    store.send(.searchQueryChanged(""))
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.secondary.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
    }

    // MARK: - Empty / Error States

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
            Text("Loading channels...")
                .foregroundStyle(.secondary)
        }
    }

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 56))
                .foregroundStyle(.secondary)
            Text(message)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Retry") {
                store.send(.retryTapped)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
    }

    private var emptyPlaylistView: some View {
        VStack(spacing: 24) {
            Image(systemName: Tab.liveTV.systemImage)
                .font(.system(size: 64))
                .foregroundStyle(.secondary)
            Text(Tab.liveTV.title)
                .font(.title)
            Text(Tab.liveTV.emptyStateMessage)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
    }

    private var emptyChannelsView: some View {
        VStack(spacing: 16) {
            Image(systemName: "tv.slash")
                .font(.system(size: 56))
                .foregroundStyle(.secondary)
            if store.isSearching {
                Text("No channels match \"\(store.searchQuery)\"")
                    .foregroundStyle(.secondary)
            } else {
                Text("No channels in this category")
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
    }
}
