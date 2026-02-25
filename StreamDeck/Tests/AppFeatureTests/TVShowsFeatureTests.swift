import ComposableArchitecture
import Database
import XCTest
@testable import AppFeature

@MainActor
final class TVShowsFeatureTests: XCTestCase {

    // MARK: - Helpers

    private func makePlaylist(id: String = "pl-1", name: String = "Test") -> PlaylistRecord {
        PlaylistRecord(id: id, name: name, type: "m3u", url: "http://example.com/pl.m3u")
    }

    private func makeSeries(
        id: String = "s1",
        title: String = "Test Series",
        playlistID: String = "pl-1",
        genre: String? = nil
    ) -> VodItemRecord {
        VodItemRecord(id: id, playlistID: playlistID, title: title, type: "series", genre: genre)
    }

    private func makeEpisode(
        id: String = "e1",
        title: String = "Pilot",
        playlistID: String = "pl-1",
        seriesID: String = "s1",
        seasonNum: Int = 1,
        episodeNum: Int = 1,
        streamURL: String? = "http://example.com/ep.mkv"
    ) -> VodItemRecord {
        VodItemRecord(
            id: id, playlistID: playlistID, title: title, type: "episode",
            streamURL: streamURL, seriesID: seriesID, seasonNum: seasonNum, episodeNum: episodeNum
        )
    }

    // MARK: - Initial State

    func testInitialState_isEmpty() {
        let state = TVShowsFeature.State()
        XCTAssertTrue(state.playlists.isEmpty)
        XCTAssertTrue(state.seriesList.isEmpty)
        XCTAssertTrue(state.displayedSeries.isEmpty)
        XCTAssertNil(state.selectedSeries)
        XCTAssertTrue(state.episodes.isEmpty)
        XCTAssertFalse(state.isLoading)
    }

    // MARK: - OnAppear

