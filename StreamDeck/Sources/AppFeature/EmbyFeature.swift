import ComposableArchitecture
import Database
import SwiftUI

@Reducer
public struct EmbyFeature {

    public enum ContentMode: String, CaseIterable, Sendable {
        case movies = "Movies"
        case tvShows = "TV Shows"
    }

    @ObservableState
    public struct State: Equatable, Sendable {
        public var embyPlaylists: [PlaylistRecord] = []
        public var selectedPlaylistID: String?
        public var contentMode: ContentMode = .movies

        // Movies
        public var movies: [VodItemRecord] = []
        public var displayedMovies: [VodItemRecord] = []

        // TV Shows
        public var seriesList: [VodItemRecord] = []
        public var displayedSeries: [VodItemRecord] = []

        // Series drill-down
        public var selectedSeries: VodItemRecord?
        public var episodes: [VodItemRecord] = []
        public var seasons: [Int] = []
        public var selectedSeason: Int?
        public var displayedEpisodes: [VodItemRecord] = []
        public var isLoadingEpisodes: Bool = false

        // Shared
        public var genres: [String] = []
        public var selectedGenre: String = "All"
        public var searchQuery: String = ""
        public var searchResults: [VodItemRecord]?
        public var progressMap: [String: Double] = [:]
        public var isLoading: Bool = false
        public var errorMessage: String?

        @Presents public var videoPlayer: VideoPlayerFeature.State?

        public var isSearching: Bool { !searchQuery.isEmpty }

        public init() {}
    }

    public enum Action: Sendable {
        case onAppear
        case playlistsLoaded(Result<[PlaylistRecord], Error>)
        case playlistSelected(String)
        case contentModeChanged(ContentMode)

        // Movies
        case moviesLoaded(Result<[VodItemRecord], Error>)
        case movieTapped(VodItemRecord)

        // TV Shows
        case seriesLoaded(Result<[VodItemRecord], Error>)
        case seriesTapped(VodItemRecord)
        case episodesLoaded(Result<[VodItemRecord], Error>)
        case seasonSelected(Int)
        case episodeTapped(VodItemRecord)
        case backToSeriesTapped

        // Shared
        case genresLoaded(Result<[String], Error>)
        case genreSelected(String)
        case searchQueryChanged(String)
        case searchResultsLoaded(Result<[VodItemRecord], Error>)
        case progressMapLoaded([String: WatchProgressRecord])
        case retryTapped
        case videoPlayer(PresentationAction<VideoPlayerFeature.Action>)
        case delegate(Delegate)

        @CasePathable
        public enum Delegate: Sendable, Equatable {
            case playMovie(VodItemRecord)
            case playEpisode(VodItemRecord)
        }
    }

    @Dependency(\.vodListClient) var vodListClient
    @Dependency(\.watchProgressClient) var watchProgressClient

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

            case .onAppear:
                guard state.embyPlaylists.isEmpty else { return .none }
                state.isLoading = true
                let client = vodListClient
                return .run { send in
                    let playlists = try await client.fetchPlaylists()
                    await send(.playlistsLoaded(.success(playlists)))
                } catch: { error, send in
                    await send(.playlistsLoaded(.failure(error)))
                }

            case let .playlistsLoaded(.success(playlists)):
                let embyPlaylists = playlists.filter { $0.type == "emby" }
                state.embyPlaylists = embyPlaylists
                if let first = embyPlaylists.first {
                    state.selectedPlaylistID = first.id
                    return loadContent(for: state.contentMode, playlistID: first.id)
                }
                state.isLoading = false
                return .none

            case let .playlistsLoaded(.failure(error)):
                state.isLoading = false
                state.errorMessage = "Failed to load playlists: \(error.localizedDescription)"
                return .none

            case let .playlistSelected(playlistID):
                guard playlistID != state.selectedPlaylistID else { return .none }
                state.selectedPlaylistID = playlistID
                state.searchQuery = ""
                state.searchResults = nil
                state.selectedGenre = "All"
                state.selectedSeries = nil
                state.episodes = []
                state.seasons = []
                state.isLoading = true
                return loadContent(for: state.contentMode, playlistID: playlistID)

