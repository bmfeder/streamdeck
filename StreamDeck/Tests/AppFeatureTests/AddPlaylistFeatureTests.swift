import ComposableArchitecture
import XCTest
import Repositories
import Database
@testable import AppFeature

@MainActor
final class AddPlaylistFeatureTests: XCTestCase {

    // MARK: - Helpers

    private func makePlaylistImportResult(
        playlistID: String = "pl-1",
        name: String = "Test Playlist",
        added: Int = 10,
        parseErrors: [String] = []
    ) -> PlaylistImportResult {
        PlaylistImportResult(
            playlist: PlaylistRecord(
                id: playlistID,
                name: name,
                type: "m3u",
                url: "http://example.com/pl.m3u"
            ),
            importResult: ImportResult(added: added, updated: 0, softDeleted: 0, unchanged: 0),
            parseErrors: parseErrors
        )
    }

    // MARK: - Initial State

    func testInitialState_defaultsToM3U() {
        let state = AddPlaylistFeature.State()
        XCTAssertEqual(state.sourceType, .m3u)
        XCTAssertTrue(state.m3uURL.isEmpty)
        XCTAssertFalse(state.isImporting)
        XCTAssertNil(state.importResult)
        XCTAssertNil(state.errorMessage)
    }

    func testInitialState_xtreamWhenSpecified() {
        let state = AddPlaylistFeature.State(sourceType: .xtream)
        XCTAssertEqual(state.sourceType, .xtream)
    }

    // MARK: - Source Type Change

    func testSourceTypeChanged_resetsErrorAndResult() async {
        let store = TestStore(
            initialState: AddPlaylistFeature.State()
        ) {
            AddPlaylistFeature()
        }
        // Set error and result manually
        store.exhaustivity = .off
        await store.send(.importResponse(.failure(PlaylistImportError.emptyPlaylist))) {
            $0.errorMessage = "The playlist contains no channels."
        }
        await store.send(.sourceTypeChanged(.xtream)) {
            $0.sourceType = .xtream
            $0.errorMessage = nil
            $0.importResult = nil
        }
    }

    // MARK: - Form Auto-Fill

    func testM3uURLChanged_autoFillsNameFromHost() async {
        let store = TestStore(
            initialState: AddPlaylistFeature.State()
        ) {
            AddPlaylistFeature()
        }
        await store.send(.m3uURLChanged("http://provider.example.com/playlist.m3u")) {
            $0.m3uURL = "http://provider.example.com/playlist.m3u"
            $0.m3uName = "provider.example.com"
        }
    }

    func testXtreamServerURLChanged_autoFillsNameFromHost() async {
        let store = TestStore(
            initialState: AddPlaylistFeature.State(sourceType: .xtream)
        ) {
            AddPlaylistFeature()
        }
        await store.send(.xtreamServerURLChanged("http://xtream.example.com:8080")) {
            $0.xtreamServerURL = "http://xtream.example.com:8080"
            $0.xtreamName = "xtream.example.com"
        }
    }

    // MARK: - Form Validation

    func testIsFormValid_m3u_emptyURL_false() {
        let state = AddPlaylistFeature.State()
        XCTAssertFalse(state.isFormValid)
    }

    func testIsFormValid_m3u_validURL_true() {
        var state = AddPlaylistFeature.State()
        state.m3uURL = "http://example.com/playlist.m3u"
        XCTAssertTrue(state.isFormValid)
    }

    func testIsFormValid_m3u_invalidURL_false() {
        var state = AddPlaylistFeature.State()
        state.m3uURL = "not a url with spaces"
        XCTAssertFalse(state.isFormValid)
    }

    func testIsFormValid_xtream_allFieldsFilled_true() {
        var state = AddPlaylistFeature.State(sourceType: .xtream)
        state.xtreamServerURL = "http://server.com"
        state.xtreamUsername = "user"
        state.xtreamPassword = "pass"
        XCTAssertTrue(state.isFormValid)
    }

    func testIsFormValid_xtream_missingUsername_false() {
        var state = AddPlaylistFeature.State(sourceType: .xtream)
        state.xtreamServerURL = "http://server.com"
        state.xtreamPassword = "pass"
        XCTAssertFalse(state.isFormValid)
    }