    func testOnAppear_loadsPlaylistsAndSeries() async {
        let playlist = makePlaylist()
        let series = [makeSeries(id: "s1", title: "Breaking Bad"), makeSeries(id: "s2", title: "Atlanta")]

        let store = TestStore(initialState: TVShowsFeature.State()) {
            TVShowsFeature()
        } withDependencies: {
            $0.vodListClient.fetchPlaylists = { [playlist] }
            $0.vodListClient.fetchSeries = { _ in series }
            $0.vodListClient.fetchGenres = { _, _ in ["Drama"] }
        }

        await store.send(.onAppear) {
            $0.isLoading = true
        }
        await store.receive(\.playlistsLoaded.success) {
            $0.playlists = [playlist]
            $0.selectedPlaylistID = "pl-1"
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

    func testOnAppear_noPlaylists_showsEmpty() async {
        let store = TestStore(initialState: TVShowsFeature.State()) {
            TVShowsFeature()
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

    // MARK: - Series Tap → Episodes

    func testSeriesTapped_loadsEpisodes() async {
        let series = makeSeries(id: "s1", title: "Breaking Bad")
        let episodes = [
            makeEpisode(id: "e1", title: "Pilot", seriesID: "s1", seasonNum: 1, episodeNum: 1),
            makeEpisode(id: "e2", title: "Cat's in the Bag", seriesID: "s1", seasonNum: 1, episodeNum: 2),
            makeEpisode(id: "e3", title: "Seven Thirty-Seven", seriesID: "s1", seasonNum: 2, episodeNum: 1),
        ]

        let store = TestStore(initialState: TVShowsFeature.State()) {
            TVShowsFeature()
        } withDependencies: {
            $0.vodListClient.fetchEpisodes = { _ in episodes }
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
    }

    func testEpisodesLoaded_noSeasons_showsAll() async {
        // VodItemRecord with nil seasonNum
        let episodeNoSeason = VodItemRecord(
            id: "e1", playlistID: "pl-1", title: "Episode 1", type: "episode",
            streamURL: "http://example.com/ep.mkv", seriesID: "s1", episodeNum: 1
        )

        var state = TVShowsFeature.State()
        state.selectedSeries = makeSeries()
        state.isLoadingEpisodes = true

        let store = TestStore(initialState: state) {
            TVShowsFeature()
        }

        await store.send(.episodesLoaded(.success([episodeNoSeason]))) {
            $0.isLoadingEpisodes = false
            $0.episodes = [episodeNoSeason]
            $0.seasons = []
            $0.displayedEpisodes = [episodeNoSeason]
        }
    }

    // MARK: - Season Selection

    func testSeasonSelected_filtersEpisodes() async {
        let ep1 = makeEpisode(id: "e1", title: "S01E01", seasonNum: 1, episodeNum: 1)
        let ep2 = makeEpisode(id: "e2", title: "S02E01", seasonNum: 2, episodeNum: 1)

        var state = TVShowsFeature.State()
        state.selectedSeries = makeSeries()
        state.episodes = [ep1, ep2]
        state.seasons = [1, 2]
        state.selectedSeason = 1
        state.displayedEpisodes = [ep1]

        let store = TestStore(initialState: state) {
            TVShowsFeature()
        }

        await store.send(.seasonSelected(2)) {
            $0.selectedSeason = 2
            $0.displayedEpisodes = [ep2]
        }
    }

    // MARK: - Episode Tap

    func testEpisodeTapped_presentsVideoPlayer() async {
        let episode = makeEpisode(id: "e1", title: "Pilot", streamURL: "http://example.com/ep.mkv")

        let store = TestStore(initialState: TVShowsFeature.State()) {
            TVShowsFeature()
        }

        await store.send(.episodeTapped(episode)) {
            $0.videoPlayer = VideoPlayerFeature.State(vodItem: episode)
        }
        await store.receive(\.delegate.playEpisode)
    }

    func testEpisodeTapped_noStreamURL_noOp() async {
        let episode = makeEpisode(id: "e1", streamURL: nil)

        let store = TestStore(initialState: TVShowsFeature.State()) {
            TVShowsFeature()
        }

        await store.send(.episodeTapped(episode))
    }

    // MARK: - Back To Series

    func testBackToSeriesTapped_clearsSelection() async {
        var state = TVShowsFeature.State()
        state.selectedSeries = makeSeries()
        state.episodes = [makeEpisode()]
        state.seasons = [1]
        state.selectedSeason = 1
        state.displayedEpisodes = [makeEpisode()]

        let store = TestStore(initialState: state) {
            TVShowsFeature()
        }

        await store.send(.backToSeriesTapped) {
            $0.selectedSeries = nil
            $0.episodes = []
            $0.seasons = []
            $0.selectedSeason = nil
            $0.displayedEpisodes = []
        }
    }

    // MARK: - Genre Filter

    func testGenreSelected_filtersSeries() async {
        var state = TVShowsFeature.State()
        state.seriesList = [
            makeSeries(id: "s1", title: "Drama Show", genre: "Drama"),
            makeSeries(id: "s2", title: "Comedy Show", genre: "Comedy"),
        ]
        state.displayedSeries = state.seriesList

        let store = TestStore(initialState: state) {
            TVShowsFeature()
        }

        await store.send(.genreSelected("Drama")) {
            $0.selectedGenre = "Drama"
            $0.displayedSeries = [state.seriesList[0]]
        }
    }

    // MARK: - Video Player Dismiss

    func testVideoPlayerDismiss_nilsState() async {
        var state = TVShowsFeature.State()
        state.videoPlayer = VideoPlayerFeature.State(
            vodItem: makeEpisode(id: "e1", streamURL: "http://example.com/ep.mkv")
        )

        let store = TestStore(initialState: state) {
            TVShowsFeature()
        }

        await store.send(.videoPlayer(.presented(.delegate(.dismissed)))) {
            $0.videoPlayer = nil
        }
    }

    // MARK: - Retry

    func testRetryTapped_reloadsSeries() async {
        var state = TVShowsFeature.State()
        state.selectedPlaylistID = "pl-1"
        state.errorMessage = "Something failed"

        let store = TestStore(initialState: state) {
            TVShowsFeature()
        } withDependencies: {
            $0.vodListClient.fetchSeries = { _ in [] }
        }

        await store.send(.retryTapped) {
            $0.errorMessage = nil
            $0.isLoading = true
        }
        await store.receive(\.seriesLoaded.success) {
            $0.isLoading = false
            $0.seriesList = []
            $0.displayedSeries = []
        }
    }
}