            case let .contentModeChanged(mode):
                guard mode != state.contentMode else { return .none }
                state.contentMode = mode
                state.searchQuery = ""
                state.searchResults = nil
                state.selectedGenre = "All"
                state.selectedSeries = nil
                state.episodes = []
                state.seasons = []
                state.selectedSeason = nil
                state.displayedEpisodes = []
                state.isLoadingEpisodes = false
                guard let playlistID = state.selectedPlaylistID else { return .none }
                state.isLoading = true
                return loadContent(for: mode, playlistID: playlistID)

            // MARK: - Movies

            case let .moviesLoaded(.success(movies)):
                state.isLoading = false
                state.movies = movies
                state.displayedMovies = movies
                state.errorMessage = nil
                let ids = movies.map(\.id)
                let progressClient = watchProgressClient
                return .run { send in
                    let batch = try await progressClient.getProgressBatch(ids)
                    await send(.progressMapLoaded(batch))
                }

            case let .moviesLoaded(.failure(error)):
                state.isLoading = false
                state.errorMessage = "Failed to load movies: \(error.localizedDescription)"
                return .none

            case let .movieTapped(movie):
                guard movie.streamURL != nil else { return .none }
                state.videoPlayer = VideoPlayerFeature.State(vodItem: movie)
                return .send(.delegate(.playMovie(movie)))

            // MARK: - TV Shows

            case let .seriesLoaded(.success(series)):
                state.isLoading = false
                state.seriesList = series
                state.displayedSeries = series
                state.errorMessage = nil
                return .none

            case let .seriesLoaded(.failure(error)):
                state.isLoading = false
                state.errorMessage = "Failed to load TV shows: \(error.localizedDescription)"
                return .none

            case let .seriesTapped(series):
                state.selectedSeries = series
                state.isLoadingEpisodes = true
                let client = vodListClient
                let seriesID = series.id
                return .run { send in
                    let episodes = try await client.fetchEpisodes(seriesID)
                    await send(.episodesLoaded(.success(episodes)))
                } catch: { error, send in
                    await send(.episodesLoaded(.failure(error)))
                }

            case let .episodesLoaded(.success(episodes)):
                state.isLoadingEpisodes = false
                state.episodes = episodes
                let seasons = Set(episodes.compactMap { $0.seasonNum }).sorted()
                state.seasons = seasons
                if let first = seasons.first {
                    state.selectedSeason = first
                    state.displayedEpisodes = episodes.filter { $0.seasonNum == first }
                } else {
                    state.displayedEpisodes = episodes
                }
                let ids = episodes.map(\.id)
                let progressClient = watchProgressClient
                return .run { send in
                    let batch = try await progressClient.getProgressBatch(ids)
                    await send(.progressMapLoaded(batch))
                }

            case let .episodesLoaded(.failure(error)):
                state.isLoadingEpisodes = false
                state.errorMessage = "Failed to load episodes: \(error.localizedDescription)"
                return .none

            case let .seasonSelected(season):
                state.selectedSeason = season
                state.displayedEpisodes = state.episodes.filter { $0.seasonNum == season }
                return .none

            case let .episodeTapped(episode):
                guard episode.streamURL != nil else { return .none }
                state.videoPlayer = VideoPlayerFeature.State(vodItem: episode)
                return .send(.delegate(.playEpisode(episode)))

            case .backToSeriesTapped:
                state.selectedSeries = nil
                state.episodes = []
                state.seasons = []
                state.selectedSeason = nil
                state.displayedEpisodes = []
                state.isLoadingEpisodes = false
                return .none

            // MARK: - Shared

            case let .genresLoaded(.success(genres)):
                state.genres = ["All"] + genres
                return .none

            case .genresLoaded(.failure):
                return .none

