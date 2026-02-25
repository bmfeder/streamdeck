import ComposableArchitecture
import Database
import XCTest
@testable import AppFeature

@MainActor
final class HomeFeatureTests: XCTestCase {

    // MARK: - Helpers

    private func makeMovie(
        id: String = "m1",
        title: String = "Test Movie",
        streamURL: String? = "http://example.com/movie.mp4"
    ) -> VodItemRecord {
        VodItemRecord(id: id, playlistID: "pl-1", title: title, type: "movie", streamURL: streamURL)
    }

    private func makeChannel(
        id: String = "ch-1",
        name: String = "Test Channel",
        epgID: String? = "epg-1"
    ) -> ChannelRecord {
        ChannelRecord(
            id: id, playlistID: "pl-1", name: name, streamURL: "http://example.com/stream",
            epgID: epgID, isFavorite: true, isDeleted: false
        )
    }

    private func makeProgressRecord(
        contentID: String,
        positionMs: Int = 1_800_000,
        durationMs: Int = 3_600_000
    ) -> WatchProgressRecord {
        WatchProgressRecord(
            contentID: contentID, positionMs: positionMs,
            durationMs: durationMs, updatedAt: 1_700_000_000
        )
    }

    private func makeContinueWatchingItem(
        vodItem: VodItemRecord,
        progress: Double = 0.5,
        positionMs: Int = 1_800_000
    ) -> HomeFeature.ContinueWatchingItem {
        HomeFeature.ContinueWatchingItem(
            vodItem: vodItem, progress: progress, positionMs: positionMs
        )
    }

    // MARK: - Initial State

    func testInitialState_isEmpty() {
        let state = HomeFeature.State()
        XCTAssertTrue(state.continueWatchingItems.isEmpty)
        XCTAssertTrue(state.favoriteChannels.isEmpty)
        XCTAssertTrue(state.nowPlaying.isEmpty)
        XCTAssertFalse(state.isLoading)
        XCTAssertNil(state.videoPlayer)
    }

    // MARK: - OnAppear (parallel effects — use exhaustivity .off)

    func testOnAppear_loadsContinueWatchingAndFavorites() async {
        let movie = makeMovie(id: "m1", title: "Inception")
        let channel = makeChannel(id: "ch-1", name: "ESPN")
        let progressRecord = makeProgressRecord(contentID: "m1")

        let store = TestStore(initialState: HomeFeature.State()) {
            HomeFeature()
        } withDependencies: {
            $0.watchProgressClient.getUnfinished = { _ in [progressRecord] }
            $0.vodListClient.fetchVodItemsByIDs = { _ in [movie] }
            $0.channelListClient.fetchFavorites = { [channel] }
            $0.epgClient.fetchNowPlayingBatch = { _ in [:] }
        }
        store.exhaustivity = .off

        await store.send(.onAppear) {
            $0.isLoading = true
        }

        await store.skipReceivedActions()

        // Verify final state after all parallel effects complete
        store.assert {
            $0.isLoading = false
            $0.continueWatchingItems = [
                HomeFeature.ContinueWatchingItem(vodItem: movie, progress: 0.5, positionMs: 1_800_000)
            ]
            $0.favoriteChannels = [channel]
        }
    }

    func testOnAppear_noContinueWatching_showsFavoritesOnly() async {
        let channel = makeChannel()

        let store = TestStore(initialState: HomeFeature.State()) {
            HomeFeature()
        } withDependencies: {
            $0.watchProgressClient.getUnfinished = { _ in [] }
            $0.channelListClient.fetchFavorites = { [channel] }
            $0.epgClient.fetchNowPlayingBatch = { _ in [:] }
        }
        store.exhaustivity = .off

        await store.send(.onAppear) {
            $0.isLoading = true
        }

        await store.skipReceivedActions()

        store.assert {
            $0.isLoading = false
            $0.continueWatchingItems = []
            $0.favoriteChannels = [channel]
        }
    }

