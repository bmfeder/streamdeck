import ComposableArchitecture
import XCTest
import Database
@testable import AppFeature

@MainActor
final class VideoPlayerFeatureTests: XCTestCase {

    // MARK: - Helpers

    private func makeChannel(
        id: String = "ch-1",
        name: String = "Test Channel",
        streamURL: String = "http://example.com/stream.m3u8",
        groupName: String? = "News"
    ) -> ChannelRecord {
        ChannelRecord(
            id: id,
            playlistID: "pl-1",
            name: name,
            groupName: groupName,
            streamURL: streamURL
        )
    }

    private func makeStore(
        channel: ChannelRecord? = nil,
        route: @escaping @Sendable (URL) async -> StreamRoute = { url in
            StreamRoute(recommendedEngine: .avPlayer, url: url, reason: "test")
        },
        savedProgress: WatchProgressRecord? = nil
    ) -> TestStoreOf<VideoPlayerFeature> {
        let ch = channel ?? makeChannel()
        return TestStore(initialState: VideoPlayerFeature.State(channel: ch)) {
            VideoPlayerFeature()
        } withDependencies: {
            $0.streamRouterClient.route = route
            $0.continuousClock = ImmediateClock()
            $0.watchProgressClient.getProgress = { _ in savedProgress }
            $0.watchProgressClient.saveProgress = { _, _, _, _ in }
            $0.userDefaultsClient.stringForKey = { _ in nil }
        }
    }

    // MARK: - Initial State

    func testInitialState() {
        let channel = makeChannel()
        let state = VideoPlayerFeature.State(channel: channel)
        XCTAssertEqual(state.status, .idle)
        XCTAssertNil(state.activeEngine)
        XCTAssertNil(state.streamRoute)
        XCTAssertEqual(state.playerCommand, .none)
        XCTAssertEqual(state.retryCount, 0)
        XCTAssertFalse(state.hasTriedFallbackEngine)
        XCTAssertTrue(state.isOverlayVisible)
    }

    // MARK: - On Appear

    func testOnAppear_routesStream() async {
        let url = URL(string: "http://example.com/stream.m3u8")!
        let expectedRoute = StreamRoute(recommendedEngine: .avPlayer, url: url, reason: "HLS")
        let store = makeStore(route: { _ in expectedRoute })
        store.exhaustivity = .off

        await store.send(.onAppear) {
            $0.status = .routing
        }

        await store.receive(\.streamRouted) {
            $0.streamRoute = expectedRoute
            $0.activeEngine = .avPlayer
            $0.status = .loading
            $0.playerCommand = .play(url: url, engine: .avPlayer)
        }

        await store.skipReceivedActions()
    }

    func testOnAppear_invalidURL_setsError() async {
        let channel = makeChannel(streamURL: "not a valid url")
        let store = TestStore(initialState: VideoPlayerFeature.State(channel: channel)) {
            VideoPlayerFeature()
        }

        await store.send(.onAppear) {
            $0.status = .error(.streamUnavailable)
        }
    }

    func testOnAppear_invalidScheme_setsError() async {
        let channel = makeChannel(streamURL: "ftp://example.com/stream")
        let store = TestStore(initialState: VideoPlayerFeature.State(channel: channel)) {
            VideoPlayerFeature()
        }

        await store.send(.onAppear) {
            $0.status = .error(.streamUnavailable)
        }
    }

    func testOnAppear_alreadyRouting_noOp() async {
        var state = VideoPlayerFeature.State(channel: makeChannel())
        state.status = .loading

        let store = TestStore(initialState: state) {
            VideoPlayerFeature()
        }

        await store.send(.onAppear)
    }

    func testOnAppear_rtspScheme_routes() async {
        let channel = makeChannel(streamURL: "rtsp://example.com/live")
        let url = URL(string: "rtsp://example.com/live")!
        let expectedRoute = StreamRoute(recommendedEngine: .vlcKit, url: url, reason: "RTSP")
        let store = TestStore(initialState: VideoPlayerFeature.State(channel: channel)) {
            VideoPlayerFeature()
        } withDependencies: {
            $0.streamRouterClient.route = { _ in expectedRoute }
            $0.continuousClock = ImmediateClock()
            $0.watchProgressClient.getProgress = { _ in nil }
            $0.watchProgressClient.saveProgress = { _, _, _, _ in }
        }
        store.exhaustivity = .off

        await store.send(.onAppear) {
            $0.status = .routing
        }

        await store.receive(\.streamRouted) {
            $0.streamRoute = expectedRoute
            $0.activeEngine = .vlcKit
            $0.status = .loading
            $0.playerCommand = .play(url: url, engine: .vlcKit)
        }

        await store.skipReceivedActions()
    }

    // MARK: - Stream Routed

    func testStreamRouted_setsEngineAndPlays() async {
        let url = URL(string: "http://example.com/stream.ts")!
        let route = StreamRoute(recommendedEngine: .vlcKit, url: url, reason: "MPEG-TS")

        var state = VideoPlayerFeature.State(channel: makeChannel())
        state.status = .routing

        let store = TestStore(initialState: state) {
            VideoPlayerFeature()
        } withDependencies: {
            $0.continuousClock = ImmediateClock()
        }
        store.exhaustivity = .off

        await store.send(.streamRouted(route)) {
            $0.streamRoute = route
            $0.activeEngine = .vlcKit
            $0.status = .loading
            $0.playerCommand = .play(url: url, engine: .vlcKit)
        }

        await store.receive(\.overlayAutoHideExpired)
        await store.skipReceivedActions()
    }

    // MARK: - Player Status Changes

    func testPlayerStatusChanged_playing_resetsRetryCount() async {
        var state = VideoPlayerFeature.State(channel: makeChannel())
        state.retryCount = 2
        state.status = .loading

        let store = TestStore(initialState: state) {
            VideoPlayerFeature()
        } withDependencies: {
            $0.continuousClock = ImmediateClock()
            $0.watchProgressClient.saveProgress = { _, _, _, _ in }
        }
        store.exhaustivity = .off

        await store.send(.playerStatusChanged(.playing)) {
            $0.status = .playing
            $0.retryCount = 0
        }
    }

    func testPlayerStatusChanged_paused() async {
        var state = VideoPlayerFeature.State(channel: makeChannel())
        state.status = .playing

        let store = TestStore(initialState: state) {
            VideoPlayerFeature()
        }

        await store.send(.playerStatusChanged(.paused)) {
            $0.status = .paused
        }
    }