            case let .genreSelected(genre):
                state.selectedGenre = genre
                switch state.contentMode {
                case .movies:
                    if genre == "All" {
                        state.displayedMovies = state.movies
                    } else {
                        state.displayedMovies = state.movies.filter { movie in
                            guard let movieGenre = movie.genre else { return false }
                            let parts = movieGenre.split(separator: ",").map {
                                $0.trimmingCharacters(in: .whitespaces)
                            }
                            return parts.contains(genre)
                        }
                    }
                case .tvShows:
                    if genre == "All" {
                        state.displayedSeries = state.seriesList
                    } else {
                        state.displayedSeries = state.seriesList.filter { series in
                            guard let seriesGenre = series.genre else { return false }
                            let parts = seriesGenre.split(separator: ",").map {
                                $0.trimmingCharacters(in: .whitespaces)
                            }
                            return parts.contains(genre)
                        }
                    }
                }
                return .none

            case let .searchQueryChanged(query):
                state.searchQuery = query
                if query.isEmpty {
                    state.searchResults = nil
                    return .send(.genreSelected(state.selectedGenre))
                }
                let client = vodListClient
                let playlistID = state.selectedPlaylistID
                let type = state.contentMode == .movies ? "movie" : "series"
                return .run { send in
                    let results = try await client.searchVod(query, playlistID, type)
                    await send(.searchResultsLoaded(.success(results)))
                } catch: { error, send in
                    await send(.searchResultsLoaded(.failure(error)))
                }
                .cancellable(id: CancelID.search, cancelInFlight: true)

            case let .searchResultsLoaded(.success(results)):
                state.searchResults = results
                switch state.contentMode {
                case .movies:
                    state.displayedMovies = results
                case .tvShows:
                    state.displayedSeries = results
                }
                return .none

            case .searchResultsLoaded(.failure):
                state.searchResults = []
                switch state.contentMode {
                case .movies:
                    state.displayedMovies = []
                case .tvShows:
                    state.displayedSeries = []
                }
                return .none

            case let .progressMapLoaded(batch):
                var map: [String: Double] = [:]
                for (id, record) in batch {
                    if let duration = record.durationMs, duration > 0 {
                        map[id] = Double(record.positionMs) / Double(duration)
                    }
                }
                state.progressMap = map
                return .none

            case .retryTapped:
                state.errorMessage = nil
                state.isLoading = true
                if let playlistID = state.selectedPlaylistID {
                    return loadContent(for: state.contentMode, playlistID: playlistID)
                }
                let client = vodListClient
                return .run { send in
                    let playlists = try await client.fetchPlaylists()
                    await send(.playlistsLoaded(.success(playlists)))
                } catch: { error, send in
                    await send(.playlistsLoaded(.failure(error)))
                }

            case .delegate:
                return .none
            }
        }
        .ifLet(\.$videoPlayer, action: \.videoPlayer) {
            VideoPlayerFeature()
        }
    }

    // MARK: - Helpers

    private func loadContent(for mode: ContentMode, playlistID: String) -> Effect<Action> {
        let client = vodListClient
        switch mode {
        case .movies:
            return .merge(
                .run { send in
                    let movies = try await client.fetchMovies(playlistID)
                    await send(.moviesLoaded(.success(movies)))
                } catch: { error, send in
                    await send(.moviesLoaded(.failure(error)))
                },
                .run { send in
                    let genres = try await client.fetchGenres(playlistID, "movie")
                    await send(.genresLoaded(.success(genres)))
                } catch: { error, send in
                    await send(.genresLoaded(.failure(error)))
                }
            )
        case .tvShows:
            return .merge(
                .run { send in
                    let series = try await client.fetchSeries(playlistID)
                    await send(.seriesLoaded(.success(series)))
                } catch: { error, send in
                    await send(.seriesLoaded(.failure(error)))
                },
                .run { send in
                    let genres = try await client.fetchGenres(playlistID, "series")
                    await send(.genresLoaded(.success(genres)))
                } catch: { error, send in
                    await send(.genresLoaded(.failure(error)))
                }
            )
        }
    }
}

// MARK: - View

public struct EmbyView: View {
    @Bindable var store: StoreOf<EmbyFeature>
    @FocusState private var focusedItemID: String?

    public init(store: StoreOf<EmbyFeature>) {
        self.store = store
    }

