import ComposableArchitecture
import Foundation

public struct UserDefaultsClient: Sendable {
    public var boolForKey: @Sendable (String) -> Bool
    public var setBool: @Sendable (Bool, String) -> Void
}

extension UserDefaultsClient: DependencyKey {
    public static let liveValue = UserDefaultsClient(
        boolForKey: { key in
            UserDefaults.standard.bool(forKey: key)
        },
        setBool: { value, key in
            UserDefaults.standard.set(value, forKey: key)
        }
    )

    public static let testValue = UserDefaultsClient(
        boolForKey: unimplemented("UserDefaultsClient.boolForKey"),
        setBool: unimplemented("UserDefaultsClient.setBool")
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
}
