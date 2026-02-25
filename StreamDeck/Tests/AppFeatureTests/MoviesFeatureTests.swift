import ComposableArchitecture
import Database
import XCTest
@testable import AppFeature

@MainActor
final class MoviesFeatureTests: XCTestCase {

    // MARK: - Helpers

    private func makePlaylist(id: String = "pl-1", name: String = "Test") -> PlaylistRecord {
        PlaylistRecord(id: id, name: name, type: "m3u", url: "http://example.com/pl.m3u")
    }

    private func makeMovie(
        id: String = "m1",
        title: String = "Test Movie",
        playlistID: String = "pl-1",
        streamURL: String? = "http://example.com/movie.mp4",
        genre: String? = nil,
        year: Int? = nil,
        rating: Double? = nil
    ) -> VodItemRecord {
        VodItemRecord(
            id: id, playlistID: playlistID, title: title, type: "movie",
            streamURL: streamURL, year: year, rating: rating, genre: genre
        )
    }

    // MARK: - Initial State

    func testInitialState_isEmpty() {
        let state = MoviesFeature.State()
        XCTAssertTrue(state.playlists.isEmpty)
        XCTAssertTrue(state.movies.isEmpty)
        XCTAssertTrue(state.displayedMovies.isEmpty)
        XCTAssertFalse(state.isLoading)
        XCTAssertNil(state.errorMessage)
        XCTAssertNil(state.videoPlayer)
    }

    // MARK: - OnAppear

    func testOnAppear_loadsPlaylistsAndMovies() async {
        let playlist = makePlaylist()
        let movies = [makeMovie(id: "m1", title: "Inception"), makeMovie(id: "m2", title: "Avatar")]

        let store = TestStore(initialState: MoviesFeature.State()) {
            MoviesFeature()
        } withDependencies: {
            $0.vodListClient.fetchPlaylists = { [playlist] }
            $0.vodListClient.fetchMovies = { _ in movies }
            $0.vodListClient.fetchGenres = { _, _ in ["Action", "Sci-Fi"] }
        }

        await store.send(.onAppear) {
            $0.isLoading = true
        }
        await store.receive(\.playlistsLoaded.success) {
            $0.playlists = [playlist]
            $0.selectedPlaylistID = "pl-1"
        }
        await store.receive(\.moviesLoaded.success) {
            $0.isLoading = false
            $0.movies = movies
            $0.displayedMovies = movies
        }
        await store.receive(\.genresLoaded.success) {
            $0.genres = ["All", "Action", "Sci-Fi"]
        }
    }

    func testOnAppear_noPlaylists_showsEmpty() async {
        let store = TestStore(initialState: MoviesFeature.State()) {
            MoviesFeature()
        } withDependencies: {
            $0.vodListClient.fetchPlaylists = { [] }
        }

        await store.send(.onAppear) {
            $0.isLoading = true
        }
        await store.receive(\.playlistsLoaded.success) {
            $0.isLoading = false
        }
    }

    func testOnAppear_alreadyLoaded_noOp() async {
        var state = MoviesFeature.State()
        state.playlists = [makePlaylist()]

        let store = TestStore(initialState: state) {
            MoviesFeature()
        }

        await store.send(.onAppear)
    }

    // MARK: - Playlist Selection

    func testPlaylistSelected_reloadsMovies() async {
        var state = MoviesFeature.State()
        state.playlists = [makePlaylist(id: "pl-1"), makePlaylist(id: "pl-2", name: "Other")]
        state.selectedPlaylistID = "pl-1"
        state.movies = [makeMovie()]

        let store = TestStore(initialState: state) {
            MoviesFeature()
        } withDependencies: {
            $0.vodListClient.fetchMovies = { _ in [] }
            $0.vodListClient.fetchGenres = { _, _ in [] }
        }

        await store.send(.playlistSelected("pl-2")) {
            $0.selectedPlaylistID = "pl-2"
            $0.isLoading = true
            $0.selectedGenre = "All"
        }
        await store.receive(\.moviesLoaded.success) {
            $0.isLoading = false
            $0.movies = []
            $0.displayedMovies = []
        }
        await store.receive(\.genresLoaded.success) {
            $0.genres = ["All"]
        }
    }