    #if os(tvOS)
    private let columns = [GridItem(.adaptive(minimum: 180), spacing: 30)]
    #else
    private let columns = [GridItem(.adaptive(minimum: 120), spacing: 16)]
    #endif

    public var body: some View {
        NavigationStack {
            Group {
                if store.embyPlaylists.isEmpty && !store.isLoading {
                    emptyStateView
                } else if store.isLoading && currentItemsEmpty {
                    loadingView
                } else if let error = store.errorMessage, currentItemsEmpty {
                    errorView(error)
                } else {
                    contentView
                }
            }
            .navigationTitle(navigationTitle)
            .onAppear { store.send(.onAppear) }
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

    private var navigationTitle: String {
        if let series = store.selectedSeries {
            return series.title
        }
        return Tab.emby.title
    }

    private var currentItemsEmpty: Bool {
        switch store.contentMode {
        case .movies: return store.displayedMovies.isEmpty
        case .tvShows: return store.displayedSeries.isEmpty
        }
    }

    // MARK: - Content

    private var contentView: some View {
        VStack(spacing: 0) {
            if store.embyPlaylists.count > 1 {
                playlistPicker
            }

            if store.selectedSeries == nil {
                contentModePicker
            }

            switch store.contentMode {
            case .movies:
                movieContent
            case .tvShows:
                if store.selectedSeries != nil {
                    seriesDetailContent
                } else {
                    seriesGridContent
                }
            }
        }
    }

    // MARK: - Content Mode Picker

    private var contentModePicker: some View {
        Picker("Content", selection: Binding(
            get: { store.contentMode },
            set: { store.send(.contentModeChanged($0)) }
        )) {
            ForEach(EmbyFeature.ContentMode.allCases, id: \.self) { mode in
                Text(mode.rawValue).tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
    }

    // MARK: - Movie Content

    private var movieContent: some View {
        VStack(spacing: 0) {
            if !store.isSearching && store.genres.count > 1 {
                genreFilterRow
            }
            searchField("Search movies...")

            if store.displayedMovies.isEmpty && !store.isLoading {
                Spacer()
                emptyContentMessage("No movies found")
                Spacer()
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 20) {
                        ForEach(store.displayedMovies, id: \.id) { movie in
                            Button {
                                store.send(.movieTapped(movie))
                            } label: {
                                VodPosterTileView(
                                    item: movie,
                                    isFocused: focusedItemID == movie.id,
                                    progress: store.progressMap[movie.id]
                                )
                            }
                            .buttonStyle(.plain)
                            .focused($focusedItemID, equals: movie.id)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 20)
                }
            }
        }
    }

    // MARK: - Series Grid Content

    private var seriesGridContent: some View {
        VStack(spacing: 0) {
            if !store.isSearching && store.genres.count > 1 {
                genreFilterRow
            }
            searchField("Search TV shows...")

            if store.displayedSeries.isEmpty && !store.isLoading {
                Spacer()
                emptyContentMessage("No TV shows found")
                Spacer()
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 20) {
                        ForEach(store.displayedSeries, id: \.id) { series in
                            Button {
                                store.send(.seriesTapped(series))
                            } label: {
                                VodPosterTileView(
                                    item: series,
                                    isFocused: focusedItemID == series.id
                                )
                            }
                            .buttonStyle(.plain)
                            .focused($focusedItemID, equals: series.id)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 20)
                }
            }
        }
    }

    // MARK: - Series Detail (Episodes)

    private var seriesDetailContent: some View {
        VStack(spacing: 0) {
            HStack {
                Button {
                    store.send(.backToSeriesTapped)
                } label: {
                    Label("All Shows", systemImage: "chevron.left")
                        .font(.subheadline)
                }
                .buttonStyle(.plain)
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 8)

            if store.isLoadingEpisodes {
                Spacer()
                ProgressView()
                Text("Loading episodes...")
                    .foregroundStyle(.secondary)
                Spacer()
            } else if store.episodes.isEmpty {
                Spacer()
                emptyContentMessage("No episodes available")
                Spacer()
            } else {
                if store.seasons.count > 1 {
                    seasonPicker
                }
                episodeList
            }
        }
    }

    // MARK: - Season Picker

    private var seasonPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(store.seasons, id: \.self) { season in
                    let isSelected = store.selectedSeason == season
                    Button {
                        store.send(.seasonSelected(season))
                    } label: {
                        Text("Season \(season)")
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
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 8)
        }
    }

    // MARK: - Episode List

    private var episodeList: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(store.displayedEpisodes, id: \.id) { episode in
                    Button {
                        store.send(.episodeTapped(episode))
                    } label: {
                        episodeRow(episode)
                    }
                    .buttonStyle(.plain)
                    .focused($focusedItemID, equals: episode.id)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
    }

    private func episodeRow(_ episode: VodItemRecord) -> some View {
        HStack(spacing: 16) {
            episodeThumbnail(episode)
                .frame(width: 120, height: 68)
                .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 4) {
                if let season = episode.seasonNum, let ep = episode.episodeNum {
                    Text("S\(String(format: "%02d", season))E\(String(format: "%02d", ep))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text(episode.title)
                    .font(.headline)
                    .lineLimit(2)
                if let duration = episode.durationS, duration > 0 {
                    Text(formattedDuration(duration))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Image(systemName: "play.circle")
                .font(.title2)
                .foregroundStyle(.secondary)
        }
        .overlay(alignment: .bottom) {
            if let progress = store.progressMap[episode.id], progress > 0 {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Rectangle().fill(Color.secondary.opacity(0.2))
                        Rectangle().fill(Color.accentColor)
                            .frame(width: geo.size.width * min(max(progress, 0), 1))
                    }
                }
                .frame(height: 3)
            }
        }
        .padding(.vertical, 4)
        .scaleEffect(focusedItemID == episode.id ? 1.02 : 1.0)
        .animation(.easeInOut(duration: 0.15), value: focusedItemID)
    }

    @ViewBuilder
    private func episodeThumbnail(_ episode: VodItemRecord) -> some View {
        if let posterURLString = episode.posterURL,
           let posterURL = URL(string: posterURLString) {
            AsyncImage(url: posterURL) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().aspectRatio(contentMode: .fill)
                case .failure:
                    thumbnailPlaceholder
                case .empty:
                    ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                @unknown default:
                    thumbnailPlaceholder
                }
            }
        } else {
            thumbnailPlaceholder
        }
    }

