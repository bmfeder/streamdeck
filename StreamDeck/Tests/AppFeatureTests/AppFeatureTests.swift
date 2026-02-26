import ComposableArchitecture
import Database
import Repositories
import XCTest
@testable import AppFeature

@MainActor
final class AppFeatureTests: XCTestCase {

    // MARK: - Initial State

    func testInitialState_homeTabSelected() {
        let state = AppFeature.State()
        XCTAssertEqual(state.selectedTab, .home)
    }

    func testInitialState_disclaimerNotAccepted() {
        let state = AppFeature.State()
        XCTAssertFalse(state.hasAcceptedDisclaimer)
    }

    // MARK: - Tab Selection

    func testTabSelection_changesTab() async {
        let store = TestStore(initialState: AppFeature.State()) {
            AppFeature()
        }
        await store.send(.tabSelected(.liveTV)) {
            $0.selectedTab = .liveTV
        }
        await store.send(.tabSelected(.settings)) {
            $0.selectedTab = .settings
        }
        await store.send(.tabSelected(.home)) {
            $0.selectedTab = .home
        }
    }

    // MARK: - Disclaimer

    func testAcceptDisclaimer_setsFlag_andPersists() async {
        let persisted = LockIsolated(false)
        let store = TestStore(initialState: AppFeature.State()) {
            AppFeature()
        } withDependencies: {
            $0.userDefaultsClient.setBool = { value, _ in
                persisted.setValue(value)
            }
        }
        await store.send(.acceptDisclaimerTapped) {
            $0.hasAcceptedDisclaimer = true
        }
        XCTAssertTrue(persisted.value)
    }

    func testOnAppear_loadsPersistedDisclaimer() async {
        let store = TestStore(initialState: AppFeature.State()) {
            AppFeature()
        } withDependencies: {
            $0.userDefaultsClient.boolForKey = { key in
                XCTAssertEqual(key, UserDefaultsKey.hasAcceptedDisclaimer)
                return true
            }
            $0.vodListClient.fetchPlaylists = { [] }
        }
        store.exhaustivity = .off
        await store.send(.onAppear) {
            $0.hasAcceptedDisclaimer = true
        }
        await store.skipReceivedActions()
    }

    func testOnAppear_noPriorAcceptance_remainsFalse() async {
        let store = TestStore(initialState: AppFeature.State()) {
            AppFeature()
        } withDependencies: {
            $0.userDefaultsClient.boolForKey = { _ in false }
            $0.vodListClient.fetchPlaylists = { [] }
        }
        store.exhaustivity = .off
        await store.send(.onAppear)
        await store.skipReceivedActions()
    }

    // MARK: - Auto-Refresh

    func testOnAppear_refreshesStalePlaylist() async {
        let stalePlaylist = PlaylistRecord(
            id: "pl-stale", name: "Stale", type: "m3u",
            url: "http://example.com/pl.m3u",
            lastSync: 1, // Very old timestamp
            sortOrder: 0
        )
        let refreshed = LockIsolated(false)

        let store = TestStore(initialState: AppFeature.State()) {
            AppFeature()
        } withDependencies: {
            $0.userDefaultsClient.boolForKey = { _ in true }
            $0.vodListClient.fetchPlaylists = { [stalePlaylist] }
            $0.playlistImportClient.refreshPlaylist = { _ in
                refreshed.setValue(true)
                return PlaylistImportResult(
                    playlist: stalePlaylist,
                    importResult: ImportResult(added: 0, updated: 0, softDeleted: 0, unchanged: 5)
                )
            }
        }
        store.exhaustivity = .off

        await store.send(.onAppear) {
            $0.hasAcceptedDisclaimer = true
        }
        await store.skipReceivedActions()
        XCTAssertTrue(refreshed.value)
    }

    func testOnAppear_skipsRecentlyRefreshedPlaylist() async {
        let freshPlaylist = PlaylistRecord(
            id: "pl-fresh", name: "Fresh", type: "m3u",
            url: "http://example.com/pl.m3u",
            lastSync: Int(Date().timeIntervalSince1970), // Just synced
            sortOrder: 0
        )
        let refreshed = LockIsolated(false)

        let store = TestStore(initialState: AppFeature.State()) {
            AppFeature()
        } withDependencies: {
            $0.userDefaultsClient.boolForKey = { _ in false }
            $0.vodListClient.fetchPlaylists = { [freshPlaylist] }
            $0.playlistImportClient.refreshPlaylist = { _ in
                refreshed.setValue(true)
                return PlaylistImportResult(
                    playlist: freshPlaylist,
                    importResult: ImportResult(added: 0, updated: 0, softDeleted: 0, unchanged: 0)
                )
            }
        }
        store.exhaustivity = .off

        await store.send(.onAppear)
        await store.skipReceivedActions()
        XCTAssertFalse(refreshed.value)
    }

    // MARK: - Child Feature Actions

