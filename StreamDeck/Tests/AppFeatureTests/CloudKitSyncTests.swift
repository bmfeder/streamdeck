import ComposableArchitecture
import Database
import Repositories
import XCTest
@testable import AppFeature

@MainActor
final class CloudKitSyncTests: XCTestCase {

    // MARK: - Helpers

    private func makePlaylist(
        id: String = "pl-1",
        name: String = "Test",
        type: String = "m3u"
    ) -> PlaylistRecord {
        PlaylistRecord(id: id, name: name, type: type, url: "http://example.com/pl.m3u")
    }

    private func makeChannel(
        id: String = "ch-1",
        playlistID: String = "pl-1",
        name: String = "ESPN",
        isFavorite: Bool = false
    ) -> ChannelRecord {
        ChannelRecord(
            id: id, playlistID: playlistID, name: name,
            streamURL: "http://example.com/stream", isFavorite: isFavorite
        )
    }

    // MARK: - AppFeature: Pull on Launch

    func testAppOnAppear_pullsFromCloudKit() async {
        let pullCalled = LockIsolated(false)

        let store = TestStore(initialState: AppFeature.State()) {
            AppFeature()
        } withDependencies: {
            $0.userDefaultsClient.boolForKey = { _ in false }
            $0.vodListClient.fetchPlaylists = { [] }
            $0.cloudKitSyncClient.isAvailable = { true }
            $0.cloudKitSyncClient.pullAll = {
                pullCalled.setValue(true)
                return SyncPullResult()
            }
        }
        store.exhaustivity = .off

        await store.send(.onAppear)
        await store.skipReceivedActions()

        XCTAssertTrue(pullCalled.value)
    }

    func testAppOnAppear_cloudKitUnavailable_skipsSync() async {
        let pullCalled = LockIsolated(false)

        let store = TestStore(initialState: AppFeature.State()) {
            AppFeature()
        } withDependencies: {
            $0.userDefaultsClient.boolForKey = { _ in false }
            $0.vodListClient.fetchPlaylists = { [] }
            $0.cloudKitSyncClient.isAvailable = { false }
            $0.cloudKitSyncClient.pullAll = {
                pullCalled.setValue(true)
                return SyncPullResult()
            }
        }
        store.exhaustivity = .off

        await store.send(.onAppear)
        await store.skipReceivedActions()

        XCTAssertFalse(pullCalled.value)
    }

    func testCloudKitPullCompleted_failure_silentlyIgnored() async {
        let store = TestStore(initialState: AppFeature.State()) {
            AppFeature()
        }

        await store.send(.cloudKitPullCompleted(.failure(NSError(domain: "test", code: 1))))
    }

    // MARK: - SettingsFeature: CloudKit Status

    func testSettingsOnAppear_checksCloudKitStatus() async {
        let store = TestStore(initialState: SettingsFeature.State()) {
            SettingsFeature()
        } withDependencies: {
            $0.userDefaultsClient.stringForKey = { _ in nil }
            $0.vodListClient.fetchPlaylists = { [] }
            $0.cloudKitSyncClient.isAvailable = { true }
        }
        store.exhaustivity = .off

        await store.send(.onAppear)
        await store.skipReceivedActions()

        store.assert {
            $0.isCloudKitAvailable = true
        }
    }

    // MARK: - SettingsFeature: Sync Now

    func testSyncNowTapped_triggersFullPull() async {
        let store = TestStore(initialState: SettingsFeature.State()) {
            SettingsFeature()
        } withDependencies: {
            $0.cloudKitSyncClient.pullAll = {
                SyncPullResult(playlistsUpdated: 2, favoritesUpdated: 1)
            }
        }

        await store.send(.syncNowTapped) {
            $0.isSyncing = true
        }

        await store.receive(\.syncCompleted.success) {
            $0.isSyncing = false
            $0.lastSyncResult = SyncPullResult(playlistsUpdated: 2, favoritesUpdated: 1)
        }
    }

    func testSyncCompleted_failure_clearsLoading() async {
        var state = SettingsFeature.State()
        state.isSyncing = true

        let store = TestStore(initialState: state) {
            SettingsFeature()
        }

        await store.send(.syncCompleted(.failure(NSError(domain: "test", code: 1)))) {
            $0.isSyncing = false
        }
    }

    // MARK: - SettingsFeature: Push on Deletion

