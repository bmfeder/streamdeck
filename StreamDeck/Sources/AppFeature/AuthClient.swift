import ComposableArchitecture
import Foundation
import Supabase
import SyncDatabase

// MARK: - Types

/// Lightweight wrapper around Supabase session info.
/// Avoids leaking Supabase types into feature reducers.
public struct AuthSession: Equatable, Sendable {
    public let userID: String
    public let email: String?
    public let accessToken: String

    public init(userID: String, email: String?, accessToken: String) {
        self.userID = userID
        self.email = email
        self.accessToken = accessToken
    }
}

/// Auth state change events.
public enum AuthEvent: Equatable, Sendable {
    case signedIn(AuthSession)
    case signedOut
    case tokenRefreshed(AuthSession)
    case initialSession(AuthSession?)
}

/// Auth-specific errors.
public enum AuthError: Error, Equatable {
    case invalidToken
    case noSession
}

// MARK: - TCA Dependency

/// TCA dependency client for Supabase authentication.
/// Wraps supabase-swift auth for use in reducers.
public struct AuthClient: Sendable {

    /// Sign in with Apple ID token and nonce.
    public var signInWithApple: @Sendable (_ identityToken: Data, _ nonce: String) async throws -> AuthSession

    /// Sign out the current user.
    public var signOut: @Sendable () async throws -> Void

    /// Get the current session, if any.
    public var currentSession: @Sendable () async -> AuthSession?

    /// Stream of auth state changes.
    public var onAuthStateChange: @Sendable () -> AsyncStream<AuthEvent>
}

// MARK: - Dependency Registration

extension AuthClient: DependencyKey {

    /// Shared Supabase client. Both AuthClient and SupabasePowerSyncConnector use this.
    private static let _supabaseClient = LockIsolated<SupabaseClient?>(nil)

    /// Access the shared SupabaseClient instance. Creates on first access using SyncConfig.
    public static var supabaseClient: SupabaseClient {
        _supabaseClient.withValue { client in
            if let c = client { return c }
            guard let config = SyncConfig.fromInfoPlist(),
                  let url = URL(string: config.supabaseURL) else {
                fatalError("SyncConfig missing or invalid — set SUPABASE_URL, SUPABASE_ANON_KEY, POWERSYNC_URL in Info.plist")
            }
            let c = SupabaseClient(supabaseURL: url, supabaseKey: config.supabaseAnonKey)
            client = c
            return c
        }
    }

    public static var liveValue: AuthClient {
        AuthClient(
            signInWithApple: { identityToken, nonce in
                guard let tokenString = String(data: identityToken, encoding: .utf8) else {
                    throw AuthError.invalidToken
                }
                let session = try await supabaseClient.auth.signInWithIdToken(
                    credentials: OpenIDConnectCredentials(
                        provider: .apple,
                        idToken: tokenString,
                        nonce: nonce
                    )
                )
                return AuthSession(
                    userID: session.user.id.uuidString,
                    email: session.user.email,
                    accessToken: session.accessToken
                )
            },
            signOut: {
                try await supabaseClient.auth.signOut()
            },
            currentSession: {
                guard let session = supabaseClient.auth.currentSession else { return nil }
                return AuthSession(
                    userID: session.user.id.uuidString,
                    email: session.user.email,
                    accessToken: session.accessToken
                )
            },
            onAuthStateChange: {
                let stream = supabaseClient.auth.authStateChanges
                return AsyncStream { continuation in
                    let task = Task {
                        for await (event, session) in stream {
                            let authSession = session.map {
                                AuthSession(
                                    userID: $0.user.id.uuidString,
                                    email: $0.user.email,
                                    accessToken: $0.accessToken
                                )
                            }
                            switch event {
                            case .signedIn:
                                continuation.yield(.signedIn(
                                    authSession ?? AuthSession(userID: "", email: nil, accessToken: "")
                                ))
                            case .signedOut:
                                continuation.yield(.signedOut)
                            case .tokenRefreshed:
                                continuation.yield(.tokenRefreshed(
                                    authSession ?? AuthSession(userID: "", email: nil, accessToken: "")
                                ))
                            case .initialSession:
                                continuation.yield(.initialSession(authSession))
                            default:
                                continue
                            }
                        }
                        continuation.finish()
                    }
                    continuation.onTermination = { _ in task.cancel() }
                }
            }
        )
    }

    public static var testValue: AuthClient {
        AuthClient(
            signInWithApple: unimplemented("AuthClient.signInWithApple"),
            signOut: unimplemented("AuthClient.signOut"),
            currentSession: { nil },
            onAuthStateChange: { AsyncStream { $0.finish() } }
        )
    }
}

extension DependencyValues {
    public var authClient: AuthClient {
        get { self[AuthClient.self] }
        set { self[AuthClient.self] = newValue }
    }
}