    func testSearchQueryChanged_passesThrough() async {
        let store = TestStore(initialState: AppFeature.State()) {
            AppFeature()
        } withDependencies: {
            $0.channelListClient.searchChannels = { _, _ in [] }
            $0.vodListClient.searchVod = { _, _, _ in [] }
            $0.epgClient.searchPrograms = { _ in [] }
        }
        store.exhaustivity = .off
        await store.send(.search(.searchQueryChanged("test"))) {
            $0.search.searchQuery = "test"
            $0.search.isSearching = true
            $0.search.pendingSearchCount = 3
        }
        await store.skipReceivedActions()
    }

    func testHomeOnAppear_loadsData() async {
        let store = TestStore(initialState: AppFeature.State()) {
            AppFeature()
        } withDependencies: {
            $0.watchProgressClient.getUnfinished = { _ in [] }
            $0.watchProgressClient.getRecentlyWatched = { _ in [] }
            $0.channelListClient.fetchFavorites = { [] }
        }
        store.exhaustivity = .off
        await store.send(.home(.onAppear)) {
            $0.home.isLoading = true
        }
        await store.skipReceivedActions()
    }

    func testLiveTVOnAppear_loadsPlaylists() async {
        let store = TestStore(initialState: AppFeature.State()) {
            AppFeature()
        } withDependencies: {
            $0.channelListClient.fetchPlaylists = { [] }
        }
        await store.send(.liveTV(.onAppear)) {
            $0.liveTV.isLoading = true
        }
        await store.receive(\.liveTV.playlistsLoaded.success) {
            $0.liveTV.isLoading = false
        }
    }

    func testSettingsOnAppear_loadsPlaylists() async {
        let store = TestStore(initialState: AppFeature.State()) {
            AppFeature()
        } withDependencies: {
            $0.vodListClient.fetchPlaylists = { [] }
            $0.userDefaultsClient.stringForKey = { _ in nil }
        }
        store.exhaustivity = .off
        await store.send(.settings(.onAppear))
        await store.skipReceivedActions()
    }

    // MARK: - Settings → Add Playlist

    func testSettingsAddM3UTapped_presentsAddPlaylist() async {
        let store = TestStore(initialState: AppFeature.State()) {
            AppFeature()
        }
        await store.send(.settings(.addM3UTapped)) {
            $0.settings.addPlaylist = AddPlaylistFeature.State(sourceType: .m3u)
        }
    }

    func testSettingsAddXtreamTapped_presentsAddPlaylist() async {
        let store = TestStore(initialState: AppFeature.State()) {
            AppFeature()
        }
        await store.send(.settings(.addXtreamTapped)) {
            $0.settings.addPlaylist = AddPlaylistFeature.State(sourceType: .xtream)
        }
    }

    func testSettingsAddEmbyTapped_presentsAddPlaylist() async {
        let store = TestStore(initialState: AppFeature.State()) {
            AppFeature()
        }
        await store.send(.settings(.addEmbyTapped)) {
            $0.settings.addPlaylist = AddPlaylistFeature.State(sourceType: .emby)
        }
    }

    func testSettingsAddPlaylistDismiss_nilsState() async {
        var initialState = AppFeature.State()
        initialState.settings.addPlaylist = AddPlaylistFeature.State(sourceType: .m3u)

        let store = TestStore(initialState: initialState) {
            AppFeature()
        }
        await store.send(.settings(.addPlaylist(.dismiss))) {
            $0.settings.addPlaylist = nil
        }
    }

    // MARK: - Now Playing Mini-Bar

    private func makeChannel(
        id: String = "ch-1",
        name: String = "CNN"
    ) -> ChannelRecord {
        ChannelRecord(
            id: id,
            playlistID: "pl-1",
            name: name,
            streamURL: "http://example.com/\(id).m3u8"
        )
    }

    func testPlayChannelFromLiveTV_setsNowPlaying() async {
        let channel = makeChannel()

        let store = TestStore(initialState: AppFeature.State()) {
            AppFeature()
        }
        store.exhaustivity = .off

        await store.send(.liveTV(.delegate(.playChannel(channel)))) {
            $0.nowPlayingChannel = channel
            $0.nowPlayingSourceTab = .liveTV
        }
    }

    func testPlayChannelFromFavorites_setsNowPlaying() async {
        let channel = makeChannel(id: "ch-2", name: "ESPN")

        let store = TestStore(initialState: AppFeature.State()) {
            AppFeature()
        }
        store.exhaustivity = .off

        await store.send(.favorites(.delegate(.playChannel(channel)))) {
            $0.nowPlayingChannel = channel
            $0.nowPlayingSourceTab = .favorites
        }
    }

