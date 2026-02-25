import ComposableArchitecture
import Database
import SwiftUI

@Reducer
public struct HomeFeature {

    public struct ContinueWatchingItem: Equatable, Sendable, Identifiable {
        public let vodItem: VodItemRecord
        public let progress: Double
        public let positionMs: Int
        public var id: String { vodItem.id }
    }

    @ObservableState
    public struct State: Equatable, Sendable {
        public var continueWatchingItems: [ContinueWatchingItem] = []
        public var favoriteChannels: [ChannelRecord] = []
        public var nowPlaying: [String: String] = [:]
        public var isLoading: Bool = false

        @Presents public var videoPlayer: VideoPlayerFeature.State?

        public init() {}
    }

    public enum Action: Sendable {
        case onAppear
        case continueWatchingLoaded(Result<[ContinueWatchingItem], Error>)
        case favoritesLoaded(Result<[ChannelRecord], Error>)
        case epgDataLoaded(Result<[String: String], Error>)
        case refreshTapped
        case continueWatchingItemTapped(ContinueWatchingItem)
        case favoriteChannelTapped(ChannelRecord)
        case videoPlayer(PresentationAction<VideoPlayerFeature.Action>)
        case delegate(Delegate)

        @CasePathable
        public enum Delegate: Sendable, Equatable {
            case playVodItem(VodItemRecord)
            case playChannel(ChannelRecord)
        }
    }

    @Dependency(\.watchProgressClient) var watchProgressClient
    @Dependency(\.vodListClient) var vodListClient
    @Dependency(\.channelListClient) var channelListClient
    @Dependency(\.epgClient) var epgClient

    public init() {}

    public var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .videoPlayer(.presented(.delegate(.dismissed))):
                state.videoPlayer = nil
                return .none

            case .videoPlayer:
                return .none

            case .onAppear, .refreshTapped:
                state.isLoading = true
                let progressClient = watchProgressClient
                let vodClient = vodListClient
                let channelClient = channelListClient
                return .merge(
                    .run { send in
                        let unfinished = try await progressClient.getUnfinished(20)
                        let ids = unfinished.map(\.contentID)
                        guard !ids.isEmpty else {
                            await send(.continueWatchingLoaded(.success([])))
                            return
                        }
                        let vodItems = try await vodClient.fetchVodItemsByIDs(ids)
                        let vodMap = Dictionary(vodItems.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
                        var items: [ContinueWatchingItem] = []
                        for record in unfinished {
                            guard let vod = vodMap[record.contentID] else { continue }
                            let progress: Double
                            if let duration = record.durationMs, duration > 0 {
                                progress = Double(record.positionMs) / Double(duration)
                            } else {
                                progress = 0
                            }
                            items.append(ContinueWatchingItem(
                                vodItem: vod,
                                progress: progress,
                                positionMs: record.positionMs
                            ))
                        }
                        await send(.continueWatchingLoaded(.success(items)))
                    } catch: { error, send in
                        await send(.continueWatchingLoaded(.failure(error)))
                    },
                    .run { send in
                        let favorites = try await channelClient.fetchFavorites()
                        await send(.favoritesLoaded(.success(favorites)))
                    } catch: { error, send in
                        await send(.favoritesLoaded(.failure(error)))
                    }
                )

            case let .continueWatchingLoaded(.success(items)):
                state.continueWatchingItems = items
                state.isLoading = false
                return .none

            case .continueWatchingLoaded(.failure):
                state.isLoading = false
                return .none

            case let .favoritesLoaded(.success(channels)):
                state.favoriteChannels = channels
                return fetchEPGData(for: channels)

            case .favoritesLoaded(.failure):
                return .none

            case let .epgDataLoaded(.success(nowPlaying)):
                state.nowPlaying.merge(nowPlaying) { _, new in new }
                return .none

            case .epgDataLoaded(.failure):
                return .none

            case let .continueWatchingItemTapped(item):
                guard item.vodItem.streamURL != nil else { return .none }
                state.videoPlayer = VideoPlayerFeature.State(vodItem: item.vodItem)
                return .send(.delegate(.playVodItem(item.vodItem)))

            case let .favoriteChannelTapped(channel):
                state.videoPlayer = VideoPlayerFeature.State(channel: channel)
                return .send(.delegate(.playChannel(channel)))

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

public struct HomeView: View {
    @Bindable var store: StoreOf<HomeFeature>
    @FocusState private var focusedItemID: String?

    public init(store: StoreOf<HomeFeature>) {
        self.store = store
    }

    public var body: some View {
        NavigationStack {
            Group {
                if store.isLoading && store.continueWatchingItems.isEmpty && store.favoriteChannels.isEmpty {
                    loadingView
                } else if store.continueWatchingItems.isEmpty && store.favoriteChannels.isEmpty {
                    emptyView
                } else {
                    dashboardContent
                }
            }
            .navigationTitle(Tab.home.title)
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

    // MARK: - Dashboard

    private var dashboardContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                if !store.continueWatchingItems.isEmpty {
                    continueWatchingSection
                }
                if !store.favoriteChannels.isEmpty {
                    favoritesSection
                }
            }
            .padding(.vertical, 20)
        }
    }

    // MARK: - Continue Watching

    #if os(tvOS)
    private let posterWidth: CGFloat = 180
    private let posterHeight: CGFloat = 270
    private let channelWidth: CGFloat = 260
    private let channelHeight: CGFloat = 156
    #else
    private let posterWidth: CGFloat = 120
    private let posterHeight: CGFloat = 180
    private let channelWidth: CGFloat = 130
    private let channelHeight: CGFloat = 78
    #endif

    private var continueWatchingSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Continue Watching")
                .font(.title2)
                .fontWeight(.bold)
                .padding(.horizontal, 20)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 16) {
                    ForEach(store.continueWatchingItems) { item in
                        Button {
                            store.send(.continueWatchingItemTapped(item))
                        } label: {
                            VodPosterTileView(
                                item: item.vodItem,
                                isFocused: focusedItemID == item.id,
                                progress: item.progress
                            )
                        }
                        .buttonStyle(.plain)
                        .focused($focusedItemID, equals: item.id)
                    }
                }
                .padding(.horizontal, 20)
            }
        }
    }

    // MARK: - Favorites

    private var favoritesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Favorites")
                .font(.title2)
                .fontWeight(.bold)
                .padding(.horizontal, 20)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 16) {
                    ForEach(store.favoriteChannels, id: \.id) { channel in
                        Button {
                            store.send(.favoriteChannelTapped(channel))
                        } label: {
                            ChannelTileView(
                                channel: channel,
                                isFocused: focusedItemID == channel.id,
                                nowPlaying: store.nowPlaying[channel.epgID ?? ""]
                                    ?? store.nowPlaying[channel.tvgID ?? ""]
                            )
                        }
                        .buttonStyle(.plain)
                        .focused($focusedItemID, equals: channel.id)
                    }
                }
                .padding(.horizontal, 20)
            }
        }
    }

    // MARK: - Empty / Loading States

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
            Text("Loading...")
                .foregroundStyle(.secondary)
        }
    }

    private var emptyView: some View {
        VStack(spacing: 24) {
            Image(systemName: Tab.home.systemImage)
                .font(.system(size: 64))
                .foregroundStyle(.secondary)
            Text(Tab.home.title)
                .font(.title)
            Text(Tab.home.emptyStateMessage)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
    }
}
