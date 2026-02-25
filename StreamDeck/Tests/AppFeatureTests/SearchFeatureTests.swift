import ComposableArchitecture
import Database
import XCTest
@testable import AppFeature

@MainActor
final class SearchFeatureTests: XCTestCase {

    // MARK: - Helpers

    private func makeChannel(
        id: String = "ch-1",
        name: String = "Test Channel"
    ) -> ChannelRecord {
        ChannelRecord(
            id: id, playlistID: "pl-1", name: name, streamURL: "http://example.com/stream",
            isFavorite: false, isDeleted: false
        )
    }

    private func makeMovie(
        id: String = "m-1",
        title: String = "Test Movie",
        streamURL: String? = "http://example.com/movie.mp4"
    ) -> VodItemRecord {
        VodItemRecord(id: id, playlistID: "pl-1", title: title, type: "movie", streamURL: streamURL)
    }

    private func makeSeries(
        id: String = "s-1",
        title: String = "Test Series"
    ) -> VodItemRecord {
        VodItemRecord(id: id, playlistID: "pl-1", title: title, type: "series")
    }

    // MARK: - Initial State

    func testInitialState_isEmpty() {
        let state = SearchFeature.State()
        XCTAssertEqual(state.searchQuery, "")
        XCTAssertTrue(state.channelResults.isEmpty)
        XCTAssertTrue(state.movieResults.isEmpty)
        XCTAssertTrue(state.seriesResults.isEmpty)
        XCTAssertFalse(state.isSearching)
        XCTAssertFalse(state.hasResults)
        XCTAssertFalse(state.hasSearched)
        XCTAssertNil(state.videoPlayer)
    }

    // MARK: - Search Query

    func testSearchQueryChanged_empty_clearsResults() async {
        var state = SearchFeature.State()
        state.searchQuery = "old"
        state.channelResults = [makeChannel()]
        state.movieResults = [makeMovie()]
        state.seriesResults = [makeSeries()]

        let store = TestStore(initialState: state) {
            SearchFeature()
        }

        await store.send(.searchQueryChanged("")) {
            $0.searchQuery = ""
            $0.channelResults = []
            $0.movieResults = []
            $0.seriesResults = []
            $0.isSearching = false
        }
    }

    func testSearchQueryChanged_firesParallelSearches() async {
        let channel = makeChannel(id: "ch-1", name: "ESPN")
        let movie = makeMovie(id: "m-1", title: "Matrix")
        let series = makeSeries(id: "s-1", title: "Breaking Bad")

        let store = TestStore(initialState: SearchFeature.State()) {
            SearchFeature()
        } withDependencies: {
            $0.channelListClient.searchChannels = { _, _ in [channel] }
            $0.vodListClient.searchVod = { _, _, _ in [movie, series] }
        }
        store.exhaustivity = .off

        await store.send(.searchQueryChanged("test")) {
            $0.searchQuery = "test"
            $0.isSearching = true
        }

        await store.skipReceivedActions()

        store.assert {
            $0.isSearching = false
            $0.channelResults = [channel]
            $0.movieResults = [movie]
            $0.seriesResults = [series]
        }
    }

    // MARK: - Channel Results

    func testChannelResultsLoaded_setsChannels() async {
        let channels = [makeChannel(id: "ch-1"), makeChannel(id: "ch-2")]

        var state = SearchFeature.State()
        state.searchQuery = "test"
        state.isSearching = true

        let store = TestStore(initialState: state) {
            SearchFeature()
        }

        await store.send(.channelResultsLoaded(.success(channels))) {
            $0.channelResults = channels
            $0.isSearching = false
        }
    }

    func testChannelResultsLoaded_failure_clearsAndStopsSearching() async {
        var state = SearchFeature.State()
        state.searchQuery = "test"
        state.isSearching = true
        state.channelResults = [makeChannel()]

        let store = TestStore(initialState: state) {
            SearchFeature()
        }

        await store.send(.channelResultsLoaded(.failure(NSError(domain: "test", code: 1)))) {
            $0.channelResults = []
            $0.isSearching = false
        }
    }

    // MARK: - VOD Results

    func testVodResultsLoaded_splitsMoviesAndSeries() async {
        let movie = makeMovie(id: "m-1")
        let series = makeSeries(id: "s-1")

        var state = SearchFeature.State()
        state.searchQuery = "test"
        state.isSearching = true

        let store = TestStore(initialState: state) {
            SearchFeature()
        }

        await store.send(.vodResultsLoaded(.success([movie, series]))) {
            $0.movieResults = [movie]
            $0.seriesResults = [series]
            $0.isSearching = false
        }
    }

