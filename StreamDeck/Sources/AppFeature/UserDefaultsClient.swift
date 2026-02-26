import ComposableArchitecture
import Foundation

public struct UserDefaultsClient: Sendable {
    public var boolForKey: @Sendable (String) -> Bool
    public var setBool: @Sendable (Bool, String) -> Void
    public var stringForKey: @Sendable (String) -> String?
    public var setString: @Sendable (String, String) -> Void
}

extension UserDefaultsClient: DependencyKey {
    public static let liveValue = UserDefaultsClient(
        boolForKey: { key in
            UserDefaults.standard.bool(forKey: key)
        },
        setBool: { value, key in
            UserDefaults.standard.set(value, forKey: key)
        },
        stringForKey: { key in
            UserDefaults.standard.string(forKey: key)
        },
        setString: { value, key in
            UserDefaults.standard.set(value, forKey: key)
        }
    )

    public static let testValue = UserDefaultsClient(
        boolForKey: unimplemented("UserDefaultsClient.boolForKey"),
        setBool: unimplemented("UserDefaultsClient.setBool"),
        stringForKey: { _ in nil },
        setString: unimplemented("UserDefaultsClient.setString")
    )
}

extension DependencyValues {
    public var userDefaultsClient: UserDefaultsClient {
        get { self[UserDefaultsClient.self] }
        set { self[UserDefaultsClient.self] = newValue }
    }
}

// MARK: - Keys

public enum UserDefaultsKey {
    public static let hasAcceptedDisclaimer = "hasAcceptedDisclaimer"
    public static let preferredPlayerEngine = "preferredPlayerEngine"
    public static let resumePlaybackEnabled = "resumePlaybackEnabled"
    public static let bufferTimeoutSeconds = "bufferTimeoutSeconds"
}
