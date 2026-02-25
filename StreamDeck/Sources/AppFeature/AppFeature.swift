import ComposableArchitecture
import Database
import SwiftUI

@Reducer
public struct AppFeature {
    @ObservableState
    public struct State: Equatable, Sendable {
        public var selectedTab: Tab = .home
        public var hasAcceptedDisclaimer: Bool = false

        public var home = HomeFeature.State()
        public var search = SearchFeature.State()
        public var liveTV = LiveTVFeature.State()
        public var guide = EPGGuideFeature.State()
        public var movies = MoviesFeature.State()
        public var tvShows = TVShowsFeature.State()
        public var emby = EmbyFeature.State()
        public var favorites = FavoritesFeature.State()
        public var settings = SettingsFeature.State()

        public init() {}
    }

    public enum Action: Sendable {
        case onAppear
        case tabSelected(Tab)
        case acceptDisclaimerTapped
        case stalePlaylistsRefreshed

        case home(HomeFeature.Action)
        case search(SearchFeature.Action)
        case liveTV(LiveTVFeature.Action)
        case guide(EPGGuideFeature.Action)
        case movies(MoviesFeature.Action)
        case tvShows(TVShowsFeature.Action)
        case emby(EmbyFeature.Action)
        case favorites(FavoritesFeature.Action)
        case settings(SettingsFeature.Action)
    }

    @Dependency(\.userDefaultsClient) var userDefaultsClient
    @Dependency(\.vodListClient) var vodListClient
    @Dependency(\.playlistImportClient) var playlistImportClient

    public init() {}

    public var body: some ReducerOf<Self> {
        Scope(state: \.home, action: \.home) { HomeFeature() }
        Scope(state: \.search, action: \.search) { SearchFeature() }
        Scope(state: \.liveTV, action: \.liveTV) { LiveTVFeature() }
        Scope(state: \.guide, action: \.guide) { EPGGuideFeature() }
        Scope(state: \.movies, action: \.movies) { MoviesFeature() }
        Scope(state: \.tvShows, action: \.tvShows) { TVShowsFeature() }
        Scope(state: \.emby, action: \.emby) { EmbyFeature() }
        Scope(state: \.favorites, action: \.favorites) { FavoritesFeature() }
        Scope(state: \.settings, action: \.settings) { SettingsFeature() }

        Reduce { state, action in
            switch action {
            case .onAppear:
                state.hasAcceptedDisclaimer = userDefaultsClient.boolForKey(
                    UserDefaultsKey.hasAcceptedDisclaimer
                )
                let vod = vodListClient
                let importClient = playlistImportClient
                return .run { send in
                    let playlists = try await vod.fetchPlaylists()
                    let now = Int(Date().timeIntervalSince1970)
                    for playlist in playlists {
                        let lastSync = playlist.lastSync ?? 0
                        let staleAfter = lastSync + (playlist.refreshHrs * 3600)
                        guard staleAfter < now else { continue }
                        _ = try? await importClient.refreshPlaylist(playlist.id)
                    }
                    await send(.stalePlaylistsRefreshed)
                } catch: { _, _ in }

            case .stalePlaylistsRefreshed:
                return .none
            case let .tabSelected(tab):
                state.selectedTab = tab
                return .none
            case .acceptDisclaimerTapped:
                state.hasAcceptedDisclaimer = true
                userDefaultsClient.setBool(true, UserDefaultsKey.hasAcceptedDisclaimer)
                return .none
            case .home, .search, .liveTV, .guide, .movies, .tvShows, .emby, .favorites, .settings:
                return .none
            }
        }
    }
}

// MARK: - App View

public struct AppView: View {
    @Bindable var store: StoreOf<AppFeature>

    public init(store: StoreOf<AppFeature>) {
        self.store = store
    }

    public var body: some View {
        Group {
            if store.hasAcceptedDisclaimer {
                sidebarTabView
            } else {
                DisclaimerView {
                    store.send(.acceptDisclaimerTapped)
                }
            }
        }
        .onAppear { store.send(.onAppear) }
    }

    private var sidebarTabView: some View {
        TabView(selection: $store.selectedTab.sending(\.tabSelected)) {
            SwiftUI.Tab(Tab.home.title, systemImage: Tab.home.systemImage, value: Tab.home) {
                HomeView(store: store.scope(state: \.home, action: \.home))
            }
            SwiftUI.Tab(Tab.search.title, systemImage: Tab.search.systemImage, value: Tab.search) {
                SearchView(store: store.scope(state: \.search, action: \.search))
            }
            SwiftUI.Tab(Tab.liveTV.title, systemImage: Tab.liveTV.systemImage, value: Tab.liveTV) {
                LiveTVView(store: store.scope(state: \.liveTV, action: \.liveTV))
            }
            SwiftUI.Tab(Tab.guide.title, systemImage: Tab.guide.systemImage, value: Tab.guide) {
                EPGGuideView(store: store.scope(state: \.guide, action: \.guide))
            }
            SwiftUI.Tab(Tab.movies.title, systemImage: Tab.movies.systemImage, value: Tab.movies) {
                MoviesView(store: store.scope(state: \.movies, action: \.movies))
            }
            SwiftUI.Tab(Tab.tvShows.title, systemImage: Tab.tvShows.systemImage, value: Tab.tvShows) {
                TVShowsView(store: store.scope(state: \.tvShows, action: \.tvShows))
            }
            SwiftUI.Tab(Tab.emby.title, systemImage: Tab.emby.systemImage, value: Tab.emby) {
                EmbyView(store: store.scope(state: \.emby, action: \.emby))
            }
            SwiftUI.Tab(Tab.favorites.title, systemImage: Tab.favorites.systemImage, value: Tab.favorites) {
                FavoritesView(store: store.scope(state: \.favorites, action: \.favorites))
            }
            SwiftUI.Tab(Tab.settings.title, systemImage: Tab.settings.systemImage, value: Tab.settings) {
                SettingsView(store: store.scope(state: \.settings, action: \.settings))
            }
        }
        #if os(tvOS)
        .tabViewStyle(.sidebarAdaptable)
        #endif
    }
}

// MARK: - Disclaimer View

struct DisclaimerView: View {
    let onAccept: () -> Void

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            Image(systemName: "exclamationmark.shield")
                .font(.system(size: 80))
                .foregroundStyle(.yellow)

            Text("Legal Disclaimer")
                .font(.title)

            Text("""
                StreamDeck is a media player application. You are responsible \
                for ensuring you have the legal right to access any content \
                you add to this app. The developers do not provide, host, or \
                endorse any media content.
                """)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 600)

            Button("I Understand") {
                onAccept()
            }
            .buttonStyle(.borderedProminent)

            Spacer()
        }
        .padding()
    }
}
