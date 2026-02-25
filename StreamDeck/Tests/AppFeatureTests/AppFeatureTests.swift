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
        }
        store.exhaustivity = .off
        await store.send(.search(.searchQueryChanged("test"))) {
            $0.search.searchQuery = "test"
            $0.search.isSearching = true
        }
        await store.skipReceivedActions()
    }

    func testHomeOnAppear_loadsData() async {
        let store = TestStore(initialState: AppFeature.State()) {
            AppFeature()
        } withDependencies: {
            $0.watchProgressClient.getUnfinished = { _ in [] }
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
}