    // MARK: - Error & Retry Logic

    func testPlayerError_firstAttempt_retriesWithDelay() async {
        let url = URL(string: "http://example.com/stream.m3u8")!
        let route = StreamRoute(recommendedEngine: .avPlayer, url: url, reason: "test")

        var state = VideoPlayerFeature.State(channel: makeChannel())
        state.streamRoute = route
        state.activeEngine = .avPlayer
        state.status = .playing

        let store = TestStore(initialState: state) {
            VideoPlayerFeature()
        } withDependencies: {
            $0.continuousClock = ImmediateClock()
        }

        await store.send(.playerEncounteredError(.networkLost)) {
            $0.retryCount = 1
            $0.status = .retrying(attempt: 1, engine: .avPlayer)
            $0.playerCommand = .stop
        }

        await store.receive(\.retryTimerFired) {
            $0.status = .loading
            $0.playerCommand = .play(url: url, engine: .avPlayer)
        }
    }

    func testPlayerError_secondAttempt_retries() async {
        let url = URL(string: "http://example.com/stream.m3u8")!
        let route = StreamRoute(recommendedEngine: .avPlayer, url: url, reason: "test")

        var state = VideoPlayerFeature.State(channel: makeChannel())
        state.streamRoute = route
        state.activeEngine = .avPlayer
        state.retryCount = 1
        state.status = .playing

        let store = TestStore(initialState: state) {
            VideoPlayerFeature()
        } withDependencies: {
            $0.continuousClock = ImmediateClock()
        }

        await store.send(.playerEncounteredError(.networkLost)) {
            $0.retryCount = 2
            $0.status = .retrying(attempt: 2, engine: .avPlayer)
            $0.playerCommand = .stop
        }

        await store.receive(\.retryTimerFired) {
            $0.status = .loading
            $0.playerCommand = .play(url: url, engine: .avPlayer)
        }
    }

    func testPlayerError_thirdAttempt_retries() async {
        let url = URL(string: "http://example.com/stream.m3u8")!
        let route = StreamRoute(recommendedEngine: .avPlayer, url: url, reason: "test")

        var state = VideoPlayerFeature.State(channel: makeChannel())
        state.streamRoute = route
        state.activeEngine = .avPlayer
        state.retryCount = 2
        state.status = .playing

        let store = TestStore(initialState: state) {
            VideoPlayerFeature()
        } withDependencies: {
            $0.continuousClock = ImmediateClock()
        }

        await store.send(.playerEncounteredError(.networkLost)) {
            $0.retryCount = 3
            $0.status = .retrying(attempt: 3, engine: .avPlayer)
            $0.playerCommand = .stop
        }

        await store.receive(\.retryTimerFired) {
            $0.status = .loading
            $0.playerCommand = .play(url: url, engine: .avPlayer)
        }
    }

    func testPlayerError_afterMaxRetries_switchesToFallbackEngine() async {
        let url = URL(string: "http://example.com/stream.m3u8")!
        let route = StreamRoute(recommendedEngine: .avPlayer, url: url, reason: "test")

        var state = VideoPlayerFeature.State(channel: makeChannel())
        state.streamRoute = route
        state.activeEngine = .avPlayer
        state.retryCount = 3 // already at max
        state.status = .playing

        let store = TestStore(initialState: state) {
            VideoPlayerFeature()
        } withDependencies: {
            $0.continuousClock = ImmediateClock()
        }

        await store.send(.playerEncounteredError(.networkLost)) {
            $0.hasTriedFallbackEngine = true
            $0.activeEngine = .vlcKit
            $0.retryCount = 1
            $0.status = .retrying(attempt: 1, engine: .vlcKit)
            $0.playerCommand = .stop
        }

        await store.receive(\.retryTimerFired) {
            $0.status = .loading
            $0.playerCommand = .play(url: url, engine: .vlcKit)
        }
    }

    func testPlayerError_fallbackEngineExhausted_fails() async {
        let url = URL(string: "http://example.com/stream.m3u8")!
        let route = StreamRoute(recommendedEngine: .avPlayer, url: url, reason: "test")

        var state = VideoPlayerFeature.State(channel: makeChannel())
        state.streamRoute = route
        state.activeEngine = .vlcKit
        state.retryCount = 3
        state.hasTriedFallbackEngine = true
        state.status = .playing

        let store = TestStore(initialState: state) {
            VideoPlayerFeature()
        }

        await store.send(.playerEncounteredError(.decodingFailed)) {
            $0.status = .failed
            $0.playerCommand = .stop
        }
    }

    // MARK: - Retry Tapped

    func testRetryTapped_resetsAndPlays() async {
        let url = URL(string: "http://example.com/stream.m3u8")!
        let route = StreamRoute(recommendedEngine: .avPlayer, url: url, reason: "test")

        var state = VideoPlayerFeature.State(channel: makeChannel())
        state.streamRoute = route
        state.activeEngine = .vlcKit
        state.retryCount = 3
        state.hasTriedFallbackEngine = true
        state.status = .failed

        let store = TestStore(initialState: state) {
            VideoPlayerFeature()
        }

        await store.send(.retryTapped) {
            $0.retryCount = 0
            $0.hasTriedFallbackEngine = false
            $0.activeEngine = .avPlayer
            $0.status = .loading
            $0.playerCommand = .play(url: url, engine: .avPlayer)
        }
    }

    func testRetryTapped_noRoute_fails() async {
        var state = VideoPlayerFeature.State(channel: makeChannel())
        state.status = .failed
        state.streamRoute = nil

        let store = TestStore(initialState: state) {
            VideoPlayerFeature()
        }

        await store.send(.retryTapped) {
            $0.retryCount = 0
            $0.hasTriedFallbackEngine = false
            $0.activeEngine = .avPlayer
            $0.status = .failed
        }
    }

    // MARK: - Try Alternate Engine

