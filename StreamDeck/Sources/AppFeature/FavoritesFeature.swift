import ComposableArchitecture
import Database
import Repositories
import SwiftUI

@Reducer
public struct FavoritesFeature {

    @ObservableState
    public struct State: Equatable, Sendable {
        public var channels: [ChannelRecord] = []
        public var isLoading: Bool = false
        public var focusedChannelID: String?
        public var nowPlaying: [String: String] = [:]
        @Presents public var videoPlayer: VideoPlayerFeature.State?

        public init() {}
    }

    public enum Action: Sendable {
        case onAppear
        case refreshTapped
        case channelsLoaded(Result<[ChannelRecord], Error>)
        case channelTapped(ChannelRecord)
        case toggleFavoriteTapped(String)
        case favoriteToggled(Result<String, Error>)
        case epgDataLoaded(Result<[String: String], Error>)
        case videoPlayer(PresentationAction<VideoPlayerFeature.Action>)
        case delegate(Delegate)

        @CasePathable
        public enum Delegate: Sendable, Equatable {
            case playChannel(ChannelRecord)
        }
    }

    @Dependency(\.channelListClient) var channelListClient
    @Dependency(\.epgClient) var epgClient

    public init() {}

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

            case .onAppear, .refreshTapped:
                state.isLoading = true
                let client = channelListClient
                return .run { send in
                    let favorites = try await client.fetchFavorites()
                    await send(.channelsLoaded(.success(favorites)))
                } catch: { error, send in
                    await send(.channelsLoaded(.failure(error)))
                }

            case let .channelsLoaded(.success(channels)):
                state.isLoading = false
                state.channels = channels
                return fetchEPGData(for: channels)

            case .channelsLoaded(.failure):
                state.isLoading = false
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
                state.channels.removeAll { $0.id == channelID }
                return .none

            case .favoriteToggled(.failure):
                return .none

            case let .epgDataLoaded(.success(nowPlaying)):
                state.nowPlaying.merge(nowPlaying) { _, new in new }
                return .none

            case .epgDataLoaded(.failure):
                return .none

            case .delegate:
                return .none
            }
        }
        .ifLet(\.$videoPlayer, action: \.videoPlayer) {
            VideoPlayerFeature()
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
}

// MARK: - View

public struct FavoritesView: View {
    @Bindable var store: StoreOf<FavoritesFeature>
    @FocusState private var focusedChannelID: String?

    public init(store: StoreOf<FavoritesFeature>) {
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
                if store.isLoading && store.channels.isEmpty {
                    ProgressView()
                } else if store.channels.isEmpty {
                    emptyView
                } else {
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 32) {
                            ForEach(store.channels, id: \.id) { channel in
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
                                        Label("Remove from Favorites", systemImage: "star.slash")
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, 40)
                        .padding(.vertical, 20)
                    }
                }
            }
            .navigationTitle(Tab.favorites.title)
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

    private var emptyView: some View {
        VStack(spacing: 24) {
            Image(systemName: Tab.favorites.systemImage)
                .font(.system(size: 64))
                .foregroundStyle(.secondary)
            Text(Tab.favorites.title)
                .font(.title)
            Text(Tab.favorites.emptyStateMessage)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
    }
}