    private var thumbnailPlaceholder: some View {
        ZStack {
            Color.secondary.opacity(0.2)
            Image(systemName: "play.rectangle")
                .foregroundStyle(.secondary)
        }
    }

    private func formattedDuration(_ seconds: Int) -> String {
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        return "\(minutes)m"
    }

    // MARK: - Playlist Picker

    private var playlistPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(store.embyPlaylists, id: \.id) { playlist in
                    Button {
                        store.send(.playlistSelected(playlist.id))
                    } label: {
                        Text(playlist.name)
                            .font(.subheadline)
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
            .padding(.horizontal, 20)
            .padding(.vertical, 8)
        }
    }

    // MARK: - Genre Filter

    private var genreFilterRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(store.genres, id: \.self) { genre in
                    genrePill(genre)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 8)
        }
    }

    private func genrePill(_ genre: String) -> some View {
        let isSelected = store.selectedGenre == genre
        return Button {
            store.send(.genreSelected(genre))
        } label: {
            Text(genre)
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

    private func searchField(_ placeholder: String) -> some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField(
                placeholder,
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

    private var emptyStateView: some View {
        VStack(spacing: 24) {
            Image(systemName: Tab.emby.systemImage)
                .font(.system(size: 64))
                .foregroundStyle(.secondary)
            Text(Tab.emby.title)
                .font(.title)
            Text(Tab.emby.emptyStateMessage)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
    }

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
            Text("Loading content...")
                .foregroundStyle(.secondary)
        }
    }

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 48))
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

    private func emptyContentMessage(_ message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "film.slash")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            if store.isSearching {
                Text("No results for \"\(store.searchQuery)\"")
                    .foregroundStyle(.secondary)
            } else {
                Text(message)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
    }
}
