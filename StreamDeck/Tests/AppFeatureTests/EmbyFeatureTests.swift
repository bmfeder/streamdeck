import ComposableArchitecture
import Database
import XCTest
@testable import AppFeature

@MainActor
final class EmbyFeatureTests: XCTestCase {

    // MARK: - Helpers

    private func makeEmbyPlaylist(id: String = "emby-1", name: String = "My Emby") -> PlaylistRecord {
        PlaylistRecord(id: id, name: name, type: "emby", url: "http://emby.local:8096")
    }

    private func makeM3UPlaylist(id: String = "m3u-1", name: String = "IPTV") -> PlaylistRecord {
        PlaylistRecord(id: id, name: name, type: "m3u", url: "http://example.com/pl.m3u")
    }

    private func makeMovie(
        id: String = "m1",
        title: String = "Test Movie",
        playlistID: String = "emby-1",
        streamURL: String? = "http://emby.local:8096/stream/m1",
        genre: String? = nil
    ) -> VodItemRecord {
        VodItemRecord(
            id: id, playlistID: playlistID, title: title, type: "movie",
            streamURL: streamURL, genre: genre
        )
    }

    private func makeSeries(
        id: String = "s1",
        title: String = "Test Series",
        playlistID: String = "emby-1",
        genre: String? = nil
    ) -> VodItemRecord {
        VodItemRecord(id: id, playlistID: playlistID, title: title, type: "series", genre: genre)
    }

    private func makeEpisode(
        id: String = "e1",
        title: String = "Pilot",
        playlistID: String = "emby-1",
        seriesID: String = "s1",
        seasonNum: Int = 1,
        episodeNum: Int = 1,
        streamURL: String? = "http://emby.local:8096/stream/e1"
    ) -> VodItemRecord {
        VodItemRecord(
            id: id, playlistID: playlistID, title: title, type: "episode",
            streamURL: streamURL, seriesID: seriesID, seasonNum: seasonNum, episodeNum: episodeNum
        )
    }

    // MARK: - Initial State

    func testInitialState_isEmpty() {
        let state = EmbyFeature.State()
        XCTAssertTrue(state.embyPlaylists.isEmpty)
        XCTAssertNil(state.selectedPlaylistID)
        XCTAssertEqual(state.contentMode, .movies)
        XCTAssertTrue(state.movies.isEmpty)
        XCTAssertTrue(state.seriesList.isEmpty)
        XCTAssertFalse(state.isLoading)
        XCTAssertNil(state.errorMessage)
        XCTAssertNil(state.videoPlayer)
    }

    // MARK: - OnAppear

    func testOnAppear_loadsEmbyPlaylistsAndMovies() async {
        let embyPlaylist = makeEmbyPlaylist()
        let m3uPlaylist = makeM3UPlaylist()
        let movies = [makeMovie(id: "m1", title: "Inception"), makeMovie(id: "m2", title: "Avatar")]

        let store = TestStore(initialState: EmbyFeature.State()) {
            EmbyFeature()
        } withDependencies: {
            $0.vodListClient.fetchPlaylists = { [embyPlaylist, m3uPlaylist] }
            $0.vodListClient.fetchMovies = { _ in movies }
            $0.vodListClient.fetchGenres = { _, _ in ["Action", "Sci-Fi"] }
            $0.watchProgressClient.getProgressBatch = { _ in [:] }
        }

        await store.send(.onAppear) {
            $0.isLoading = true
        }
        await store.receive(\.playlistsLoaded.success) {
            $0.embyPlaylists = [embyPlaylist]
            $0.selectedPlaylistID = "emby-1"
        }
        await store.receive(\.moviesLoaded.success) {
            $0.isLoading = false
            $0.movies = movies
            $0.displayedMovies = movies
        }
        await store.receive(\.genresLoaded.success) {
            $0.genres = ["All", "Action", "Sci-Fi"]
        }
        await store.receive(\.progressMapLoaded)
    }

    func testOnAppear_noEmbyPlaylists_showsEmpty() async {
        let m3uPlaylist = makeM3UPlaylist()

        let store = TestStore(initialState: EmbyFeature.State()) {
            EmbyFeature()
        } withDependencies: {
            $0.vodListClient.fetchPlaylists = { [m3uPlaylist] }
        }

        await store.send(.onAppear) {
            $0.isLoading = true
        }
        await store.receive(\.playlistsLoaded.success) {
            $0.isLoading = false
        }
    }

    func testOnAppear_alreadyLoaded_noOp() async {
        var state = EmbyFeature.State()
        state.embyPlaylists = [makeEmbyPlaylist()]

        let store = TestStore(initialState: state) {
            EmbyFeature()
        }

        await store.send(.onAppear)
    }

    // MARK: - Playlist Selection

