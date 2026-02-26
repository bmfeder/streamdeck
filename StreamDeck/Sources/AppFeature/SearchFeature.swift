import ComposableArchitecture
import Database
import SwiftUI

@Reducer
public struct SearchFeature {

    @ObservableState
    public struct State: Equatable, Sendable {
        public var searchQuery: String = ""
        public var channelResults: [ChannelRecord] = []
        public var movieResults: [VodItemRecord] = []
        public var seriesResults: [VodItemRecord] = []
        public var isSearching: Bool = false

        @Presents public var videoPlayer: VideoPlayerFeature.State?

        public var hasResults: Bool {
            !channelResults.isEmpty || !movieResults.isEmpty || !seriesResults.isEmpty
        }

        public var hasSearched: Bool { !searchQuery.isEmpty }

        public init() {}
    }

    public enum Action: Sendable {
        case searchQueryChanged(String)
        case channelResultsLoaded(Result<[ChannelRecord], Error>)
        case vodResultsLoaded(Result<[VodItemRecord], Error>)
        case channelTapped(ChannelRecord)
        case movieTapped(VodItemRecord)
        case seriesTapped(VodItemRecord)
        case clearTapped
        case videoPlayer(PresentationAction<VideoPlayerFeature.Action>)
        case delegate(Delegate)

        @CasePathable
        public enum Delegate: Sendable, Equatable {
            case playChannel(ChannelRecord)
            case playVodItem(VodItemRecord)
            case showSeries(VodItemRecord)
        }
    }

    @Dependency(\.channelListClient) var channelListClient
    @Dependency(\.vodListClient) var vodListClient

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

            case .videoPlayer:
                return .none

            case let .searchQueryChanged(query):
                state.searchQuery = query
                guard !query.isEmpty else {
                    state.channelResults = []
                    state.movieResults = []
                    state.seriesResults = []
                    state.isSearching = false
                    return .cancel(id: CancelID.search)
                }
                state.isSearching = true
                let channelClient = channelListClient
                let vodClient = vodListClient
                return .merge(
                    .run { send in
                        let channels = try await channelClient.searchChannels(query, nil)
                        await send(.channelResultsLoaded(.success(channels)))
                    } catch: { error, send in
                        await send(.channelResultsLoaded(.failure(error)))
                    },
                    .run { send in
                        let items = try await vodClient.searchVod(query, nil, nil)
                        await send(.vodResultsLoaded(.success(items)))
                    } catch: { error, send in
                        await send(.vodResultsLoaded(.failure(error)))
                    }
                )
                .cancellable(id: CancelID.search, cancelInFlight: true)

            case let .channelResultsLoaded(.success(channels)):
                state.channelResults = channels
                state.isSearching = false
                return .none

            case .channelResultsLoaded(.failure):
                state.channelResults = []
                state.isSearching = false
                return .none

            case let .vodResultsLoaded(.success(items)):
                state.movieResults = items.filter { $0.type == "movie" }
                state.seriesResults = items.filter { $0.type == "series" }
                state.isSearching = false
                return .none

            case .vodResultsLoaded(.failure):
                state.movieResults = []
                state.seriesResults = []
                state.isSearching = false
                return .none

            case let .channelTapped(channel):
                state.videoPlayer = VideoPlayerFeature.State(channel: channel)
                return .send(.delegate(.playChannel(channel)))

            case let .movieTapped(movie):
                guard movie.streamURL != nil else { return .none }
                state.videoPlayer = VideoPlayerFeature.State(vodItem: movie)
                return .send(.delegate(.playVodItem(movie)))

            case let .seriesTapped(series):
                return .send(.delegate(.showSeries(series)))

            case .clearTapped:
                state.searchQuery = ""
                state.channelResults = []
                state.movieResults = []
                state.seriesResults = []
                state.isSearching = false
                return .cancel(id: CancelID.search)

            case .delegate:
                return .none
            }
        }
        .ifLet(\.$videoPlayer, action: \.videoPlayer) {
            VideoPlayerFeature()
        }
    }
}

// MARK: - View

public struct SearchView: View {
    @Bindable var store: StoreOf<SearchFeature>
    @FocusState private var focusedItemID: String?

    public init(store: StoreOf<SearchFeature>) {
        self.store = store
    }

    public var body: some View {
        NavigationStack {
            Group {
                if store.isSearching && !store.hasResults {
                    searchingView
                } else if store.hasSearched && !store.hasResults && !store.isSearching {
                    noResultsView
                } else if store.hasResults {
                    resultsContent
                } else {
                    promptView
                }
            }
            .navigationTitle(Tab.search.title)
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
        .searchable(
            text: Binding(
                get: { store.searchQuery },
                set: { store.send(.searchQueryChanged($0)) }
            ),
            prompt: "Channels, movies, and TV shows"
        )
    }

    // MARK: - Results

    #if os(tvOS)
    private let channelWidth: CGFloat = 260
    private let channelHeight: CGFloat = 156
    #else
    private let channelWidth: CGFloat = 130
    private let channelHeight: CGFloat = 78
    #endif

    private var resultsContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                if !store.channelResults.isEmpty {
                    channelsSection
                }
                if !store.movieResults.isEmpty {
                    moviesSection
                }
                if !store.seriesResults.isEmpty {
                    seriesSection
                }
            }
            .padding(.vertical, 20)
        }
    }

    private var channelsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Live TV")
                .font(.title2)
                .fontWeight(.bold)
                .padding(.horizontal, 20)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 16) {
                    ForEach(store.channelResults, id: \.id) { channel in
                        Button {
                            store.send(.channelTapped(channel))
                        } label: {
                            ChannelTileView(
                                channel: channel,
                                isFocused: focusedItemID == channel.id
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

    private var moviesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Movies")
                .font(.title2)
                .fontWeight(.bold)
                .padding(.horizontal, 20)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 16) {
                    ForEach(store.movieResults, id: \.id) { movie in
                        Button {
                            store.send(.movieTapped(movie))
                        } label: {
                            VodPosterTileView(item: movie, isFocused: focusedItemID == movie.id)
                        }
                        .buttonStyle(.plain)
                        .focused($focusedItemID, equals: movie.id)
                    }
                }
                .padding(.horizontal, 20)
            }
        }
    }

    private var seriesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("TV Shows")
                .font(.title2)
                .fontWeight(.bold)
                .padding(.horizontal, 20)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 16) {
                    ForEach(store.seriesResults, id: \.id) { series in
                        Button {
                            store.send(.seriesTapped(series))
                        } label: {
                            VodPosterTileView(item: series, isFocused: focusedItemID == series.id)
                        }
                        .buttonStyle(.plain)
                        .focused($focusedItemID, equals: series.id)
                    }
                }
                .padding(.horizontal, 20)
            }
        }
    }

    // MARK: - States

    private var promptView: some View {
        VStack(spacing: 24) {
            Image(systemName: Tab.search.systemImage)
                .font(.system(size: 64))
                .foregroundStyle(.secondary)
            Text(Tab.search.title)
                .font(.title)
            Text(Tab.search.emptyStateMessage)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
    }

    private var searchingView: some View {
        VStack(spacing: 16) {
            ProgressView()
            Text("Searching...")
                .foregroundStyle(.secondary)
        }
    }

    private var noResultsView: some View {
        VStack(spacing: 16) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("No results for \"\(store.searchQuery)\"")
                .font(.title3)
                .foregroundStyle(.secondary)
            Text("Check your spelling, try a shorter query, or browse by category.")
                .font(.subheadline)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .padding()
    }
}
