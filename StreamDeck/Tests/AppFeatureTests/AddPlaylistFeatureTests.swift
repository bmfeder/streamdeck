import ComposableArchitecture
import XCTest
import Repositories
import Database
@testable import AppFeature

@MainActor
final class AddPlaylistFeatureTests: XCTestCase {

    // MARK: - Initial State

    func testInitialState_defaultsToM3U() {
        let state = AddPlaylistFeature.State()
        XCTAssertEqual(state.sourceType, .m3u)
        XCTAssertTrue(state.m3uURL.isEmpty)
        XCTAssertFalse(state.isValidating)
        XCTAssertNil(state.errorMessage)
    }

    func testInitialState_xtreamWhenSpecified() {
        let state = AddPlaylistFeature.State(sourceType: .xtream)
        XCTAssertEqual(state.sourceType, .xtream)
    }

    // MARK: - Source Type Change

    func testSourceTypeChanged_resetsError() async {
        let store = TestStore(
            initialState: AddPlaylistFeature.State()
        ) {
            AddPlaylistFeature()
        }
        store.exhaustivity = .off
        await store.send(.validationResponse(.failure(PlaylistImportError.emptyPlaylist))) {
            $0.errorMessage = "The playlist contains no channels."
        }
        await store.send(.sourceTypeChanged(.xtream)) {
            $0.sourceType = .xtream
            $0.errorMessage = nil
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

    // MARK: - Validation Flow (M3U)

    func testAddButtonTapped_m3u_validatesAndDelegates() async {
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
            $0.playlistImportClient.validateM3U = { _ in }
            $0.dismiss = DismissEffect { }
        }

        await store.send(.addButtonTapped) {
            $0.isValidating = true
            $0.errorMessage = nil
        }

        await store.receive(\.validationResponse) {
            $0.isValidating = false
        }

        await store.receive(\.delegate.validationSucceeded)
    }

    // MARK: - Validation Flow (Xtream)

    func testAddButtonTapped_xtream_validatesAndDelegates() async {
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
            $0.playlistImportClient.validateXtream = { _, _, _ in }
            $0.dismiss = DismissEffect { }
        }

        await store.send(.addButtonTapped) {
            $0.isValidating = true
            $0.errorMessage = nil
        }

        await store.receive(\.validationResponse) {
            $0.isValidating = false
        }

        await store.receive(\.delegate.validationSucceeded)
    }

    // MARK: - Validation Failure

    func testValidationResponse_failure_setsErrorMessage() async {
        let store = TestStore(
            initialState: {
                var state = AddPlaylistFeature.State()
                state.m3uURL = "http://example.com/pl.m3u"
                state.isValidating = true
                return state
            }()
        ) {
            AddPlaylistFeature()
        }

        await store.send(.validationResponse(.failure(PlaylistImportError.emptyPlaylist))) {
            $0.isValidating = false
            $0.errorMessage = "The playlist contains no channels."
        }
    }

    func testValidationResponse_authFailure() async {
        let store = TestStore(
            initialState: {
                var state = AddPlaylistFeature.State(sourceType: .xtream)
                state.isValidating = true
                return state
            }()
        ) {
            AddPlaylistFeature()
        }

        await store.send(.validationResponse(.failure(PlaylistImportError.authenticationFailed))) {
            $0.isValidating = false
            $0.errorMessage = "Authentication failed. Check your username and password."
        }
    }

    // MARK: - No Double Submit

    func testAddButtonTapped_whenAlreadyValidating_noOp() async {
        let store = TestStore(
            initialState: {
                var state = AddPlaylistFeature.State()
                state.m3uURL = "http://example.com/pl.m3u"
                state.isValidating = true
                return state
            }()
        ) {
            AddPlaylistFeature()
        }

        await store.send(.addButtonTapped)
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

    // MARK: - Emby

    func testInitialState_embyWhenSpecified() {
        let state = AddPlaylistFeature.State(sourceType: .emby)
        XCTAssertEqual(state.sourceType, .emby)
    }

    func testIsFormValid_emby_allFieldsFilled_true() {
        var state = AddPlaylistFeature.State(sourceType: .emby)
        state.embyServerURL = "http://emby.local:8096"
        state.embyUsername = "user"
        state.embyPassword = "pass"
        XCTAssertTrue(state.isFormValid)
    }

    func testIsFormValid_emby_missingServerURL_false() {
        var state = AddPlaylistFeature.State(sourceType: .emby)
        state.embyUsername = "user"
        state.embyPassword = "pass"
        XCTAssertFalse(state.isFormValid)
    }

    func testIsFormValid_emby_missingUsername_false() {
        var state = AddPlaylistFeature.State(sourceType: .emby)
        state.embyServerURL = "http://emby.local:8096"
        state.embyPassword = "pass"
        XCTAssertFalse(state.isFormValid)
    }

    func testIsFormValid_emby_missingPassword_false() {
        var state = AddPlaylistFeature.State(sourceType: .emby)
        state.embyServerURL = "http://emby.local:8096"
        state.embyUsername = "user"
        XCTAssertFalse(state.isFormValid)
    }

    func testEmbyServerURLChanged_autoFillsName() async {
        let store = TestStore(
            initialState: AddPlaylistFeature.State(sourceType: .emby)
        ) {
            AddPlaylistFeature()
        }
        await store.send(.embyServerURLChanged("http://emby.local:8096")) {
            $0.embyServerURL = "http://emby.local:8096"
            $0.embyName = "emby.local"
        }
    }

    func testAddButtonTapped_emby_validatesAndDelegates() async {
        let store = TestStore(
            initialState: {
                var state = AddPlaylistFeature.State(sourceType: .emby)
                state.embyServerURL = "http://emby.local:8096"
                state.embyUsername = "user"
                state.embyPassword = "pass"
                state.embyName = "My Emby"
                return state
            }()
        ) {
            AddPlaylistFeature()
        } withDependencies: {
            $0.playlistImportClient.validateEmby = { _, _, _ in }
            $0.dismiss = DismissEffect { }
        }

        await store.send(.addButtonTapped) {
            $0.isValidating = true
            $0.errorMessage = nil
        }

        await store.receive(\.validationResponse) {
            $0.isValidating = false
        }

        await store.receive(\.delegate.validationSucceeded)
    }

    func testValidationResponse_embyAuthFailure() async {
        let store = TestStore(
            initialState: {
                var state = AddPlaylistFeature.State(sourceType: .emby)
                state.isValidating = true
                return state
            }()
        ) {
            AddPlaylistFeature()
        }

        await store.send(.validationResponse(.failure(PlaylistImportError.authenticationFailed))) {
            $0.isValidating = false
            $0.errorMessage = "Authentication failed. Check your username and password."
        }
    }
}
