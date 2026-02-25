import ComposableArchitecture
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
        }
        await store.send(.onAppear) {
            $0.hasAcceptedDisclaimer = true
        }
    }

    func testOnAppear_noPriorAcceptance_remainsFalse() async {
        let store = TestStore(initialState: AppFeature.State()) {
            AppFeature()
        } withDependencies: {
            $0.userDefaultsClient.boolForKey = { _ in false }
        }
        await store.send(.onAppear)
    }

    // MARK: - Child Feature Actions

    func testHomeOnAppear_passesThrough() async {
        let store = TestStore(initialState: AppFeature.State()) {
            AppFeature()
        }
        await store.send(.home(.onAppear))
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

    func testSettingsOnAppear_passesThrough() async {
        let store = TestStore(initialState: AppFeature.State()) {
            AppFeature()
        }
        await store.send(.settings(.onAppear))
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

    func testTabCaseIterable_hasEight() {
        XCTAssertEqual(Tab.allCases.count, 8)
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
