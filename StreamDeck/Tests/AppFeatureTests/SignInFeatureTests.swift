import ComposableArchitecture
import XCTest
@testable import AppFeature

@MainActor
final class SignInFeatureTests: XCTestCase {

    // MARK: - Helpers

    private let testSession = AuthSession(
        userID: "user-123",
        email: "test@example.com",
        accessToken: "test-token"
    )

    // MARK: - Initial State

    func testInitialState() {
        let state = SignInFeature.State()
        XCTAssertFalse(state.isSigningIn)
        XCTAssertNil(state.errorMessage)
    }

    // MARK: - Sign In With Apple Tapped

    func testSignInWithAppleTapped_setsLoading() async {
        let store = TestStore(initialState: SignInFeature.State()) {
            SignInFeature()
        }

        await store.send(.signInWithAppleTapped) {
            $0.isSigningIn = true
        }
    }

    func testSignInWithAppleTapped_clearsError() async {
        var state = SignInFeature.State()
        state.errorMessage = "Previous error"

        let store = TestStore(initialState: state) {
            SignInFeature()
        }

        await store.send(.signInWithAppleTapped) {
            $0.isSigningIn = true
            $0.errorMessage = nil
        }
    }

    // MARK: - Apple Credential Received

    func testAppleCredentialReceived_success_sendsDelegate() async {
        let session = testSession
        let store = TestStore(initialState: SignInFeature.State()) {
            SignInFeature()
        } withDependencies: {
            $0.authClient.signInWithApple = { _, _ in session }
        }

        await store.send(.appleCredentialReceived(
            userID: "apple-user",
            identityToken: Data("test-token".utf8),
            nonce: "test-nonce"
        )) {
            $0.isSigningIn = true
        }

        await store.receive(\.signInCompleted.success) {
            $0.isSigningIn = false
        }

        await store.receive(\.delegate.authenticated)
    }

    func testAppleCredentialReceived_failure_setsError() async {
        let store = TestStore(initialState: SignInFeature.State()) {
            SignInFeature()
        } withDependencies: {
            $0.authClient.signInWithApple = { _, _ in
                throw AuthError.invalidToken
            }
        }

        await store.send(.appleCredentialReceived(
            userID: "apple-user",
            identityToken: Data("bad-token".utf8),
            nonce: "test-nonce"
        )) {
            $0.isSigningIn = true
        }

        await store.receive(\.signInCompleted.failure) {
            $0.isSigningIn = false
            $0.errorMessage = AuthError.invalidToken.localizedDescription
        }
    }

    // MARK: - Apple Sign In Failed

    func testAppleSignInFailed_setsErrorAndStopsLoading() async {
        var state = SignInFeature.State()
        state.isSigningIn = true

        let store = TestStore(initialState: state) {
            SignInFeature()
        }

        await store.send(.appleSignInFailed("User cancelled")) {
            $0.isSigningIn = false
            $0.errorMessage = "User cancelled"
        }
    }

    // MARK: - Sign In Completed

    func testSignInCompleted_success_delegatesAuthenticated() async {
        var state = SignInFeature.State()
        state.isSigningIn = true

        let store = TestStore(initialState: state) {
            SignInFeature()
        }

        await store.send(.signInCompleted(.success(testSession))) {
            $0.isSigningIn = false
            $0.errorMessage = nil
        }

        await store.receive(\.delegate.authenticated)
    }

    func testSignInCompleted_failure_setsError() async {
        var state = SignInFeature.State()
        state.isSigningIn = true

        let store = TestStore(initialState: state) {
            SignInFeature()
        }

        let error = NSError(domain: "test", code: 1, userInfo: [NSLocalizedDescriptionKey: "Network error"])
        await store.send(.signInCompleted(.failure(error))) {
            $0.isSigningIn = false
            $0.errorMessage = "Network error"
        }
    }
}