    func testDeletePlaylistConfirmed_pushesDeletion() async {
        let pushedID = LockIsolated<String?>(nil)
        var state = SettingsFeature.State()
        let playlist = makePlaylist(id: "pl-del", name: "To Delete")
        state.playlists = [playlist]
        state.playlistToDelete = playlist

        let store = TestStore(initialState: state) {
            SettingsFeature()
        } withDependencies: {
            $0.playlistImportClient.deletePlaylist = { _ in }
            $0.cloudKitSyncClient.pushPlaylistDeletion = { id in
                pushedID.setValue(id)
            }
        }
        store.exhaustivity = .off

        await store.send(.deletePlaylistConfirmed) {
            $0.playlistToDelete = nil
        }
        await store.skipReceivedActions()

        XCTAssertEqual(pushedID.value, "pl-del")
    }

    // MARK: - SettingsFeature: Push Preferences

    func testPreferredEngineChanged_pushesPreferences() async {
        let pushedEngine = LockIsolated<String?>(nil)

        let store = TestStore(initialState: SettingsFeature.State()) {
            SettingsFeature()
        } withDependencies: {
            $0.userDefaultsClient.setString = { _, _ in }
            $0.cloudKitSyncClient.pushPreferences = { prefs in
                pushedEngine.setValue(prefs.preferredEngine)
            }
        }
        store.exhaustivity = .off

        await store.send(.preferredEngineChanged(.vlcKit)) {
            $0.preferences.preferredEngine = .vlcKit
        }

        XCTAssertEqual(pushedEngine.value, "vlcKit")
    }

    // MARK: - LiveTVFeature: Push Favorites

    func testLiveTVFavoriteToggled_pushesToCloudKit() async {
        let pushedChannelID = LockIsolated<String?>(nil)
        var state = LiveTVFeature.State()
        let channel = makeChannel(id: "ch-fav", isFavorite: false)
        state.displayedChannels = [channel]

        let store = TestStore(initialState: state) {
            LiveTVFeature()
        } withDependencies: {
            $0.channelListClient.toggleFavorite = { _ in }
            $0.cloudKitSyncClient.pushFavorite = { channelID, _, _ in
                pushedChannelID.setValue(channelID)
            }
        }
        store.exhaustivity = .off

        await store.send(.toggleFavoriteTapped("ch-fav"))
        await store.skipReceivedActions()

        XCTAssertEqual(pushedChannelID.value, "ch-fav")
    }

    // MARK: - FavoritesFeature: Push Unfavorite

    func testFavoritesFavoriteToggled_pushesToCloudKit() async {
        let pushedIsFavorite = LockIsolated<Bool?>(nil)
        var state = FavoritesFeature.State()
        let channel = makeChannel(id: "ch-unfav", isFavorite: true)
        state.channels = [channel]

        let store = TestStore(initialState: state) {
            FavoritesFeature()
        } withDependencies: {
            $0.channelListClient.toggleFavorite = { _ in }
            $0.cloudKitSyncClient.pushFavorite = { _, _, isFavorite in
                pushedIsFavorite.setValue(isFavorite)
            }
        }
        store.exhaustivity = .off

        await store.send(.toggleFavoriteTapped("ch-unfav"))
        await store.skipReceivedActions()

        XCTAssertEqual(pushedIsFavorite.value, false)
    }

    // MARK: - VideoPlayerFeature: Push Watch Progress

    func testVideoPlayerSaveProgress_pushesToCloudKit() async {
        let pushedContentID = LockIsolated<String?>(nil)
        let channel = makeChannel(id: "ch-prog")
        var state = VideoPlayerFeature.State(channel: channel)
        state.currentPositionMs = 30000
        state.currentDurationMs = 60000

        let store = TestStore(initialState: state) {
            VideoPlayerFeature()
        } withDependencies: {
            $0.watchProgressClient.saveProgress = { _, _, _, _ in }
            $0.cloudKitSyncClient.pushWatchProgress = { record in
                pushedContentID.setValue(record.contentID)
            }
        }

        await store.send(.saveProgress)
    }

    func testVideoPlayerSaveProgress_cloudKitFails_localStillSaves() async {
        let localSaved = LockIsolated(false)
        let channel = makeChannel(id: "ch-fail")
        var state = VideoPlayerFeature.State(channel: channel)
        state.currentPositionMs = 30000

        let store = TestStore(initialState: state) {
            VideoPlayerFeature()
        } withDependencies: {
            $0.watchProgressClient.saveProgress = { _, _, _, _ in
                localSaved.setValue(true)
            }
            $0.cloudKitSyncClient.pushWatchProgress = { _ in
                throw NSError(domain: "CloudKit", code: 1)
            }
        }

        await store.send(.saveProgress)

        XCTAssertTrue(localSaved.value)
    }
}