    func testTryAlternateEngineTapped_switchesEngine() async {
        let url = URL(string: "http://example.com/stream.m3u8")!
        let route = StreamRoute(recommendedEngine: .avPlayer, url: url, reason: "test")

        var state = VideoPlayerFeature.State(channel: makeChannel())
        state.streamRoute = route
        state.activeEngine = .avPlayer
        state.status = .playing

        let store = TestStore(initialState: state) {
            VideoPlayerFeature()
        }

        await store.send(.tryAlternateEngineTapped) {
            $0.activeEngine = .vlcKit
            $0.retryCount = 0
            $0.hasTriedFallbackEngine = true
            $0.status = .loading
            $0.playerCommand = .play(url: url, engine: .vlcKit)
        }
    }

    func testTryAlternateEngineTapped_noRoute_fails() async {
        var state = VideoPlayerFeature.State(channel: makeChannel())
        state.activeEngine = .avPlayer
        state.streamRoute = nil

        let store = TestStore(initialState: state) {
            VideoPlayerFeature()
        }

        await store.send(.tryAlternateEngineTapped) {
            $0.activeEngine = .vlcKit
            $0.retryCount = 0
            $0.hasTriedFallbackEngine = true
            $0.status = .failed
        }
    }

    // MARK: - Overlay

    func testToggleOverlay_hidesWhenVisible() async {
        var state = VideoPlayerFeature.State(channel: makeChannel())
        state.isOverlayVisible = true

        let store = TestStore(initialState: state) {
            VideoPlayerFeature()
        }

        await store.send(.toggleOverlayTapped) {
            $0.isOverlayVisible = false
        }
    }

    func testToggleOverlay_showsWhenHidden() async {
        var state = VideoPlayerFeature.State(channel: makeChannel())
        state.isOverlayVisible = false

        let store = TestStore(initialState: state) {
            VideoPlayerFeature()
        } withDependencies: {
            $0.continuousClock = ImmediateClock()
        }

        await store.send(.toggleOverlayTapped) {
            $0.isOverlayVisible = true
        }

        // Overlay auto-hide fires but status is not .playing, so no state change
        await store.receive(\.overlayAutoHideExpired)
    }

    func testOverlayAutoHide_hidesWhenPlaying() async {
        var state = VideoPlayerFeature.State(channel: makeChannel())
        state.isOverlayVisible = true
        state.status = .playing

        let store = TestStore(initialState: state) {
            VideoPlayerFeature()
        }

        await store.send(.overlayAutoHideExpired) {
            $0.isOverlayVisible = false
        }
    }

    func testOverlayAutoHide_staysVisibleWhenNotPlaying() async {
        var state = VideoPlayerFeature.State(channel: makeChannel())
        state.isOverlayVisible = true
        state.status = .loading

        let store = TestStore(initialState: state) {
            VideoPlayerFeature()
        }

        await store.send(.overlayAutoHideExpired)
    }

    // MARK: - Dismiss

    func testDismissTapped_stopsAndDelegates() async {
        var state = VideoPlayerFeature.State(channel: makeChannel())
        state.status = .playing
        state.playerCommand = .play(
            url: URL(string: "http://example.com/stream.m3u8")!,
            engine: .avPlayer
        )

        let store = TestStore(initialState: state) {
            VideoPlayerFeature()
        }

        await store.send(.dismissTapped) {
            $0.playerCommand = .stop
        }

        await store.receive(\.delegate.dismissed)
    }

    // MARK: - On Disappear

    func testOnDisappear_stopsPlayback() async {
        var state = VideoPlayerFeature.State(channel: makeChannel())
        state.status = .playing
        state.playerCommand = .play(
            url: URL(string: "http://example.com/stream.m3u8")!,
            engine: .avPlayer
        )

        let store = TestStore(initialState: state) {
            VideoPlayerFeature()
        }

        await store.send(.onDisappear) {
            $0.playerCommand = .stop
        }
    }

    // MARK: - Retry Timer with No Route

    func testRetryTimerFired_noRoute_fails() async {
        var state = VideoPlayerFeature.State(channel: makeChannel())
        state.streamRoute = nil
        state.status = .retrying(attempt: 1, engine: .avPlayer)

        let store = TestStore(initialState: state) {
            VideoPlayerFeature()
        }

        await store.send(.retryTimerFired(attempt: 1, engine: .avPlayer)) {
            $0.status = .failed
        }
    }

    func testRetryTimerFired_withRoute_playsAgain() async {
        let url = URL(string: "http://example.com/stream.m3u8")!
        let route = StreamRoute(recommendedEngine: .avPlayer, url: url, reason: "test")

        var state = VideoPlayerFeature.State(channel: makeChannel())
        state.streamRoute = route
        state.status = .retrying(attempt: 1, engine: .avPlayer)

        let store = TestStore(initialState: state) {
            VideoPlayerFeature()
        }

        await store.send(.retryTimerFired(attempt: 1, engine: .avPlayer)) {
            $0.status = .loading
            $0.playerCommand = .play(url: url, engine: .avPlayer)
        }
    }

    // MARK: - VLCKit to AVPlayer Fallback

    func testFallback_vlcKitToAVPlayer() async {
        let url = URL(string: "http://example.com/stream.ts")!
        let route = StreamRoute(recommendedEngine: .vlcKit, url: url, reason: "MPEG-TS")

        var state = VideoPlayerFeature.State(channel: makeChannel())
        state.streamRoute = route
        state.activeEngine = .vlcKit
        state.retryCount = 3
        state.status = .playing

        let store = TestStore(initialState: state) {
            VideoPlayerFeature()
        } withDependencies: {
            $0.continuousClock = ImmediateClock()
        }

        await store.send(.playerEncounteredError(.decodingFailed)) {
            $0.hasTriedFallbackEngine = true
            $0.activeEngine = .avPlayer
            $0.retryCount = 1
            $0.status = .retrying(attempt: 1, engine: .avPlayer)
            $0.playerCommand = .stop
        }

        await store.receive(\.retryTimerFired) {
            $0.status = .loading
            $0.playerCommand = .play(url: url, engine: .avPlayer)
        }
    }

    // MARK: - Watch Progress

    func testOnAppear_loadsExistingProgress() async {
        let url = URL(string: "http://example.com/stream.m3u8")!
        let expectedRoute = StreamRoute(recommendedEngine: .avPlayer, url: url, reason: "HLS")
        let savedProgress = WatchProgressRecord(
            contentID: "ch-1", positionMs: 120_000, durationMs: 3_600_000, updatedAt: 1_700_000_000
        )
        let store = makeStore(route: { _ in expectedRoute }, savedProgress: savedProgress)
        store.exhaustivity = .off

        await store.send(.onAppear) {
            $0.status = .routing
        }

        await store.receive(\.progressLoaded) {
            $0.resumePositionMs = 120_000
            $0.currentDurationMs = 3_600_000
        }

        await store.skipReceivedActions()
    }