    func testOnAppear_noFavorites_showsContinueWatchingOnly() async {
        let movie = makeMovie(id: "m1")
        let progressRecord = makeProgressRecord(contentID: "m1")

        let store = TestStore(initialState: HomeFeature.State()) {
            HomeFeature()
        } withDependencies: {
            $0.watchProgressClient.getUnfinished = { _ in [progressRecord] }
            $0.vodListClient.fetchVodItemsByIDs = { _ in [movie] }
            $0.channelListClient.fetchFavorites = { [] }
        }
        store.exhaustivity = .off

        await store.send(.onAppear) {
            $0.isLoading = true
        }

        await store.skipReceivedActions()

        store.assert {
            $0.isLoading = false
            $0.continueWatchingItems = [
                HomeFeature.ContinueWatchingItem(vodItem: movie, progress: 0.5, positionMs: 1_800_000)
            ]
            $0.favoriteChannels = []
        }
    }

    func testOnAppear_bothEmpty_showsEmptyState() async {
        let store = TestStore(initialState: HomeFeature.State()) {
            HomeFeature()
        } withDependencies: {
            $0.watchProgressClient.getUnfinished = { _ in [] }
            $0.channelListClient.fetchFavorites = { [] }
        }
        store.exhaustivity = .off

        await store.send(.onAppear) {
            $0.isLoading = true
        }

        await store.skipReceivedActions()

        store.assert {
            $0.isLoading = false
            $0.continueWatchingItems = []
            $0.favoriteChannels = []
        }
    }

    func testOnAppear_alwaysReloads() async {
        var state = HomeFeature.State()
        state.continueWatchingItems = [makeContinueWatchingItem(vodItem: makeMovie())]
        state.favoriteChannels = [makeChannel()]

        let store = TestStore(initialState: state) {
            HomeFeature()
        } withDependencies: {
            $0.watchProgressClient.getUnfinished = { _ in [] }
            $0.channelListClient.fetchFavorites = { [] }
        }
        store.exhaustivity = .off

        await store.send(.onAppear) {
            $0.isLoading = true
        }

        await store.skipReceivedActions()

        store.assert {
            $0.isLoading = false
            $0.continueWatchingItems = []
            $0.favoriteChannels = []
        }
    }

    // MARK: - Continue Watching

    func testContinueWatching_computesProgress() async {
        let movie = makeMovie(id: "m1")
        let progressRecord = WatchProgressRecord(
            contentID: "m1", positionMs: 900_000, durationMs: 3_600_000, updatedAt: 1_700_000_000
        )

        let store = TestStore(initialState: HomeFeature.State()) {
            HomeFeature()
        } withDependencies: {
            $0.watchProgressClient.getUnfinished = { _ in [progressRecord] }
            $0.vodListClient.fetchVodItemsByIDs = { _ in [movie] }
            $0.channelListClient.fetchFavorites = { [] }
        }
        store.exhaustivity = .off

        await store.send(.onAppear) {
            $0.isLoading = true
        }

        await store.skipReceivedActions()

        store.assert {
            $0.isLoading = false
            $0.continueWatchingItems = [
                HomeFeature.ContinueWatchingItem(vodItem: movie, progress: 0.25, positionMs: 900_000)
            ]
        }
    }

    func testContinueWatching_filtersOutMissingVodItems() async {
        let movie = makeMovie(id: "m1")
        let progress1 = makeProgressRecord(contentID: "m1")
        let progress2 = makeProgressRecord(contentID: "m-deleted")

        let store = TestStore(initialState: HomeFeature.State()) {
            HomeFeature()
        } withDependencies: {
            $0.watchProgressClient.getUnfinished = { _ in [progress1, progress2] }
            $0.vodListClient.fetchVodItemsByIDs = { _ in [movie] }
            $0.channelListClient.fetchFavorites = { [] }
        }
        store.exhaustivity = .off

        await store.send(.onAppear) {
            $0.isLoading = true
        }

        await store.skipReceivedActions()

        store.assert {
            $0.isLoading = false
            $0.continueWatchingItems = [
                HomeFeature.ContinueWatchingItem(vodItem: movie, progress: 0.5, positionMs: 1_800_000)
            ]
        }
    }

