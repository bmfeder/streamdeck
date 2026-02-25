import ComposableArchitecture
import Database
import Repositories
import XCTest
@testable import AppFeature

@MainActor
final class SettingsFeatureTests: XCTestCase {

    // MARK: - Helpers

    private func makePlaylist(
        id: String = "pl-1",
        name: String = "Test Playlist",
        type: String = "m3u",
        lastSync: Int? = nil,
        sortOrder: Int = 0
    ) -> PlaylistRecord {
        PlaylistRecord(
            id: id, name: name, type: type, url: "http://example.com/pl.m3u",
            lastSync: lastSync, sortOrder: sortOrder
        )
    }

    // MARK: - Load Playlists

    func testOnAppear_loadsPlaylists() async {
        let playlists = [
            makePlaylist(id: "pl-1", name: "My M3U", type: "m3u", sortOrder: 0),
            makePlaylist(id: "pl-2", name: "Xtream", type: "xtream", sortOrder: 1),
        ]

        let store = TestStore(initialState: SettingsFeature.State()) {
            SettingsFeature()
        } withDependencies: {
            $0.vodListClient.fetchPlaylists = { playlists }
        }

        await store.send(.onAppear)
        await store.receive(\.playlistsLoaded.success) {
            $0.playlists = playlists
        }
    }

    func testPlaylistsLoaded_failure_remainsEmpty() async {
        let store = TestStore(initialState: SettingsFeature.State()) {
            SettingsFeature()
        } withDependencies: {
            $0.vodListClient.fetchPlaylists = { throw NSError(domain: "test", code: 1) }
        }

        await store.send(.onAppear)
        await store.receive(\.playlistsLoaded.failure)
    }

    func testPlaylistsLoaded_orderedBySortOrder() async {
        let playlists = [
            makePlaylist(id: "pl-a", name: "Alpha", sortOrder: 0),
            makePlaylist(id: "pl-b", name: "Beta", sortOrder: 1),
            makePlaylist(id: "pl-c", name: "Gamma", sortOrder: 2),
        ]

        let store = TestStore(initialState: SettingsFeature.State()) {
            SettingsFeature()
        } withDependencies: {
            $0.vodListClient.fetchPlaylists = { playlists }
        }

        await store.send(.onAppear)
        await store.receive(\.playlistsLoaded.success) {
            $0.playlists = playlists
        }
        XCTAssertEqual(store.state.playlists.map(\.id), ["pl-a", "pl-b", "pl-c"])
    }

    // MARK: - Delete Flow

    func testDeletePlaylistTapped_setsPlaylistToDelete() async {
        let playlist = makePlaylist()

        let store = TestStore(initialState: SettingsFeature.State()) {
            SettingsFeature()
        }

        await store.send(.deletePlaylistTapped(playlist)) {
            $0.playlistToDelete = playlist
        }
    }

    func testDeletePlaylistCancelled_nilsPlaylistToDelete() async {
        var state = SettingsFeature.State()
        state.playlistToDelete = makePlaylist()

        let store = TestStore(initialState: state) {
            SettingsFeature()
        }

        await store.send(.deletePlaylistCancelled) {
            $0.playlistToDelete = nil
        }
    }

    func testDeletePlaylistConfirmed_deletesAndRemovesFromList() async {
        let playlist = makePlaylist(id: "pl-1", name: "To Delete")
        var state = SettingsFeature.State()
        state.playlists = [playlist, makePlaylist(id: "pl-2", name: "Keep")]
        state.playlistToDelete = playlist

        let deleted = LockIsolated<String?>(nil)
        let store = TestStore(initialState: state) {
            SettingsFeature()
        } withDependencies: {
            $0.playlistImportClient.deletePlaylist = { id in
                deleted.setValue(id)
            }
        }

        await store.send(.deletePlaylistConfirmed) {
            $0.playlistToDelete = nil
        }
        await store.receive(\.playlistDeleted.success) {
            $0.playlists = [self.makePlaylist(id: "pl-2", name: "Keep")]
        }
        XCTAssertEqual(deleted.value, "pl-1")
    }

    func testDeletePlaylistConfirmed_failure_keepsPlaylist() async {
        let playlist = makePlaylist(id: "pl-1")
        var state = SettingsFeature.State()
        state.playlists = [playlist]
        state.playlistToDelete = playlist

        let store = TestStore(initialState: state) {
            SettingsFeature()
        } withDependencies: {
            $0.playlistImportClient.deletePlaylist = { _ in
                throw NSError(domain: "test", code: 1)
            }
        }

        await store.send(.deletePlaylistConfirmed) {
            $0.playlistToDelete = nil
        }
        await store.receive(\.playlistDeleted.failure)
        // playlists array unchanged
        XCTAssertEqual(store.state.playlists.count, 1)
    }

    func testDeletePlaylistConfirmed_noPlaylistToDelete_noOp() async {
        let store = TestStore(initialState: SettingsFeature.State()) {
            SettingsFeature()
        }

        await store.send(.deletePlaylistConfirmed)
    }

    func testDeleteLastPlaylist_showsEmptyList() async {
        let playlist = makePlaylist(id: "pl-1")
        var state = SettingsFeature.State()
        state.playlists = [playlist]
        state.playlistToDelete = playlist

        let store = TestStore(initialState: state) {
            SettingsFeature()
        } withDependencies: {
            $0.playlistImportClient.deletePlaylist = { _ in }
        }

        await store.send(.deletePlaylistConfirmed) {
            $0.playlistToDelete = nil
        }
        await store.receive(\.playlistDeleted.success) {
            $0.playlists = []
        }
    }

    // MARK: - Import Completed Refreshes List

    func testImportCompleted_refreshesPlaylistList() async {
        let newPlaylist = makePlaylist(id: "pl-new", name: "New Playlist")

        var state = SettingsFeature.State()
        state.addPlaylist = AddPlaylistFeature.State(sourceType: .m3u)

        let store = TestStore(initialState: state) {
            SettingsFeature()
        } withDependencies: {
            $0.epgClient.syncEPG = { _ in
                EpgImportResult(programsImported: 0, programsPurged: 0, parseErrorCount: 0)
            }
            $0.vodListClient.fetchPlaylists = { [newPlaylist] }
        }
        store.exhaustivity = .off

        await store.send(.addPlaylist(.presented(.delegate(.importCompleted(playlistID: "pl-new")))))
        await store.skipReceivedActions()

        store.assert {
            $0.playlists = [newPlaylist]
        }
    }

    // MARK: - Add Playlist Buttons

    func testAddM3UTapped_presentsAddPlaylist() async {
        let store = TestStore(initialState: SettingsFeature.State()) {
            SettingsFeature()
        }

        await store.send(.addM3UTapped) {
            $0.addPlaylist = AddPlaylistFeature.State(sourceType: .m3u)
        }
    }

    func testAddXtreamTapped_presentsAddPlaylist() async {
        let store = TestStore(initialState: SettingsFeature.State()) {
            SettingsFeature()
        }

        await store.send(.addXtreamTapped) {
            $0.addPlaylist = AddPlaylistFeature.State(sourceType: .xtream)
        }
    }

    func testAddEmbyTapped_presentsAddPlaylist() async {
        let store = TestStore(initialState: SettingsFeature.State()) {
            SettingsFeature()
        }

        await store.send(.addEmbyTapped) {
            $0.addPlaylist = AddPlaylistFeature.State(sourceType: .emby)
        }
    }
}
