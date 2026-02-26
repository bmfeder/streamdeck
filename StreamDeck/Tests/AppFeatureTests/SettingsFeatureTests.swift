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
        await store.receive(\.preferencesLoaded)
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
        await store.receive(\.preferencesLoaded)
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
        await store.receive(\.preferencesLoaded)
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

    // MARK: - Refresh

    func testRefreshPlaylistTapped_setsRefreshingID() async {
        let playlist = makePlaylist(id: "pl-1")
        var state = SettingsFeature.State()
        state.playlists = [playlist]

        let refreshedPlaylist = makePlaylist(id: "pl-1", lastSync: 1700000000)
        let store = TestStore(initialState: state) {
            SettingsFeature()
        } withDependencies: {
            $0.playlistImportClient.refreshPlaylist = { _ in
                PlaylistImportResult(
                    playlist: refreshedPlaylist,
                    importResult: ImportResult(added: 0, updated: 0, softDeleted: 0, unchanged: 10)
                )
            }
            $0.vodListClient.fetchPlaylists = { [refreshedPlaylist] }
        }
        store.exhaustivity = .off

        await store.send(.refreshPlaylistTapped(playlist)) {
            $0.refreshingPlaylistID = "pl-1"
        }
        await store.skipReceivedActions()

        store.assert {
            $0.refreshingPlaylistID = nil
            $0.playlists = [refreshedPlaylist]
        }
    }

    func testPlaylistRefreshed_failure_clearsRefreshing() async {
        let playlist = makePlaylist(id: "pl-1")
        var state = SettingsFeature.State()
        state.playlists = [playlist]

        let store = TestStore(initialState: state) {
            SettingsFeature()
        } withDependencies: {
            $0.playlistImportClient.refreshPlaylist = { _ in
                throw NSError(domain: "test", code: 1)
            }
        }

        await store.send(.refreshPlaylistTapped(playlist)) {
            $0.refreshingPlaylistID = "pl-1"
        }
        await store.receive(\.playlistRefreshed.failure) {
            $0.refreshingPlaylistID = nil
        }
    }

    func testRefreshPlaylistTapped_whileAlreadyRefreshing_noOp() async {
        var state = SettingsFeature.State()
        state.refreshingPlaylistID = "pl-other"

        let store = TestStore(initialState: state) {
            SettingsFeature()
        }

        await store.send(.refreshPlaylistTapped(makePlaylist(id: "pl-1")))
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

    // MARK: - Edit Playlist

    func testEditPlaylistTapped_populatesFields() async {
        let playlist = makePlaylist(id: "pl-1", name: "My Playlist")

        let store = TestStore(initialState: SettingsFeature.State()) {
            SettingsFeature()
        }

        await store.send(.editPlaylistTapped(playlist)) {
            $0.editingPlaylist = playlist
            $0.editName = "My Playlist"
            $0.editEpgURL = ""
            $0.editRefreshHrs = 24
        }
    }

    func testEditPlaylistTapped_withEpgURL_populatesEpgField() async {
        var playlist = makePlaylist(id: "pl-1", name: "My Playlist")
        playlist.epgURL = "http://example.com/epg.xml"
        playlist.refreshHrs = 6

        let store = TestStore(initialState: SettingsFeature.State()) {
            SettingsFeature()
        }

        await store.send(.editPlaylistTapped(playlist)) {
            $0.editingPlaylist = playlist
            $0.editName = "My Playlist"
            $0.editEpgURL = "http://example.com/epg.xml"
            $0.editRefreshHrs = 6
        }
    }

    func testEditNameChanged_updatesField() async {
        var state = SettingsFeature.State()
        state.editingPlaylist = makePlaylist()

        let store = TestStore(initialState: state) {
            SettingsFeature()
        }

        await store.send(.editNameChanged("New Name")) {
            $0.editName = "New Name"
        }
    }

    func testEditRefreshHrsChanged_updatesField() async {
        var state = SettingsFeature.State()
        state.editingPlaylist = makePlaylist()

        let store = TestStore(initialState: state) {
            SettingsFeature()
        }

        await store.send(.editRefreshHrsChanged(6)) {
            $0.editRefreshHrs = 6
        }
    }

    func testEditPlaylistSaved_updatesAndReloads() async {
        let playlist = makePlaylist(id: "pl-1", name: "Old Name")
        var state = SettingsFeature.State()
        state.playlists = [playlist]
        state.editingPlaylist = playlist
        state.editName = "New Name"
        state.editEpgURL = "http://example.com/epg.xml"
        state.editRefreshHrs = 12

        let updated = LockIsolated<PlaylistRecord?>(nil)
        let updatedPlaylist = makePlaylist(id: "pl-1", name: "New Name")

        let store = TestStore(initialState: state) {
            SettingsFeature()
        } withDependencies: {
            $0.playlistImportClient.updatePlaylist = { record in
                updated.setValue(record)
            }
            $0.vodListClient.fetchPlaylists = { [updatedPlaylist] }
        }
        store.exhaustivity = .off

        await store.send(.editPlaylistSaved) {
            $0.editingPlaylist = nil
        }

        await store.skipReceivedActions()

        XCTAssertEqual(updated.value?.name, "New Name")
        XCTAssertEqual(updated.value?.epgURL, "http://example.com/epg.xml")
        XCTAssertEqual(updated.value?.refreshHrs, 12)
    }

    func testEditPlaylistSaved_emptyName_noOp() async {
        let playlist = makePlaylist(id: "pl-1")
        var state = SettingsFeature.State()
        state.editingPlaylist = playlist
        state.editName = "   "

        let store = TestStore(initialState: state) {
            SettingsFeature()
        }

        await store.send(.editPlaylistSaved)
    }

    func testEditPlaylistCancelled_clearsState() async {
        var state = SettingsFeature.State()
        state.editingPlaylist = makePlaylist()
        state.editName = "Changed"

        let store = TestStore(initialState: state) {
            SettingsFeature()
        }

        await store.send(.editPlaylistCancelled) {
            $0.editingPlaylist = nil
        }
    }

    // MARK: - Clear Watch History

    func testClearHistoryTapped_showsConfirmation() async {
        let store = TestStore(initialState: SettingsFeature.State()) {
            SettingsFeature()
        }

        await store.send(.clearHistoryTapped) {
            $0.showClearHistoryConfirmation = true
        }
    }

    func testClearHistoryConfirmed_callsClearAll() async {
        var state = SettingsFeature.State()
        state.showClearHistoryConfirmation = true

        let cleared = LockIsolated(false)
        let store = TestStore(initialState: state) {
            SettingsFeature()
        } withDependencies: {
            $0.watchProgressClient.clearAll = {
                cleared.setValue(true)
            }
        }

        await store.send(.clearHistoryConfirmed) {
            $0.showClearHistoryConfirmation = false
        }
        await store.receive(\.historyCleared)
        XCTAssertTrue(cleared.value)
    }

    func testClearHistoryCancelled_hidesConfirmation() async {
        var state = SettingsFeature.State()
        state.showClearHistoryConfirmation = true

        let store = TestStore(initialState: state) {
            SettingsFeature()
        }

        await store.send(.clearHistoryCancelled) {
            $0.showClearHistoryConfirmation = false
        }
    }
}