    func testProgressLoaded_belowThreshold_noResume() async {
        let record = WatchProgressRecord(contentID: "ch-1", positionMs: 5000, updatedAt: 1_700_000_000)

        let state = VideoPlayerFeature.State(channel: makeChannel())
        let store = TestStore(initialState: state) {
            VideoPlayerFeature()
        }

        await store.send(.progressLoaded(record))
        // positionMs (5000) < 10_000 threshold, so no resumePositionMs set
    }

    func testProgressLoaded_aboveThreshold_setsResume() async {
        let record = WatchProgressRecord(
            contentID: "ch-1", positionMs: 60_000, durationMs: 3_600_000, updatedAt: 1_700_000_000
        )

        let store = TestStore(initialState: VideoPlayerFeature.State(channel: makeChannel())) {
            VideoPlayerFeature()
        }

        await store.send(.progressLoaded(record)) {
            $0.resumePositionMs = 60_000
            $0.currentDurationMs = 3_600_000
        }
    }

    func testTimeUpdated_updatesPosition() async {
        let store = TestStore(initialState: VideoPlayerFeature.State(channel: makeChannel())) {
            VideoPlayerFeature()
        }

        await store.send(.timeUpdated(positionMs: 45_000, durationMs: 3_600_000)) {
            $0.currentPositionMs = 45_000
            $0.currentDurationMs = 3_600_000
        }
    }

    func testOnDisappear_savesProgress() async {
        var state = VideoPlayerFeature.State(channel: makeChannel())
        state.currentPositionMs = 120_000
        state.currentDurationMs = 3_600_000
        state.status = .playing

        let saved = LockIsolated<(String, Int)?>(nil)

        let store = TestStore(initialState: state) {
            VideoPlayerFeature()
        } withDependencies: {
            $0.watchProgressClient.saveProgress = { contentID, _, positionMs, _ in
                saved.setValue((contentID, positionMs))
            }
        }

        await store.send(.onDisappear) {
            $0.playerCommand = .stop
        }

        let result = saved.value
        XCTAssertEqual(result?.0, "ch-1")
        XCTAssertEqual(result?.1, 120_000)
    }

    // MARK: - Channel Switcher: Initial State

    func testInitialState_channel_isLiveChannelTrue() {
        let state = VideoPlayerFeature.State(channel: makeChannel())
        XCTAssertTrue(state.isLiveChannel)
        XCTAssertFalse(state.isSwitcherVisible)
        XCTAssertTrue(state.switcherChannels.isEmpty)
    }

    func testInitialState_vod_isLiveChannelFalse() {
        let vod = VodItemRecord(
            id: "m1", playlistID: "pl-1", title: "Movie", type: "movie",
            streamURL: "http://example.com/movie.mp4"
        )
        let state = VideoPlayerFeature.State(vodItem: vod)
        XCTAssertFalse(state.isLiveChannel)
    }

    // MARK: - Channel Switcher: Show/Hide

    func testShowSwitcher_liveChannel_showsAndLoadsFavorites() async {
        let favorites = [
            makeChannel(id: "ch-2", name: "CNN"),
            makeChannel(id: "ch-3", name: "BBC"),
        ]

        let store = makeStore()
        store.exhaustivity = .off

        // Need to provide channelListClient and epgClient
        store.dependencies.channelListClient.fetchFavorites = { favorites }
        store.dependencies.epgClient.fetchNowPlayingBatch = { _ in [:] }

        await store.send(.showSwitcher) {
            $0.isSwitcherVisible = true
            $0.isOverlayVisible = false
        }

        await store.receive(\.switcherChannelsLoaded.success) {
            $0.switcherChannels = favorites
        }

        await store.skipReceivedActions()
    }

    func testShowSwitcher_vodItem_noOp() async {
        let vod = VodItemRecord(
            id: "m1", playlistID: "pl-1", title: "Movie", type: "movie",
            streamURL: "http://example.com/movie.mp4"
        )
        let store = TestStore(initialState: VideoPlayerFeature.State(vodItem: vod)) {
            VideoPlayerFeature()
        }

        await store.send(.showSwitcher)
    }

    func testHideSwitcher_resetsState() async {
        var state = VideoPlayerFeature.State(channel: makeChannel())
        state.isSwitcherVisible = true
        state.switcherChannels = [makeChannel(id: "ch-2")]
        state.switcherNowPlaying = ["epg-1": "Live News"]

        let store = TestStore(initialState: state) {
            VideoPlayerFeature()
        }

        await store.send(.hideSwitcher) {
            $0.isSwitcherVisible = false
            $0.switcherChannels = []
            $0.switcherNowPlaying = [:]
        }
    }

    func testSwitcherAutoHide_hidesAfterTimeout() async {
        var state = VideoPlayerFeature.State(channel: makeChannel())
        state.isSwitcherVisible = true
        state.switcherChannels = [makeChannel(id: "ch-2")]

        let store = TestStore(initialState: state) {
            VideoPlayerFeature()
        }

        await store.send(.switcherAutoHideExpired) {
            $0.isSwitcherVisible = false
            $0.switcherChannels = []
            $0.switcherNowPlaying = [:]
        }
    }

    // MARK: - Channel Switcher: Channel Loading

    func testSwitcherChannelsLoaded_success_populatesChannels() async {
        let channels = [
            makeChannel(id: "ch-2", name: "CNN"),
            makeChannel(id: "ch-3", name: "BBC"),
        ]

        var state = VideoPlayerFeature.State(channel: makeChannel())
        state.isSwitcherVisible = true

        let store = TestStore(initialState: state) {
            VideoPlayerFeature()
        } withDependencies: {
            $0.epgClient.fetchNowPlayingBatch = { _ in [:] }
        }

        await store.send(.switcherChannelsLoaded(.success(channels))) {
            $0.switcherChannels = channels
        }
    }

    func testSwitcherChannelsLoaded_failure_noStateChange() async {
        var state = VideoPlayerFeature.State(channel: makeChannel())
        state.isSwitcherVisible = true

        let store = TestStore(initialState: state) {
            VideoPlayerFeature()
        }

        await store.send(.switcherChannelsLoaded(.failure(NSError(domain: "test", code: 1))))
    }

