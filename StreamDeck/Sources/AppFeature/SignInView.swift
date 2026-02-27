import AuthenticationServices
import ComposableArchitecture
import SwiftUI

// MARK: - Sign In Feature

@Reducer
public struct SignInFeature {
    @ObservableState
    public struct State: Equatable, Sendable {
        public var isSigningIn: Bool = false
        public var errorMessage: String?

        public init() {}
    }

    public enum Action: Sendable {
        case signInWithAppleTapped
        case appleCredentialReceived(userID: String, identityToken: Data, nonce: String)
        case appleSignInFailed(String)
        case signInCompleted(Result<AuthSession, Error>)
        case delegate(Delegate)

        @CasePathable
        public enum Delegate: Sendable, Equatable {
            case authenticated(AuthSession)
        }
    }

    @Dependency(\.authClient) var authClient

    public init() {}

    public var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .signInWithAppleTapped:
                state.isSigningIn = true
                state.errorMessage = nil
                return .none

            case let .appleCredentialReceived(_, identityToken, nonce):
                state.isSigningIn = true
                let client = authClient
                return .run { send in
                    let session = try await client.signInWithApple(identityToken, nonce)
                    await send(.signInCompleted(.success(session)))
                } catch: { error, send in
                    await send(.signInCompleted(.failure(error)))
                }

            case let .appleSignInFailed(message):
                state.isSigningIn = false
                state.errorMessage = message
                return .none

            case let .signInCompleted(.success(session)):
                state.isSigningIn = false
                state.errorMessage = nil
                return .send(.delegate(.authenticated(session)))

            case let .signInCompleted(.failure(error)):
                state.isSigningIn = false
                state.errorMessage = error.localizedDescription
                return .none

            case .delegate:
                return .none
            }
        }
    }
}

// MARK: - View

public struct SignInView: View {
    let store: StoreOf<SignInFeature>
    @State private var currentNonce: String?

    public init(store: StoreOf<SignInFeature>) {
        self.store = store
    }

    public var body: some View {
        VStack(spacing: 32) {
            Spacer()

            Image(systemName: "play.tv")
                .font(.system(size: 80))
                .foregroundStyle(.tint)

            Text("StreamDeck")
                .font(.largeTitle)
                .fontWeight(.bold)

            Text("Sign in to sync your playlists, favorites, and watch progress across all your devices.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 500)

            if store.isSigningIn {
                ProgressView("Signing in...")
            } else {
                signInButton
            }

            if let error = store.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 400)
            }

            Spacer()
        }
        .padding()
    }

    private var signInButton: some View {
        #if os(tvOS) || os(iOS)
        SignInWithAppleButton(.signIn) { request in
            let nonce = randomNonceString()
            currentNonce = nonce
            request.requestedScopes = [.email]
            request.nonce = sha256(nonce)
        } onCompletion: { result in
            switch result {
            case let .success(authorization):
                guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                      let identityToken = credential.identityToken,
                      let nonce = currentNonce else {
                    store.send(.appleSignInFailed("Failed to get Apple ID credential"))
                    return
                }
                store.send(.appleCredentialReceived(
                    userID: credential.user,
                    identityToken: identityToken,
                    nonce: nonce
                ))
            case let .failure(error):
                if (error as? ASAuthorizationError)?.code == .canceled {
                    return // User cancelled, no error
                }
                store.send(.appleSignInFailed(error.localizedDescription))
            }
        }
        .signInWithAppleButtonStyle(.white)
        #if os(tvOS)
        .frame(width: 400, height: 60)
        #else
        .frame(width: 280, height: 44)
        #endif
        #else
        Button("Sign In with Apple") {
            store.send(.signInWithAppleTapped)
        }
        .buttonStyle(.borderedProminent)
        #endif
    }
}

// MARK: - Crypto Helpers

import CryptoKit

/// Generate a random nonce string for Sign In with Apple.
private func randomNonceString(length: Int = 32) -> String {
    precondition(length > 0)
    var randomBytes = [UInt8](repeating: 0, count: length)
    let errorCode = SecRandomCopyBytes(kSecRandomDefault, randomBytes.count, &randomBytes)
    if errorCode != errSecSuccess {
        fatalError("Unable to generate nonce. SecRandomCopyBytes failed with OSStatus \(errorCode)")
    }
    let charset: [Character] = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
    return String(randomBytes.map { charset[Int($0) % charset.count] })
}

/// SHA256 hash of the nonce for Apple's anti-replay protection.
private func sha256(_ input: String) -> String {
    let inputData = Data(input.utf8)
    let hashed = SHA256.hash(data: inputData)
    return hashed.compactMap { String(format: "%02x", $0) }.joined()
}