    func testIsFormValid_xtream_missingPassword_false() {
        var state = AddPlaylistFeature.State(sourceType: .xtream)
        state.xtreamServerURL = "http://server.com"
        state.xtreamUsername = "user"
        XCTAssertFalse(state.isFormValid)
    }

    // MARK: - Import Flow (M3U)

    func testImportButtonTapped_m3u_setsLoadingAndImports() async {
        let importResult = makePlaylistImportResult()

        let store = TestStore(
            initialState: {
                var state = AddPlaylistFeature.State()
                state.m3uURL = "http://example.com/pl.m3u"
                state.m3uName = "My Playlist"
                return state
            }()
        ) {
            AddPlaylistFeature()
        } withDependencies: {
            $0.playlistImportClient.importM3U = { _, _, _ in importResult }
        }

        await store.send(.importButtonTapped) {
            $0.isImporting = true
            $0.errorMessage = nil
            $0.importResult = nil
        }

        await store.receive(\.importResponse.success) {
            $0.isImporting = false
            $0.importResult = AddPlaylistFeature.ImportResultState(
                playlistName: "Test Playlist",
                channelsAdded: 10,
                parseWarnings: 0
            )
        }

        await store.receive(\.delegate.importCompleted)
    }

    // MARK: - Import Flow (Xtream)

    func testImportButtonTapped_xtream_setsLoadingAndImports() async {
        let importResult = makePlaylistImportResult(name: "Xtream Server")

        let store = TestStore(
            initialState: {
                var state = AddPlaylistFeature.State(sourceType: .xtream)
                state.xtreamServerURL = "http://server.com"
                state.xtreamUsername = "user"
                state.xtreamPassword = "pass"
                state.xtreamName = "Xtream Server"
                return state
            }()
        ) {
            AddPlaylistFeature()
        } withDependencies: {
            $0.playlistImportClient.importXtream = { _, _, _, _ in importResult }
        }

        await store.send(.importButtonTapped) {
            $0.isImporting = true
            $0.errorMessage = nil
            $0.importResult = nil
        }

        await store.receive(\.importResponse.success) {
            $0.isImporting = false
            $0.importResult = AddPlaylistFeature.ImportResultState(
                playlistName: "Xtream Server",
                channelsAdded: 10,
                parseWarnings: 0
            )
        }

        await store.receive(\.delegate.importCompleted)
    }

    // MARK: - Import Failure

    func testImportResponse_failure_setsErrorMessage() async {
        let store = TestStore(
            initialState: {
                var state = AddPlaylistFeature.State()
                state.m3uURL = "http://example.com/pl.m3u"
                state.isImporting = true
                return state
            }()
        ) {
            AddPlaylistFeature()
        }

        await store.send(.importResponse(.failure(PlaylistImportError.emptyPlaylist))) {
            $0.isImporting = false
            $0.errorMessage = "The playlist contains no channels."
        }
    }

    func testImportResponse_authFailure() async {
        let store = TestStore(
            initialState: {
                var state = AddPlaylistFeature.State(sourceType: .xtream)
                state.isImporting = true
                return state
            }()
        ) {
            AddPlaylistFeature()
        }

        await store.send(.importResponse(.failure(PlaylistImportError.authenticationFailed))) {
            $0.isImporting = false
            $0.errorMessage = "Authentication failed. Check your username and password."
        }
    }

    // MARK: - No Double Submit

    func testImportButtonTapped_whenAlreadyImporting_noOp() async {
        let store = TestStore(
            initialState: {
                var state = AddPlaylistFeature.State()
                state.m3uURL = "http://example.com/pl.m3u"
                state.isImporting = true
                return state
            }()
        ) {
            AddPlaylistFeature()
        }

        await store.send(.importButtonTapped)
        // No state change, no effect fired
    }

    // MARK: - Dismiss

    func testDismissErrorTapped_clearsError() async {
        let store = TestStore(
            initialState: {
                var state = AddPlaylistFeature.State()
                state.errorMessage = "Some error"
                return state
            }()
        ) {
            AddPlaylistFeature()
        }

        await store.send(.dismissErrorTapped) {
            $0.errorMessage = nil
        }
    }
}