    func testPlayerDismissed_clearsNowPlaying() async {
        var state = AppFeature.State()
        state.nowPlayingChannel = makeChannel()
        state.nowPlayingSourceTab = .liveTV
        state.liveTV.videoPlayer = VideoPlayerFeature.State(channel: makeChannel())

        let store = TestStore(initialState: state) {
            AppFeature()
        }
        store.exhaustivity = .off

        await store.send(.liveTV(.videoPlayer(.presented(.delegate(.dismissed))))) {
            $0.nowPlayingChannel = nil
            $0.nowPlayingSourceTab = nil
            $0.liveTV.videoPlayer = nil
        }
    }

    func testMiniBarTapped_switchesTabAndPlays() async {
        let channel = makeChannel()
        var state = AppFeature.State()
        state.nowPlayingChannel = channel
        state.nowPlayingSourceTab = .liveTV
        state.selectedTab = .home

        let store = TestStore(initialState: state) {
            AppFeature()
        } withDependencies: {
            $0.streamRouterClient.route = { url in
                StreamRoute(recommendedEngine: .avPlayer, url: url, reason: "test")
            }
            $0.continuousClock = ImmediateClock()
            $0.watchProgressClient.getProgress = { _ in nil }
            $0.watchProgressClient.saveProgress = { _, _, _, _ in }
        }
        store.exhaustivity = .off

        await store.send(.miniBarTapped) {
            $0.selectedTab = .liveTV
        }

        await store.receive(\.liveTV.channelTapped) {
            $0.liveTV.focusedChannelID = "ch-1"
            $0.liveTV.videoPlayer = VideoPlayerFeature.State(channel: channel)
        }

        await store.skipReceivedActions()
    }

    func testMiniBarDismissed_clearsState() async {
        var state = AppFeature.State()
        state.nowPlayingChannel = makeChannel()
        state.nowPlayingSourceTab = .liveTV

        let store = TestStore(initialState: state) {
            AppFeature()
        }

        await store.send(.miniBarDismissed) {
            $0.nowPlayingChannel = nil
            $0.nowPlayingSourceTab = nil
        }
    }

    func testMiniBarTapped_noChannel_noOp() async {
        let store = TestStore(initialState: AppFeature.State()) {
            AppFeature()
        }

        await store.send(.miniBarTapped)
    }

    // MARK: - Tab Enum

    func testTabCaseIterable_hasNine() {
        XCTAssertEqual(Tab.allCases.count, 9)
    }

    func testTabTitles_areNonEmpty() {
        for tab in Tab.allCases {
            XCTAssertFalse(tab.title.isEmpty, "\(tab) has empty title")
        }
    }

    func testTabSystemImages_areNonEmpty() {
        for tab in Tab.allCases {
            XCTAssertFalse(tab.systemImage.isEmpty, "\(tab) has empty systemImage")
        }
    }

    // MARK: - Settings Playback Preferences

    func testSettingsOnAppear_loadsPreferences() async {
        let store = TestStore(initialState: AppFeature.State()) {
            AppFeature()
        } withDependencies: {
            $0.vodListClient.fetchPlaylists = { [] }
            $0.userDefaultsClient.stringForKey = { key in
                if key == UserDefaultsKey.preferredPlayerEngine { return "vlcKit" }
                if key == UserDefaultsKey.resumePlaybackEnabled { return "false" }
                if key == UserDefaultsKey.bufferTimeoutSeconds { return "20" }
                return nil
            }
        }
        store.exhaustivity = .off

        await store.send(.settings(.onAppear))
        await store.receive(\.settings.preferencesLoaded) {
            $0.settings.preferences = UserPreferences(
                preferredEngine: .vlcKit,
                resumePlaybackEnabled: false,
                bufferTimeoutSeconds: 20
            )
        }
        await store.skipReceivedActions()
    }

    func testPreferredEngineChanged_updatesAndPersists() async {
        let saved = LockIsolated<[String: String]>([:])
        let store = TestStore(initialState: AppFeature.State()) {
            AppFeature()
        } withDependencies: {
            $0.userDefaultsClient.setString = { value, key in
                saved.withValue { $0[key] = value }
            }
            $0.cloudKitSyncClient.pushPreferences = { _ in }
        }

        await store.send(.settings(.preferredEngineChanged(.vlcKit))) {
            $0.settings.preferences.preferredEngine = .vlcKit
        }
        XCTAssertEqual(saved.value[UserDefaultsKey.preferredPlayerEngine], "vlcKit")
    }

    func testBufferTimeoutChanged_updatesAndPersists() async {
        let saved = LockIsolated<[String: String]>([:])
        let store = TestStore(initialState: AppFeature.State()) {
            AppFeature()
        } withDependencies: {
            $0.userDefaultsClient.setString = { value, key in
                saved.withValue { $0[key] = value }
            }
            $0.cloudKitSyncClient.pushPreferences = { _ in }
        }

        await store.send(.settings(.bufferTimeoutChanged(20))) {
            $0.settings.preferences.bufferTimeoutSeconds = 20
        }
        XCTAssertEqual(saved.value[UserDefaultsKey.bufferTimeoutSeconds], "20")
    }
}