    func testVodResultsLoaded_onlyMovies() async {
        let movie = makeMovie(id: "m-1")

        var state = SearchFeature.State()
        state.searchQuery = "test"
        state.isSearching = true

        let store = TestStore(initialState: state) {
            SearchFeature()
        }

        await store.send(.vodResultsLoaded(.success([movie]))) {
            $0.movieResults = [movie]
            $0.seriesResults = []
            $0.isSearching = false
        }
    }

    func testVodResultsLoaded_onlySeries() async {
        let series = makeSeries(id: "s-1")

        var state = SearchFeature.State()
        state.searchQuery = "test"
        state.isSearching = true

        let store = TestStore(initialState: state) {
            SearchFeature()
        }

        await store.send(.vodResultsLoaded(.success([series]))) {
            $0.movieResults = []
            $0.seriesResults = [series]
            $0.isSearching = false
        }
    }

    func testVodResultsLoaded_failure_clearsAndStopsSearching() async {
        var state = SearchFeature.State()
        state.searchQuery = "test"
        state.isSearching = true
        state.movieResults = [makeMovie()]

        let store = TestStore(initialState: state) {
            SearchFeature()
        }

        await store.send(.vodResultsLoaded(.failure(NSError(domain: "test", code: 1)))) {
            $0.movieResults = []
            $0.seriesResults = []
            $0.isSearching = false
        }
    }

    // MARK: - Tapping Items

    func testChannelTapped_presentsVideoPlayer() async {
        let channel = makeChannel(id: "ch-1", name: "ESPN")

        let store = TestStore(initialState: SearchFeature.State()) {
            SearchFeature()
        }

        await store.send(.channelTapped(channel)) {
            $0.videoPlayer = VideoPlayerFeature.State(channel: channel)
        }
        await store.receive(\.delegate.playChannel)
    }

    func testMovieTapped_presentsVideoPlayer() async {
        let movie = makeMovie(id: "m-1", streamURL: "http://example.com/movie.mp4")

        let store = TestStore(initialState: SearchFeature.State()) {
            SearchFeature()
        }

        await store.send(.movieTapped(movie)) {
            $0.videoPlayer = VideoPlayerFeature.State(vodItem: movie)
        }
        await store.receive(\.delegate.playVodItem)
    }

    func testMovieTapped_noStreamURL_noOp() async {
        let movie = makeMovie(id: "m-1", streamURL: nil)

        let store = TestStore(initialState: SearchFeature.State()) {
            SearchFeature()
        }

        await store.send(.movieTapped(movie))
    }

    func testSeriesTapped_sendsDelegate() async {
        let series = makeSeries(id: "s-1", title: "Breaking Bad")

        let store = TestStore(initialState: SearchFeature.State()) {
            SearchFeature()
        }

        await store.send(.seriesTapped(series))
        await store.receive(\.delegate.showSeries)
    }

    // MARK: - Clear

    func testClearTapped_resetsAll() async {
        var state = SearchFeature.State()
        state.searchQuery = "test"
        state.channelResults = [makeChannel()]
        state.movieResults = [makeMovie()]
        state.seriesResults = [makeSeries()]
        state.isSearching = true

        let store = TestStore(initialState: state) {
            SearchFeature()
        }

        await store.send(.clearTapped) {
            $0.searchQuery = ""
            $0.channelResults = []
            $0.movieResults = []
            $0.seriesResults = []
            $0.isSearching = false
        }
    }

    // MARK: - Video Player

    func testVideoPlayerDismiss_nilsState() async {
        var state = SearchFeature.State()
        state.videoPlayer = VideoPlayerFeature.State(
            channel: makeChannel()
        )

        let store = TestStore(initialState: state) {
            SearchFeature()
        }

        await store.send(.videoPlayer(.presented(.delegate(.dismissed)))) {
            $0.videoPlayer = nil
        }
    }

    // MARK: - Computed Properties

    func testHasResults_true_withChannels() {
        var state = SearchFeature.State()
        state.channelResults = [makeChannel()]
        XCTAssertTrue(state.hasResults)
    }

    func testHasResults_true_withMovies() {
        var state = SearchFeature.State()
        state.movieResults = [makeMovie()]
        XCTAssertTrue(state.hasResults)
    }

    func testHasResults_false_whenEmpty() {
        let state = SearchFeature.State()
        XCTAssertFalse(state.hasResults)
    }

    func testHasSearched_true_whenQueryNotEmpty() {
        var state = SearchFeature.State()
        state.searchQuery = "foo"
        XCTAssertTrue(state.hasSearched)
    }
}