    // MARK: - Tapping Items

    func testContinueWatchingItemTapped_presentsVideoPlayer() async {
        let movie = makeMovie(id: "m1", streamURL: "http://example.com/movie.mp4")
        let item = makeContinueWatchingItem(vodItem: movie)

        let store = TestStore(initialState: HomeFeature.State()) {
            HomeFeature()
        }

        await store.send(.continueWatchingItemTapped(item)) {
            $0.videoPlayer = VideoPlayerFeature.State(vodItem: movie)
        }
        await store.receive(\.delegate.playVodItem)
    }

    func testContinueWatchingItemTapped_noStreamURL_noOp() async {
        let movie = makeMovie(id: "m1", streamURL: nil)
        let item = makeContinueWatchingItem(vodItem: movie)

        let store = TestStore(initialState: HomeFeature.State()) {
            HomeFeature()
        }

        await store.send(.continueWatchingItemTapped(item))
    }

    func testFavoriteChannelTapped_presentsVideoPlayer() async {
        let channel = makeChannel(id: "ch-1", name: "ESPN")

        let store = TestStore(initialState: HomeFeature.State()) {
            HomeFeature()
        }

        await store.send(.favoriteChannelTapped(channel)) {
            $0.videoPlayer = VideoPlayerFeature.State(channel: channel)
        }
        await store.receive(\.delegate.playChannel)
    }

    // MARK: - Video Player Dismiss

    func testVideoPlayerDismiss_nilsState() async {
        var state = HomeFeature.State()
        state.videoPlayer = VideoPlayerFeature.State(
            vodItem: makeMovie(id: "m1", streamURL: "http://example.com/movie.mp4")
        )

        let store = TestStore(initialState: state) {
            HomeFeature()
        }

        await store.send(.videoPlayer(.presented(.delegate(.dismissed)))) {
            $0.videoPlayer = nil
        }
    }

    // MARK: - EPG Data

    func testEpgDataLoaded_mergesNowPlaying() async {
        var state = HomeFeature.State()
        state.nowPlaying = ["epg-1": "Old Show"]

        let store = TestStore(initialState: state) {
            HomeFeature()
        }

        await store.send(.epgDataLoaded(.success(["epg-1": "New Show", "epg-2": "Another"]))) {
            $0.nowPlaying = ["epg-1": "New Show", "epg-2": "Another"]
        }
    }

    // MARK: - Failure Handling

    func testContinueWatchingLoaded_failure_clearsLoading() async {
        var state = HomeFeature.State()
        state.isLoading = true

        let store = TestStore(initialState: state) {
            HomeFeature()
        }

        await store.send(.continueWatchingLoaded(.failure(NSError(domain: "test", code: 1)))) {
            $0.isLoading = false
        }
    }

    func testFavoritesLoaded_failure_noStateChange() async {
        let store = TestStore(initialState: HomeFeature.State()) {
            HomeFeature()
        }

        await store.send(.favoritesLoaded(.failure(NSError(domain: "test", code: 1))))
    }

    // MARK: - Pull to Refresh

    func testRefreshTapped_reloadsData() async {
        let store = TestStore(initialState: HomeFeature.State()) {
            HomeFeature()
        } withDependencies: {
            $0.watchProgressClient.getUnfinished = { _ in [] }
            $0.channelListClient.fetchFavorites = { [] }
        }
        store.exhaustivity = .off

        await store.send(.refreshTapped) {
            $0.isLoading = true
        }
        await store.skipReceivedActions()
    }
}