    // MARK: - Genre Filter

    func testGenreSelected_filtersMovies() async {
        var state = MoviesFeature.State()
        state.movies = [
            makeMovie(id: "m1", title: "Action Movie", genre: "Action"),
            makeMovie(id: "m2", title: "Drama Film", genre: "Drama"),
            makeMovie(id: "m3", title: "Sci-Fi Action", genre: "Action, Sci-Fi"),
        ]
        state.displayedMovies = state.movies
        state.genres = ["All", "Action", "Drama", "Sci-Fi"]

        let store = TestStore(initialState: state) {
            MoviesFeature()
        }

        await store.send(.genreSelected("Action")) {
            $0.selectedGenre = "Action"
            $0.displayedMovies = [
                state.movies[0],
                state.movies[2],
            ]
        }
    }

    func testGenreSelected_all_showsAllMovies() async {
        var state = MoviesFeature.State()
        state.movies = [makeMovie(id: "m1"), makeMovie(id: "m2")]
        state.displayedMovies = [makeMovie(id: "m1")]
        state.selectedGenre = "Action"

        let store = TestStore(initialState: state) {
            MoviesFeature()
        }

        await store.send(.genreSelected("All")) {
            $0.selectedGenre = "All"
            $0.displayedMovies = state.movies
        }
    }

    // MARK: - Search

    func testSearchQueryChanged_triggersSearch() async {
        var state = MoviesFeature.State()
        state.selectedPlaylistID = "pl-1"

        let results = [makeMovie(id: "m1", title: "Matrix")]

        let store = TestStore(initialState: state) {
            MoviesFeature()
        } withDependencies: {
            $0.vodListClient.searchVod = { _, _, _ in results }
        }

        await store.send(.searchQueryChanged("Matrix")) {
            $0.searchQuery = "Matrix"
        }
        await store.receive(\.searchResultsLoaded.success) {
            $0.searchResults = results
            $0.displayedMovies = results
        }
    }

    // MARK: - Movie Tap

    func testMovieTapped_presentsVideoPlayer() async {
        let movie = makeMovie(id: "m1", title: "Inception", streamURL: "http://example.com/inception.mp4")

        let store = TestStore(initialState: MoviesFeature.State()) {
            MoviesFeature()
        }

        await store.send(.movieTapped(movie)) {
            $0.videoPlayer = VideoPlayerFeature.State(vodItem: movie)
        }
        await store.receive(\.delegate.playMovie)
    }

    func testMovieTapped_noStreamURL_noOp() async {
        let movie = makeMovie(id: "m1", streamURL: nil)

        let store = TestStore(initialState: MoviesFeature.State()) {
            MoviesFeature()
        }

        await store.send(.movieTapped(movie))
    }

    // MARK: - Video Player Dismiss

    func testVideoPlayerDismiss_nilsState() async {
        var state = MoviesFeature.State()
        state.videoPlayer = VideoPlayerFeature.State(
            vodItem: makeMovie(id: "m1", streamURL: "http://example.com/movie.mp4")
        )

        let store = TestStore(initialState: state) {
            MoviesFeature()
        }

        await store.send(.videoPlayer(.presented(.delegate(.dismissed)))) {
            $0.videoPlayer = nil
        }
    }

    // MARK: - Retry

    func testRetryTapped_reloadsMovies() async {
        var state = MoviesFeature.State()
        state.selectedPlaylistID = "pl-1"
        state.errorMessage = "Something failed"

        let store = TestStore(initialState: state) {
            MoviesFeature()
        } withDependencies: {
            $0.vodListClient.fetchMovies = { _ in [] }
        }

        await store.send(.retryTapped) {
            $0.errorMessage = nil
            $0.isLoading = true
        }
        await store.receive(\.moviesLoaded.success) {
            $0.isLoading = false
            $0.movies = []
            $0.displayedMovies = []
        }
    }
}
