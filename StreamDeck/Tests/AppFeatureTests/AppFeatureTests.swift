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

    func testAcceptDisclaimer_setsFlag() async {
        let store = TestStore(initialState: AppFeature.State()) {
            AppFeature()
        }
        await store.send(.acceptDisclaimerTapped) {
            $0.hasAcceptedDisclaimer = true
        }
    }

    // MARK: - Child Feature Actions

    func testHomeOnAppear_passesThrough() async {
        let store = TestStore(initialState: AppFeature.State()) {
            AppFeature()
        }
        await store.send(.home(.onAppear))
    }

    func testLiveTVOnAppear_passesThrough() async {
        let store = TestStore(initialState: AppFeature.State()) {
            AppFeature()
        }
        await store.send(.liveTV(.onAppear))
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

    func testTabCaseIterable_hasSeven() {
        XCTAssertEqual(Tab.allCases.count, 7)
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
