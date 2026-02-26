import ComposableArchitecture
import Database
import XCTest
@testable import AppFeature

@MainActor
final class SearchFeatureTests: XCTestCase {

    // MARK: - Helpers

    private func makeChannel(
        id: String = "ch-1",
        name: String = "Test Channel",
        epgID: String? = nil
    ) -> ChannelRecord {
        ChannelRecord(
            id: id, playlistID: "pl-1", name: name, streamURL: "http://example.com/stream",
            epgID: epgID, isFavorite: false, isDeleted: false
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

    private func makeProgram(
        id: String = "p-1",
        channelEpgID: String = "epg-1",
        title: String = "News at 9",
        startTime: Int = 1000,
        endTime: Int = 2000,
        category: String? = "News"
    ) -> EpgProgramRecord {
        EpgProgramRecord(
            id: id, channelEpgID: channelEpgID, title: title,
            startTime: startTime, endTime: endTime, category: category
        )
    }

    // MARK: - Initial State

    func testInitialState_isEmpty() {
        let state = SearchFeature.State()
        XCTAssertEqual(state.searchQuery, "")
        XCTAssertTrue(state.channelResults.isEmpty)
        XCTAssertTrue(state.movieResults.isEmpty)
        XCTAssertTrue(state.seriesResults.isEmpty)
        XCTAssertTrue(state.programResults.isEmpty)
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
        state.programResults = [makeProgram()]
        state.pendingSearchCount = 2

        let store = TestStore(initialState: state) {
            SearchFeature()
        }

        await store.send(.searchQueryChanged("")) {
            $0.searchQuery = ""
            $0.channelResults = []
            $0.movieResults = []
            $0.seriesResults = []
            $0.programResults = []
            $0.isSearching = false
            $0.pendingSearchCount = 0
        }
    }

    func testSearchQueryChanged_firesParallelSearches() async {
        let channel = makeChannel(id: "ch-1", name: "ESPN")
        let movie = makeMovie(id: "m-1", title: "Matrix")
        let series = makeSeries(id: "s-1", title: "Breaking Bad")
        let program = makeProgram(id: "p-1", title: "Sports Center")

        let store = TestStore(initialState: SearchFeature.State()) {
            SearchFeature()
        } withDependencies: {
            $0.channelListClient.searchChannels = { _, _ in [channel] }
            $0.vodListClient.searchVod = { _, _, _ in [movie, series] }
            $0.epgClient.searchPrograms = { _ in [program] }
        }
        store.exhaustivity = .off

        await store.send(.searchQueryChanged("test")) {
            $0.searchQuery = "test"
            $0.isSearching = true
            $0.pendingSearchCount = 3
        }

        await store.skipReceivedActions()

        store.assert {
            $0.isSearching = false
            $0.pendingSearchCount = 0
            $0.channelResults = [channel]
            $0.movieResults = [movie]
            $0.seriesResults = [series]
            $0.programResults = [program]
        }
    }

    // MARK: - Channel Results

    func testChannelResultsLoaded_setsChannels() async {
        let channels = [makeChannel(id: "ch-1"), makeChannel(id: "ch-2")]

        var state = SearchFeature.State()
        state.searchQuery = "test"
        state.isSearching = true
        state.pendingSearchCount = 1

        let store = TestStore(initialState: state) {
            SearchFeature()
        }

        await store.send(.channelResultsLoaded(.success(channels))) {
            $0.channelResults = channels
            $0.pendingSearchCount = 0
            $0.isSearching = false
        }
    }

    func testChannelResultsLoaded_failure_clearsAndStopsSearching() async {
        var state = SearchFeature.State()
        state.searchQuery = "test"
        state.isSearching = true
        state.pendingSearchCount = 1
        state.channelResults = [makeChannel()]

        let store = TestStore(initialState: state) {
            SearchFeature()
        }

        await store.send(.channelResultsLoaded(.failure(NSError(domain: "test", code: 1)))) {
            $0.channelResults = []
            $0.pendingSearchCount = 0
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
        state.pendingSearchCount = 1

        let store = TestStore(initialState: state) {
            SearchFeature()
        }

        await store.send(.vodResultsLoaded(.success([movie, series]))) {
            $0.movieResults = [movie]
            $0.seriesResults = [series]
            $0.pendingSearchCount = 0
            $0.isSearching = false
        }
    }

    func testVodResultsLoaded_onlyMovies() async {
        let movie = makeMovie(id: "m-1")

        var state = SearchFeature.State()
        state.searchQuery = "test"
        state.isSearching = true
        state.pendingSearchCount = 1

        let store = TestStore(initialState: state) {
            SearchFeature()
        }

        await store.send(.vodResultsLoaded(.success([movie]))) {
            $0.movieResults = [movie]
            $0.seriesResults = []
            $0.pendingSearchCount = 0
            $0.isSearching = false
        }
    }

    func testVodResultsLoaded_onlySeries() async {
        let series = makeSeries(id: "s-1")

        var state = SearchFeature.State()
        state.searchQuery = "test"
        state.isSearching = true
        state.pendingSearchCount = 1

        let store = TestStore(initialState: state) {
            SearchFeature()
        }

        await store.send(.vodResultsLoaded(.success([series]))) {
            $0.movieResults = []
            $0.seriesResults = [series]
            $0.pendingSearchCount = 0
            $0.isSearching = false
        }
    }

    func testVodResultsLoaded_failure_clearsAndStopsSearching() async {
        var state = SearchFeature.State()
        state.searchQuery = "test"
        state.isSearching = true
        state.pendingSearchCount = 1
        state.movieResults = [makeMovie()]

        let store = TestStore(initialState: state) {
            SearchFeature()
        }

        await store.send(.vodResultsLoaded(.failure(NSError(domain: "test", code: 1)))) {
            $0.movieResults = []
            $0.seriesResults = []
            $0.pendingSearchCount = 0
            $0.isSearching = false
        }
    }

    // MARK: - EPG Results

    func testEpgResultsLoaded_setsPrograms() async {
        let programs = [makeProgram(id: "p-1"), makeProgram(id: "p-2")]

        var state = SearchFeature.State()
        state.searchQuery = "test"
        state.isSearching = true
        state.pendingSearchCount = 1

        let store = TestStore(initialState: state) {
            SearchFeature()
        }

        await store.send(.epgResultsLoaded(.success(programs))) {
            $0.programResults = programs
            $0.pendingSearchCount = 0
            $0.isSearching = false
        }
    }

    func testEpgResultsLoaded_failure_clears() async {
        var state = SearchFeature.State()
        state.searchQuery = "test"
        state.isSearching = true
        state.pendingSearchCount = 1
        state.programResults = [makeProgram()]

        let store = TestStore(initialState: state) {
            SearchFeature()
        }

        await store.send(.epgResultsLoaded(.failure(NSError(domain: "test", code: 1)))) {
            $0.programResults = []
            $0.pendingSearchCount = 0
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

    func testProgramTapped_resolvesChannelAndPlays() async {
        let program = makeProgram(channelEpgID: "epg-cnn")
        let channel = makeChannel(id: "ch-cnn", name: "CNN", epgID: "epg-cnn")

        let store = TestStore(initialState: SearchFeature.State()) {
            SearchFeature()
        } withDependencies: {
            $0.channelListClient.fetchByEpgID = { _ in channel }
        }
        store.exhaustivity = .off

        await store.send(.programTapped(program))
        await store.receive(\.channelTapped) {
            $0.videoPlayer = VideoPlayerFeature.State(channel: channel)
        }
        await store.skipReceivedActions()
    }

    func testProgramTapped_noChannel_noOp() async {
        let program = makeProgram(channelEpgID: "epg-unknown")

        let store = TestStore(initialState: SearchFeature.State()) {
            SearchFeature()
        } withDependencies: {
            $0.channelListClient.fetchByEpgID = { _ in nil }
        }

        await store.send(.programTapped(program))
    }

    // MARK: - Clear

    func testClearTapped_resetsAll() async {
        var state = SearchFeature.State()
        state.searchQuery = "test"
        state.channelResults = [makeChannel()]
        state.movieResults = [makeMovie()]
        state.seriesResults = [makeSeries()]
        state.programResults = [makeProgram()]
        state.isSearching = true
        state.pendingSearchCount = 2

        let store = TestStore(initialState: state) {
            SearchFeature()
        }

        await store.send(.clearTapped) {
            $0.searchQuery = ""
            $0.channelResults = []
            $0.movieResults = []
            $0.seriesResults = []
            $0.programResults = []
            $0.isSearching = false
            $0.pendingSearchCount = 0
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

    func testHasResults_true_withPrograms() {
        var state = SearchFeature.State()
        state.programResults = [makeProgram()]
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

    // MARK: - Pending Search Count

    func testIsSearching_staysTrueUntilAllResults() async {
        var state = SearchFeature.State()
        state.searchQuery = "test"
        state.isSearching = true
        state.pendingSearchCount = 3

        let store = TestStore(initialState: state) {
            SearchFeature()
        }

        // First result: still 2 pending
        await store.send(.channelResultsLoaded(.success([makeChannel()]))) {
            $0.channelResults = [self.makeChannel()]
            $0.pendingSearchCount = 2
        }

        // Second result: still 1 pending
        await store.send(.vodResultsLoaded(.success([]))) {
            $0.movieResults = []
            $0.seriesResults = []
            $0.pendingSearchCount = 1
        }

        // Third result: now isSearching = false
        await store.send(.epgResultsLoaded(.success([]))) {
            $0.programResults = []
            $0.pendingSearchCount = 0
            $0.isSearching = false
        }
    }
}