    func testSwitcherEPGLoaded_success_populatesNowPlaying() async {
        var state = VideoPlayerFeature.State(channel: makeChannel())
        state.isSwitcherVisible = true
        state.switcherChannels = [makeChannel(id: "ch-2")]

        let store = TestStore(initialState: state) {
            VideoPlayerFeature()
        }

        await store.send(.switcherEPGLoaded(.success(["epg-1": "Live News"]))) {
            $0.switcherNowPlaying = ["epg-1": "Live News"]
        }
    }

    // MARK: - Channel Switcher: Channel Selection

    func testSwitcherChannelSelected_sameChannel_justCloses() async {
        let currentChannel = makeChannel(id: "ch-1")
        var state = VideoPlayerFeature.State(channel: currentChannel)
        state.isSwitcherVisible = true
        state.switcherChannels = [currentChannel, makeChannel(id: "ch-2")]

        let store = TestStore(initialState: state) {
            VideoPlayerFeature()
        }

        await store.send(.switcherChannelSelected(currentChannel))
        await store.receive(\.hideSwitcher) {
            $0.isSwitcherVisible = false
            $0.switcherChannels = []
            $0.switcherNowPlaying = [:]
        }
    }

    func testSwitcherChannelSelected_differentChannel_switchesPlayback() async {
        let currentChannel = makeChannel(id: "ch-1", name: "Old Channel")
        let newChannel = makeChannel(id: "ch-2", name: "New Channel", streamURL: "http://example.com/new.m3u8")
        let url = URL(string: "http://example.com/new.m3u8")!
        let expectedRoute = StreamRoute(recommendedEngine: .avPlayer, url: url, reason: "test")

        var state = VideoPlayerFeature.State(channel: currentChannel)
        state.status = .playing
        state.isSwitcherVisible = true
        state.switcherChannels = [currentChannel, newChannel]

        let store = TestStore(initialState: state) {
            VideoPlayerFeature()
        } withDependencies: {
            $0.streamRouterClient.route = { _ in expectedRoute }
            $0.continuousClock = ImmediateClock()
            $0.watchProgressClient.getProgress = { _ in nil }
            $0.watchProgressClient.saveProgress = { _, _, _, _ in }
        }
        store.exhaustivity = .off

        await store.send(.switcherChannelSelected(newChannel)) {
            $0.item = PlayableItem(channel: newChannel)
            $0.status = .idle
            $0.activeEngine = nil
            $0.streamRoute = nil
            $0.playerCommand = .stop
            $0.retryCount = 0
            $0.hasTriedFallbackEngine = false
            $0.resumePositionMs = nil
            $0.currentPositionMs = 0
            $0.currentDurationMs = nil
            $0.isSwitcherVisible = false
            $0.switcherChannels = []
            $0.switcherNowPlaying = [:]
        }

        await store.receive(\.delegate.channelSwitched)

        await store.receive(\.onAppear) {
            $0.status = .routing
        }

        await store.skipReceivedActions()
    }

    func testSwitcherChannelSelected_savesProgressBeforeSwitch() async {
        let currentChannel = makeChannel(id: "ch-1")
        let newChannel = makeChannel(id: "ch-2", name: "New", streamURL: "http://example.com/new.m3u8")

        var state = VideoPlayerFeature.State(channel: currentChannel)
        state.status = .playing
        state.currentPositionMs = 60_000
        state.currentDurationMs = 3_600_000
        state.isSwitcherVisible = true

        let saved = LockIsolated<(String, Int)?>(nil)
        let url = URL(string: "http://example.com/new.m3u8")!

        let store = TestStore(initialState: state) {
            VideoPlayerFeature()
        } withDependencies: {
            $0.streamRouterClient.route = { _ in
                StreamRoute(recommendedEngine: .avPlayer, url: url, reason: "test")
            }
            $0.continuousClock = ImmediateClock()
            $0.watchProgressClient.getProgress = { _ in nil }
            $0.watchProgressClient.saveProgress = { contentID, _, positionMs, _ in
                saved.setValue((contentID, positionMs))
            }
        }
        store.exhaustivity = .off

        await store.send(.switcherChannelSelected(newChannel)) {
            $0.item = PlayableItem(channel: newChannel)
            $0.status = .idle
            $0.activeEngine = nil
            $0.streamRoute = nil
            $0.playerCommand = .stop
            $0.retryCount = 0
            $0.hasTriedFallbackEngine = false
            $0.resumePositionMs = nil
            $0.currentPositionMs = 0
            $0.currentDurationMs = nil
            $0.isSwitcherVisible = false
            $0.switcherChannels = []
            $0.switcherNowPlaying = [:]
        }

        await store.skipReceivedActions()

        let result = saved.value
        XCTAssertEqual(result?.0, "ch-1")
        XCTAssertEqual(result?.1, 60_000)
    }

    // MARK: - Sleep Timer

    func testSleepTimerButtonTapped_togglesPicker() async {
        let store = makeStore()
        store.exhaustivity = .off

        await store.send(.sleepTimerButtonTapped) {
            $0.isSleepTimerPickerVisible = true
        }

        await store.send(.sleepTimerButtonTapped) {
            $0.isSleepTimerPickerVisible = false
        }

        await store.skipReceivedActions()
    }

    func testSleepTimerSelected_setsState() async {
        let store = makeStore()
        store.exhaustivity = .off

        await store.send(.sleepTimerSelected(minutes: 30)) {
            $0.sleepTimerMinutesRemaining = 30
            $0.isSleepTimerPickerVisible = false
            // sleepTimerEndDate is set but exact Date is non-deterministic
        }

        // ImmediateClock fires sleepTimerFired immediately
        await store.skipReceivedActions()
    }

    func testSleepTimerSelected_nil_cancelsTimer() async {
        var state = VideoPlayerFeature.State(channel: makeChannel())
        state.sleepTimerEndDate = Date().addingTimeInterval(1800)
        state.sleepTimerMinutesRemaining = 30

        let store = TestStore(initialState: state) {
            VideoPlayerFeature()
        } withDependencies: {
            $0.continuousClock = ImmediateClock()
        }
        store.exhaustivity = .off

        await store.send(.sleepTimerSelected(minutes: nil)) {
            $0.sleepTimerEndDate = nil
            $0.sleepTimerMinutesRemaining = nil
            $0.isSleepTimerPickerVisible = false
        }

        await store.skipReceivedActions()
    }

