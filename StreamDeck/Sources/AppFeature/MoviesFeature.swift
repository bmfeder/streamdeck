import ComposableArchitecture
import Database
import SwiftUI

@Reducer
public struct MoviesFeature {

    @ObservableState
    public struct State: Equatable, Sendable {
        public var playlists: [PlaylistRecord] = []
        public var selectedPlaylistID: String?
        public var movies: [VodItemRecord] = []
        public var genres: [String] = []
        public var selectedGenre: String = "All"
        public var displayedMovies: [VodItemRecord] = []

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
        case moviesLoaded(Result<[VodItemRecord], Error>)
        case genresLoaded(Result<[String], Error>)
        case playlistSelected(String)
        case genreSelected(String)
        case searchQueryChanged(String)
        case searchResultsLoaded(Result<[VodItemRecord], Error>)
        case movieTapped(VodItemRecord)
        case progressMapLoaded([String: WatchProgressRecord])
        case refreshTapped
        case retryTapped
        case videoPlayer(PresentationAction<VideoPlayerFeature.Action>)
        case delegate(Delegate)

        @CasePathable
        public enum Delegate: Sendable, Equatable {
            case playMovie(VodItemRecord)
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
                guard state.playlists.isEmpty else { return .none }
                return loadPlaylists(&state)

            case .refreshTapped:
                state.playlists = []
                state.movies = []
                state.genres = []
                state.selectedGenre = "All"
                state.displayedMovies = []
                state.searchQuery = ""
                state.searchResults = nil
                state.progressMap = [:]
                state.errorMessage = nil
                return loadPlaylists(&state)

            case let .playlistsLoaded(.success(playlists)):
                state.playlists = playlists.filter { $0.type != "emby" }
                if let first = playlists.first {
                    state.selectedPlaylistID = first.id
                    return .merge(
                        loadMovies(playlistID: first.id),
                        loadGenres(playlistID: first.id)
                    )
                }
                state.isLoading = false
                return .none

            case let .playlistsLoaded(.failure(error)):
                state.isLoading = false
                state.errorMessage = "Failed to load playlists: \(error.localizedDescription)"
                return .none

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

            case let .genresLoaded(.success(genres)):
                state.genres = ["All"] + genres
                return .none

            case .genresLoaded(.failure):
                return .none

            case let .playlistSelected(playlistID):
                guard playlistID != state.selectedPlaylistID else { return .none }
                state.selectedPlaylistID = playlistID
                state.searchQuery = ""
                state.searchResults = nil
                state.selectedGenre = "All"
                state.isLoading = true
                return .merge(
                    loadMovies(playlistID: playlistID),
                    loadGenres(playlistID: playlistID)
                )

            case let .genreSelected(genre):
                state.selectedGenre = genre
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
                return .none

            case let .searchQueryChanged(query):
                state.searchQuery = query
                if query.isEmpty {
                    state.searchResults = nil
                    return .send(.genreSelected(state.selectedGenre))
                }
                let client = vodListClient
                let playlistID = state.selectedPlaylistID
                return .run { send in
                    let results = try await client.searchVod(query, playlistID, "movie")
                    await send(.searchResultsLoaded(.success(results)))
                } catch: { error, send in
                    await send(.searchResultsLoaded(.failure(error)))
                }
                .cancellable(id: CancelID.search, cancelInFlight: true)

            case let .searchResultsLoaded(.success(results)):
                state.searchResults = results
                state.displayedMovies = results
                return .none

            case .searchResultsLoaded(.failure):
                state.searchResults = []
                state.displayedMovies = []
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

            case let .movieTapped(movie):
                guard movie.streamURL != nil else { return .none }
                state.videoPlayer = VideoPlayerFeature.State(vodItem: movie)
                return .send(.delegate(.playMovie(movie)))

            case .retryTapped:
                state.errorMessage = nil
                state.isLoading = true
                if let playlistID = state.selectedPlaylistID {
                    return loadMovies(playlistID: playlistID)
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

    private func loadPlaylists(_ state: inout State) -> Effect<Action> {
        state.isLoading = true
        let client = vodListClient
        return .run { send in
            let playlists = try await client.fetchPlaylists()
            await send(.playlistsLoaded(.success(playlists)))
        } catch: { error, send in
            await send(.playlistsLoaded(.failure(error)))
        }
    }

    private func loadMovies(playlistID: String) -> Effect<Action> {
        let client = vodListClient
        return .run { send in
            let movies = try await client.fetchMovies(playlistID)
            await send(.moviesLoaded(.success(movies)))
        } catch: { error, send in
            await send(.moviesLoaded(.failure(error)))
        }
    }

    private func loadGenres(playlistID: String) -> Effect<Action> {
        let client = vodListClient
        return .run { send in
            let genres = try await client.fetchGenres(playlistID, "movie")
            await send(.genresLoaded(.success(genres)))
        } catch: { error, send in
            await send(.genresLoaded(.failure(error)))
        }
    }
}

// MARK: - View

public struct MoviesView: View {
    @Bindable var store: StoreOf<MoviesFeature>
    @FocusState private var focusedMovieID: String?

    public init(store: StoreOf<MoviesFeature>) {
        self.store = store
    }

    #if os(tvOS)
    private let columns = [GridItem(.adaptive(minimum: 220), spacing: 40)]
    #else
    private let columns = [GridItem(.adaptive(minimum: 120), spacing: 16)]
    #endif

    public var body: some View {
        NavigationStack {
            Group {
                if store.isLoading && store.displayedMovies.isEmpty {
                    loadingView
                } else if let error = store.errorMessage, store.displayedMovies.isEmpty {
                    errorView(error)
                } else if store.playlists.isEmpty {
                    emptyPlaylistView
                } else if store.displayedMovies.isEmpty && !store.isLoading {
                    emptyMoviesView
                } else {
                    movieGridContent
                }
            }
            .navigationTitle(Tab.movies.title)
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

    // MARK: - Movie Grid Content

    private var movieGridContent: some View {
        VStack(spacing: 0) {
            if store.playlists.count > 1 {
                playlistPicker
            }

            if !store.isSearching && store.genres.count > 1 {
                genreFilterRow
            }

            searchField

            ScrollView {
                LazyVGrid(columns: columns, spacing: 32) {
                    ForEach(store.displayedMovies, id: \.id) { movie in
                        Button {
                            store.send(.movieTapped(movie))
                        } label: {
                            VodPosterTileView(
                                item: movie,
                                isFocused: focusedMovieID == movie.id,
                                progress: store.progressMap[movie.id]
                            )
                        }
                        .buttonStyle(.plain)
                        .focused($focusedMovieID, equals: movie.id)
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
            .padding(.horizontal, 40)
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
            .padding(.horizontal, 40)
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

    private var searchField: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField(
                "Search movies...",
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
        .padding(.horizontal, 40)
        .padding(.vertical, 8)
    }

    // MARK: - Empty / Error States

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
            Text("Loading movies...")
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
            Image(systemName: Tab.movies.systemImage)
                .font(.system(size: 64))
                .foregroundStyle(.secondary)
            Text(Tab.movies.title)
                .font(.title)
            Text(Tab.movies.emptyStateMessage)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
    }

    private var emptyMoviesView: some View {
        VStack(spacing: 16) {
            Image(systemName: "film.slash")
                .font(.system(size: 56))
                .foregroundStyle(.secondary)
            if store.isSearching {
                Text("No movies match \"\(store.searchQuery)\"")
                    .foregroundStyle(.secondary)
            } else {
                Text("No movies in this category")
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
    }
}
