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

        await store.send(.streamRouted(route)) {
            $0.streamRoute = route
            $0.activeEngine = .vlcKit
            $0.status = .loading
            $0.playerCommand = .play(url: url, engine: .vlcKit)
        }

        await store.receive(\.overlayAutoHideExpired)
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

        var state = VideoPlayerFeature.State(channel: makeChannel())
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
}