    func testSleepTimerSelected_whileActive_replacesTimer() async {
        var state = VideoPlayerFeature.State(channel: makeChannel())
        state.sleepTimerEndDate = Date().addingTimeInterval(900)
        state.sleepTimerMinutesRemaining = 15

        let store = TestStore(initialState: state) {
            VideoPlayerFeature()
        } withDependencies: {
            $0.continuousClock = ImmediateClock()
            $0.watchProgressClient.saveProgress = { _, _, _, _ in }
        }
        store.exhaustivity = .off

        await store.send(.sleepTimerSelected(minutes: 60)) {
            $0.sleepTimerMinutesRemaining = 60
            $0.isSleepTimerPickerVisible = false
        }

        await store.skipReceivedActions()
    }

    func testSleepTimerTick_updatesRemaining() async {
        var state = VideoPlayerFeature.State(channel: makeChannel())
        state.sleepTimerEndDate = Date().addingTimeInterval(45 * 60)
        state.sleepTimerMinutesRemaining = 46

        let store = TestStore(initialState: state) {
            VideoPlayerFeature()
        }

        await store.send(.sleepTimerTick) {
            $0.sleepTimerMinutesRemaining = 45
        }
    }

    func testSleepTimerTick_noTimer_noOp() async {
        let store = TestStore(
            initialState: VideoPlayerFeature.State(channel: makeChannel())
        ) {
            VideoPlayerFeature()
        }

        await store.send(.sleepTimerTick)
    }

    func testSleepTimerFired_stopsAndDismisses() async {
        var state = VideoPlayerFeature.State(channel: makeChannel())
        state.status = .playing
        state.sleepTimerEndDate = Date()
        state.sleepTimerMinutesRemaining = 0

        let store = TestStore(initialState: state) {
            VideoPlayerFeature()
        } withDependencies: {
            $0.watchProgressClient.saveProgress = { _, _, _, _ in }
        }

        await store.send(.sleepTimerFired) {
            $0.sleepTimerEndDate = nil
            $0.sleepTimerMinutesRemaining = nil
            $0.playerCommand = .stop
        }

        await store.receive(\.delegate.dismissed)
    }

    func testSleepTimerFired_savesProgress() async {
        var state = VideoPlayerFeature.State(channel: makeChannel())
        state.status = .playing
        state.currentPositionMs = 90_000
        state.currentDurationMs = 3_600_000
        state.sleepTimerEndDate = Date()
        state.sleepTimerMinutesRemaining = 0

        let saved = LockIsolated<(String, Int)?>(nil)

        let store = TestStore(initialState: state) {
            VideoPlayerFeature()
        } withDependencies: {
            $0.watchProgressClient.saveProgress = { contentID, _, positionMs, _ in
                saved.setValue((contentID, positionMs))
            }
        }

        await store.send(.sleepTimerFired) {
            $0.sleepTimerEndDate = nil
            $0.sleepTimerMinutesRemaining = nil
            $0.playerCommand = .stop
        }

        await store.receive(\.delegate.dismissed)

        let result = saved.value
        XCTAssertEqual(result?.0, "ch-1")
        XCTAssertEqual(result?.1, 90_000)
    }

    func testSleepTimerPersists_acrossChannelSwitch() async {
        let newChannel = makeChannel(id: "ch-2", name: "New", streamURL: "http://example.com/new.m3u8")
        let url = URL(string: "http://example.com/new.m3u8")!

        var state = VideoPlayerFeature.State(channel: makeChannel())
        state.status = .playing
        state.isSwitcherVisible = true
        let futureDate = Date().addingTimeInterval(1800)
        state.sleepTimerEndDate = futureDate
        state.sleepTimerMinutesRemaining = 30

        let store = TestStore(initialState: state) {
            VideoPlayerFeature()
        } withDependencies: {
            $0.streamRouterClient.route = { _ in
                StreamRoute(recommendedEngine: .avPlayer, url: url, reason: "test")
            }
            $0.continuousClock = ImmediateClock()
            $0.watchProgressClient.getProgress = { _ in nil }
            $0.watchProgressClient.saveProgress = { _, _, _, _ in }
        }
        store.exhaustivity = .off

        await store.send(.switcherChannelSelected(newChannel)) {
            $0.item = PlayableItem(channel: newChannel)
            $0.status = .idle
            $0.activeEngine = nil
            $0.streamRoute = nil
            $0.playerCommand = .stop
            $0.retryCount = 0
            $0.hasTriedFallbackEngine = false
            $0.resumePositionMs = nil
            $0.currentPositionMs = 0
            $0.currentDurationMs = nil
            $0.isSwitcherVisible = false
            $0.switcherChannels = []
            $0.switcherNowPlaying = [:]
            // Sleep timer fields preserved (not reset)
        }

        await store.skipReceivedActions()
    }

    func testOverlayAutoHide_blockedWhilePickerOpen() async {
        var state = VideoPlayerFeature.State(channel: makeChannel())
        state.isOverlayVisible = true
        state.status = .playing
        state.isSleepTimerPickerVisible = true

        let store = TestStore(initialState: state) {
            VideoPlayerFeature()
        }

        await store.send(.overlayAutoHideExpired)
        // Overlay stays visible because picker is open
    }

    // MARK: - Buffering Feedback

    func testBufferingTimerTick_incrementsElapsed() async {
        var state = VideoPlayerFeature.State(channel: makeChannel())
        state.status = .loading
        state.bufferingElapsedSeconds = 5

        let store = TestStore(initialState: state) {
            VideoPlayerFeature()
        }

        await store.send(.bufferingTimerTick) {
            $0.bufferingElapsedSeconds = 6
        }
    }

    func testBufferingTimerTick_nonLoading_noOp() async {
        var state = VideoPlayerFeature.State(channel: makeChannel())
        state.status = .playing
        state.bufferingElapsedSeconds = 5

        let store = TestStore(initialState: state) {
            VideoPlayerFeature()
        }

        await store.send(.bufferingTimerTick)
    }