    func testPlaylistSelected_reloadsContent() async {
        var state = EmbyFeature.State()
        state.embyPlaylists = [makeEmbyPlaylist(id: "emby-1"), makeEmbyPlaylist(id: "emby-2", name: "Other")]
        state.selectedPlaylistID = "emby-1"
        state.movies = [makeMovie()]

        let store = TestStore(initialState: state) {
            EmbyFeature()
        } withDependencies: {
            $0.vodListClient.fetchMovies = { _ in [] }
            $0.vodListClient.fetchGenres = { _, _ in [] }
            $0.watchProgressClient.getProgressBatch = { _ in [:] }
        }

        await store.send(.playlistSelected("emby-2")) {
            $0.selectedPlaylistID = "emby-2"
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
        await store.receive(\.progressMapLoaded)
    }

    // MARK: - Content Mode Switch

    func testContentModeChanged_switchesToTVShows() async {
        var state = EmbyFeature.State()
        state.embyPlaylists = [makeEmbyPlaylist()]
        state.selectedPlaylistID = "emby-1"
        state.contentMode = .movies

        let series = [makeSeries(id: "s1", title: "Breaking Bad")]

        let store = TestStore(initialState: state) {
            EmbyFeature()
        } withDependencies: {
            $0.vodListClient.fetchSeries = { _ in series }
            $0.vodListClient.fetchGenres = { _, _ in ["Drama"] }
        }

        await store.send(.contentModeChanged(.tvShows)) {
            $0.contentMode = .tvShows
            $0.isLoading = true
            $0.selectedGenre = "All"
        }
        await store.receive(\.seriesLoaded.success) {
            $0.isLoading = false
            $0.seriesList = series
            $0.displayedSeries = series
        }
        await store.receive(\.genresLoaded.success) {
            $0.genres = ["All", "Drama"]
        }
    }

    func testContentModeChanged_sameMode_noOp() async {
        var state = EmbyFeature.State()
        state.contentMode = .movies

        let store = TestStore(initialState: state) {
            EmbyFeature()
        }

        await store.send(.contentModeChanged(.movies))
    }

    // MARK: - Movies: Genre Filter

    func testGenreSelected_filtersMovies() async {
        var state = EmbyFeature.State()
        state.contentMode = .movies
        state.movies = [
            makeMovie(id: "m1", title: "Action Movie", genre: "Action"),
            makeMovie(id: "m2", title: "Drama Film", genre: "Drama"),
        ]
        state.displayedMovies = state.movies

        let store = TestStore(initialState: state) {
            EmbyFeature()
        }

        await store.send(.genreSelected("Action")) {
            $0.selectedGenre = "Action"
            $0.displayedMovies = [state.movies[0]]
        }
    }

    // MARK: - Movies: Search

    func testSearchQueryChanged_searchesMovies() async {
        var state = EmbyFeature.State()
        state.contentMode = .movies
        state.selectedPlaylistID = "emby-1"

        let results = [makeMovie(id: "m1", title: "Matrix")]

        let store = TestStore(initialState: state) {
            EmbyFeature()
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

    // MARK: - Movies: Tap

    func testMovieTapped_presentsVideoPlayer() async {
        let movie = makeMovie(id: "m1", title: "Inception")

        let store = TestStore(initialState: EmbyFeature.State()) {
            EmbyFeature()
        }

        await store.send(.movieTapped(movie)) {
            $0.videoPlayer = VideoPlayerFeature.State(vodItem: movie)
        }
        await store.receive(\.delegate.playMovie)
    }

    func testMovieTapped_noStreamURL_noOp() async {
        let movie = makeMovie(id: "m1", streamURL: nil)

        let store = TestStore(initialState: EmbyFeature.State()) {
            EmbyFeature()
        }

        await store.send(.movieTapped(movie))
    }

    // MARK: - TV Shows: Series Tap → Episodes

    func testSeriesTapped_loadsEpisodes() async {
        let series = makeSeries(id: "s1", title: "Breaking Bad")
        let episodes = [
            makeEpisode(id: "e1", title: "Pilot", seasonNum: 1, episodeNum: 1),
            makeEpisode(id: "e2", title: "Cat's in the Bag", seasonNum: 1, episodeNum: 2),
            makeEpisode(id: "e3", title: "Seven Thirty-Seven", seasonNum: 2, episodeNum: 1),
        ]

        let store = TestStore(initialState: EmbyFeature.State()) {
            EmbyFeature()
        } withDependencies: {
            $0.vodListClient.fetchEpisodes = { _ in episodes }
            $0.watchProgressClient.getProgressBatch = { _ in [:] }
        }

        await store.send(.seriesTapped(series)) {
            $0.selectedSeries = series
            $0.isLoadingEpisodes = true
        }
        await store.receive(\.episodesLoaded.success) {
            $0.isLoadingEpisodes = false
            $0.episodes = episodes
            $0.seasons = [1, 2]
            $0.selectedSeason = 1
            $0.displayedEpisodes = [episodes[0], episodes[1]]
        }
        await store.receive(\.progressMapLoaded)
    }

    // MARK: - TV Shows: Season Selection

    func testSeasonSelected_filtersEpisodes() async {
        let ep1 = makeEpisode(id: "e1", title: "S01E01", seasonNum: 1, episodeNum: 1)
        let ep2 = makeEpisode(id: "e2", title: "S02E01", seasonNum: 2, episodeNum: 1)

        var state = EmbyFeature.State()
        state.selectedSeries = makeSeries()
        state.episodes = [ep1, ep2]
        state.seasons = [1, 2]
        state.selectedSeason = 1
        state.displayedEpisodes = [ep1]

        let store = TestStore(initialState: state) {
            EmbyFeature()
        }

        await store.send(.seasonSelected(2)) {
            $0.selectedSeason = 2
            $0.displayedEpisodes = [ep2]
        }
    }

    // MARK: - TV Shows: Episode Tap

    func testEpisodeTapped_presentsVideoPlayer() async {
        let episode = makeEpisode(id: "e1", title: "Pilot")

        let store = TestStore(initialState: EmbyFeature.State()) {
            EmbyFeature()
        }

        await store.send(.episodeTapped(episode)) {
            $0.videoPlayer = VideoPlayerFeature.State(vodItem: episode)
        }
        await store.receive(\.delegate.playEpisode)
    }

    func testEpisodeTapped_noStreamURL_noOp() async {
        let episode = makeEpisode(id: "e1", streamURL: nil)

        let store = TestStore(initialState: EmbyFeature.State()) {
            EmbyFeature()
        }

        await store.send(.episodeTapped(episode))
    }

    // MARK: - Back to Series

    func testBackToSeriesTapped_clearsSelection() async {
        var state = EmbyFeature.State()
        state.selectedSeries = makeSeries()
        state.episodes = [makeEpisode()]
        state.seasons = [1]
        state.selectedSeason = 1
        state.displayedEpisodes = [makeEpisode()]

        let store = TestStore(initialState: state) {
            EmbyFeature()
        }

        await store.send(.backToSeriesTapped) {
            $0.selectedSeries = nil
            $0.episodes = []
            $0.seasons = []
            $0.selectedSeason = nil
            $0.displayedEpisodes = []
        }
    }

    // MARK: - Video Player Dismiss

    func testVideoPlayerDismiss_nilsState() async {
        var state = EmbyFeature.State()
        state.videoPlayer = VideoPlayerFeature.State(
            vodItem: makeMovie(id: "m1", streamURL: "http://emby.local:8096/stream/m1")
        )

        let store = TestStore(initialState: state) {
            EmbyFeature()
        }

        await store.send(.videoPlayer(.presented(.delegate(.dismissed)))) {
            $0.videoPlayer = nil
        }
    }

    // MARK: - Retry

    func testRetryTapped_reloadsContent() async {
        var state = EmbyFeature.State()
        state.selectedPlaylistID = "emby-1"
        state.contentMode = .movies
        state.errorMessage = "Something failed"

        let store = TestStore(initialState: state) {
            EmbyFeature()
        } withDependencies: {
            $0.vodListClient.fetchMovies = { _ in [] }
            $0.vodListClient.fetchGenres = { _, _ in [] }
            $0.watchProgressClient.getProgressBatch = { _ in [:] }
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
        await store.receive(\.genresLoaded.success) {
            $0.genres = ["All"]
        }
        await store.receive(\.progressMapLoaded)
    }

    // MARK: - Progress Map

    func testProgressMapLoaded_computesFractions() async {
        let store = TestStore(initialState: EmbyFeature.State()) {
            EmbyFeature()
        }

        let batch: [String: WatchProgressRecord] = [
            "m1": WatchProgressRecord(contentID: "m1", positionMs: 1_800_000, durationMs: 3_600_000, updatedAt: 1_700_000_000),
            "m2": WatchProgressRecord(contentID: "m2", positionMs: 600_000, durationMs: 7_200_000, updatedAt: 1_700_000_000),
        ]

        await store.send(.progressMapLoaded(batch)) {
            $0.progressMap = [
                "m1": 0.5,
                "m2": Double(600_000) / Double(7_200_000),
            ]
        }
    }

    // MARK: - Playlists Loaded Failure

    func testPlaylistsLoaded_failure_setsError() async {
        let store = TestStore(initialState: EmbyFeature.State()) {
            EmbyFeature()
        } withDependencies: {
            $0.vodListClient.fetchPlaylists = { throw NSError(domain: "test", code: 1, userInfo: [NSLocalizedDescriptionKey: "Network error"]) }
        }

        await store.send(.onAppear) {
            $0.isLoading = true
        }
        await store.receive(\.playlistsLoaded.failure) {
            $0.isLoading = false
            $0.errorMessage = "Failed to load playlists: Network error"
        }
    }
}