    func testPlayerPlaying_resetsBufferingElapsed() async {
        var state = VideoPlayerFeature.State(channel: makeChannel())
        state.status = .loading
        state.bufferingElapsedSeconds = 15

        let store = TestStore(initialState: state) {
            VideoPlayerFeature()
        } withDependencies: {
            $0.continuousClock = ImmediateClock()
        }
        store.exhaustivity = .off

        await store.send(.playerStatusChanged(.playing)) {
            $0.status = .playing
            $0.retryCount = 0
            $0.bufferingElapsedSeconds = 0
        }

        await store.skipReceivedActions()
    }

    // MARK: - Channel Number Entry

    func testNumberDigitPressed_startsEntry() async {
        var state = VideoPlayerFeature.State(channel: makeChannel())
        state.isOverlayVisible = true

        let store = TestStore(initialState: state) {
            VideoPlayerFeature()
        } withDependencies: {
            $0.continuousClock = ImmediateClock()
            $0.channelListClient.fetchByNumber = { _, _ in nil }
        }
        store.exhaustivity = .off

        await store.send(.numberDigitPressed("5")) {
            $0.isNumberEntryVisible = true
            $0.isOverlayVisible = false
            $0.numberEntryDigits = "5"
        }

        await store.skipReceivedActions()
    }

    func testNumberDigitPressed_appendsMultiple() async {
        var state = VideoPlayerFeature.State(channel: makeChannel())
        state.isNumberEntryVisible = true
        state.numberEntryDigits = "1"

        let store = TestStore(initialState: state) {
            VideoPlayerFeature()
        } withDependencies: {
            $0.continuousClock = ImmediateClock()
            $0.channelListClient.fetchByNumber = { _, _ in nil }
        }
        store.exhaustivity = .off

        await store.send(.numberDigitPressed("2")) {
            $0.numberEntryDigits = "12"
        }

        await store.skipReceivedActions()
    }

    func testNumberDigitPressed_vodItem_noOp() async {
        let vodItem = VodItemRecord(
            id: "vod-1",
            playlistID: "pl-1",
            title: "Movie",
            type: "movie",
            streamURL: "http://example.com/movie.mp4"
        )
        let store = TestStore(
            initialState: VideoPlayerFeature.State(vodItem: vodItem)
        ) {
            VideoPlayerFeature()
        }

        await store.send(.numberDigitPressed("5"))
    }

    func testNumberEntryAutoHide_looksUpChannel() async {
        let channel = makeChannel(id: "ch-42")

        var state = VideoPlayerFeature.State(channel: makeChannel())
        state.isNumberEntryVisible = true
        state.numberEntryDigits = "42"

        let store = TestStore(initialState: state) {
            VideoPlayerFeature()
        } withDependencies: {
            $0.continuousClock = ImmediateClock()
            $0.channelListClient.fetchByNumber = { _, number in
                number == 42 ? channel : nil
            }
            $0.watchProgressClient.getProgress = { _ in nil }
            $0.watchProgressClient.saveProgress = { _, _, _, _ in }
            $0.streamRouterClient.route = { url in
                StreamRoute(recommendedEngine: .avPlayer, url: url, reason: "test")
            }
        }
        store.exhaustivity = .off

        await store.send(.numberEntryAutoHideExpired) {
            $0.numberEntryResult = .searching
        }

        await store.receive(\.numberEntryLookupResult) {
            $0.numberEntryResult = .found(channel)
        }

        await store.skipReceivedActions()
    }

    func testNumberEntryLookupResult_notFound() async {
        var state = VideoPlayerFeature.State(channel: makeChannel())
        state.isNumberEntryVisible = true
        state.numberEntryDigits = "999"

        let store = TestStore(initialState: state) {
            VideoPlayerFeature()
        } withDependencies: {
            $0.continuousClock = ImmediateClock()
        }
        store.exhaustivity = .off

        await store.send(.numberEntryLookupResult(nil)) {
            $0.numberEntryResult = .notFound
        }

        // Auto-cancels after 1s (immediate with ImmediateClock)
        await store.skipReceivedActions()
    }

    func testNumberEntryConfirmed_switchesChannel() async {
        let targetChannel = makeChannel(id: "ch-42", name: "CNN", streamURL: "http://example.com/cnn.m3u8")
        let url = URL(string: "http://example.com/cnn.m3u8")!

        var state = VideoPlayerFeature.State(channel: makeChannel())
        state.status = .playing
        state.isNumberEntryVisible = true
        state.numberEntryDigits = "42"
        state.numberEntryResult = .found(targetChannel)

        let store = TestStore(initialState: state) {
            VideoPlayerFeature()
        } withDependencies: {
            $0.streamRouterClient.route = { _ in
                StreamRoute(recommendedEngine: .avPlayer, url: url, reason: "test")
            }
            $0.continuousClock = ImmediateClock()
            $0.watchProgressClient.getProgress = { _ in nil }
            $0.watchProgressClient.saveProgress = { _, _, _, _ in }
        }
        store.exhaustivity = .off

        await store.send(.numberEntryConfirmed) {
            $0.isNumberEntryVisible = false
            $0.numberEntryDigits = ""
            $0.numberEntryResult = nil
            $0.item = PlayableItem(channel: targetChannel)
            $0.status = .idle
            $0.activeEngine = nil
            $0.streamRoute = nil
            $0.playerCommand = .stop
            $0.retryCount = 0
            $0.hasTriedFallbackEngine = false
            $0.resumePositionMs = nil
            $0.currentPositionMs = 0
            $0.currentDurationMs = nil
        }

        await store.receive(\.delegate.channelSwitched)

        await store.skipReceivedActions()
    }

    func testNumberEntryCancelled_clearsState() async {
        var state = VideoPlayerFeature.State(channel: makeChannel())
        state.isNumberEntryVisible = true
        state.numberEntryDigits = "12"
        state.numberEntryResult = .notFound

        let store = TestStore(initialState: state) {
            VideoPlayerFeature()
        }

        await store.send(.numberEntryCancelled) {
            $0.isNumberEntryVisible = false
            $0.numberEntryDigits = ""
            $0.numberEntryResult = nil
        }
    }

    // MARK: - User Preferences

    func testOnAppear_autoEngine_usesRouterRecommendation() async {
        let store = makeStore(
            route: { url in
                StreamRoute(recommendedEngine: .vlcKit, url: url, reason: "MPEG-TS")
            }
        )
        store.exhaustivity = .off

        await store.send(.onAppear) {
            $0.status = .routing
        }

        await store.receive(\.streamRouted) {
            $0.streamRoute = StreamRoute(
                recommendedEngine: .vlcKit,
                url: URL(string: "http://example.com/stream.m3u8")!,
                reason: "MPEG-TS"
            )
            $0.activeEngine = .vlcKit
            $0.status = .loading
            $0.playerCommand = .play(
                url: URL(string: "http://example.com/stream.m3u8")!,
                engine: .vlcKit
            )
        }

        await store.skipReceivedActions()
    }

    func testOnAppear_preferredAVPlayer_overridesRouter() async {
        let ch = makeChannel()
        let store = TestStore(initialState: VideoPlayerFeature.State(channel: ch)) {
            VideoPlayerFeature()
        } withDependencies: {
            $0.streamRouterClient.route = { url in
                StreamRoute(recommendedEngine: .vlcKit, url: url, reason: "MPEG-TS")
            }
            $0.continuousClock = ImmediateClock()
            $0.watchProgressClient.getProgress = { _ in nil }
            $0.watchProgressClient.saveProgress = { _, _, _, _ in }
            $0.userDefaultsClient.stringForKey = { key in
                if key == UserDefaultsKey.preferredPlayerEngine { return "avPlayer" }
                return nil
            }
        }
        store.exhaustivity = .off

        await store.send(.onAppear) {
            $0.preferredEngine = .avPlayer
            $0.status = .routing
        }

        await store.receive(\.streamRouted) {
            $0.streamRoute = StreamRoute(
                recommendedEngine: .avPlayer,
                url: URL(string: "http://example.com/stream.m3u8")!,
                reason: "User preference (AVPlayer)"
            )
            $0.activeEngine = .avPlayer
            $0.status = .loading
            $0.playerCommand = .play(
                url: URL(string: "http://example.com/stream.m3u8")!,
                engine: .avPlayer
            )
        }

        await store.skipReceivedActions()
    }

    func testOnAppear_preferredVLCKit_overridesRouter() async {
        let ch = makeChannel()
        let store = TestStore(initialState: VideoPlayerFeature.State(channel: ch)) {
            VideoPlayerFeature()
        } withDependencies: {
            $0.streamRouterClient.route = { url in
                StreamRoute(recommendedEngine: .avPlayer, url: url, reason: "HLS")
            }
            $0.continuousClock = ImmediateClock()
            $0.watchProgressClient.getProgress = { _ in nil }
            $0.watchProgressClient.saveProgress = { _, _, _, _ in }
            $0.userDefaultsClient.stringForKey = { key in
                if key == UserDefaultsKey.preferredPlayerEngine { return "vlcKit" }
                return nil
            }
        }
        store.exhaustivity = .off

        await store.send(.onAppear) {
            $0.preferredEngine = .vlcKit
            $0.status = .routing
        }

        await store.receive(\.streamRouted) {
            $0.streamRoute = StreamRoute(
                recommendedEngine: .vlcKit,
                url: URL(string: "http://example.com/stream.m3u8")!,
                reason: "User preference (VLCKit)"
            )
            $0.activeEngine = .vlcKit
            $0.status = .loading
            $0.playerCommand = .play(
                url: URL(string: "http://example.com/stream.m3u8")!,
                engine: .vlcKit
            )
        }

        await store.skipReceivedActions()
    }

    func testOnAppear_resumeDisabled_noResumePosition() async {
        let progress = WatchProgressRecord(
            contentID: "ch-1",
            playlistID: "pl-1",
            positionMs: 120_000,
            durationMs: 3_600_000,
            updatedAt: 1_000_000
        )
        let ch = makeChannel()
        let store = TestStore(initialState: VideoPlayerFeature.State(channel: ch)) {
            VideoPlayerFeature()
        } withDependencies: {
            $0.streamRouterClient.route = { url in
                StreamRoute(recommendedEngine: .avPlayer, url: url, reason: "test")
            }
            $0.continuousClock = ImmediateClock()
            $0.watchProgressClient.getProgress = { _ in progress }
            $0.watchProgressClient.saveProgress = { _, _, _, _ in }
            $0.userDefaultsClient.stringForKey = { key in
                if key == UserDefaultsKey.resumePlaybackEnabled { return "false" }
                return nil
            }
        }
        store.exhaustivity = .off

        await store.send(.onAppear) {
            $0.resumePlaybackEnabled = false
            $0.status = .routing
        }

        await store.skipReceivedActions()

        // Resume should not be set since resume playback is disabled
        XCTAssertNil(store.state.resumePositionMs)
    }

    func testRetryTapped_respectsPreferredEngine() async {
        var state = VideoPlayerFeature.State(channel: makeChannel())
        state.preferredEngine = .vlcKit
        state.status = .failed
        state.streamRoute = StreamRoute(
            recommendedEngine: .avPlayer,
            url: URL(string: "http://example.com/stream.m3u8")!,
            reason: "HLS"
        )

        let store = TestStore(initialState: state) {
            VideoPlayerFeature()
        }

        await store.send(.retryTapped) {
            $0.retryCount = 0
            $0.hasTriedFallbackEngine = false
            $0.activeEngine = .vlcKit // Uses preferred, not router's .avPlayer
            $0.status = .loading
            $0.playerCommand = .play(
                url: URL(string: "http://example.com/stream.m3u8")!,
                engine: .vlcKit
            )
        }
    }

    func testBufferTimeoutSeconds_loadedFromPreferences() async {
        let ch = makeChannel()
        let store = TestStore(initialState: VideoPlayerFeature.State(channel: ch)) {
            VideoPlayerFeature()
        } withDependencies: {
            $0.streamRouterClient.route = { url in
                StreamRoute(recommendedEngine: .avPlayer, url: url, reason: "test")
            }
            $0.continuousClock = ImmediateClock()
            $0.watchProgressClient.getProgress = { _ in nil }
            $0.watchProgressClient.saveProgress = { _, _, _, _ in }
            $0.userDefaultsClient.stringForKey = { key in
                if key == UserDefaultsKey.bufferTimeoutSeconds { return "20" }
                return nil
            }
        }
        store.exhaustivity = .off

        await store.send(.onAppear) {
            $0.bufferTimeoutSeconds = 20
            $0.status = .routing
        }

        await store.skipReceivedActions()
    }
}
