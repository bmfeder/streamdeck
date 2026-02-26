import ComposableArchitecture
import XCTest
@testable import AppFeature

@MainActor
final class UserPreferencesTests: XCTestCase {

    func testLoad_allDefaults_whenKeysUnset() {
        let client = UserDefaultsClient(
            boolForKey: { _ in false },
            setBool: { _, _ in },
            stringForKey: { _ in nil },
            setString: { _, _ in }
        )
        let prefs = UserPreferences.load(from: client)
        XCTAssertEqual(prefs.preferredEngine, .auto)
        XCTAssertTrue(prefs.resumePlaybackEnabled)
        XCTAssertEqual(prefs.bufferTimeoutSeconds, 10)
    }

    func testLoad_customValues() {
        let client = UserDefaultsClient(
            boolForKey: { _ in false },
            setBool: { _, _ in },
            stringForKey: { key in
                switch key {
                case UserDefaultsKey.preferredPlayerEngine: return "vlcKit"
                case UserDefaultsKey.resumePlaybackEnabled: return "false"
                case UserDefaultsKey.bufferTimeoutSeconds: return "20"
                default: return nil
                }
            },
            setString: { _, _ in }
        )
        let prefs = UserPreferences.load(from: client)
        XCTAssertEqual(prefs.preferredEngine, .vlcKit)
        XCTAssertFalse(prefs.resumePlaybackEnabled)
        XCTAssertEqual(prefs.bufferTimeoutSeconds, 20)
    }

    func testLoad_invalidEngine_fallsToAuto() {
        let client = UserDefaultsClient(
            boolForKey: { _ in false },
            setBool: { _, _ in },
            stringForKey: { key in
                if key == UserDefaultsKey.preferredPlayerEngine { return "garbage" }
                return nil
            },
            setString: { _, _ in }
        )
        let prefs = UserPreferences.load(from: client)
        XCTAssertEqual(prefs.preferredEngine, .auto)
    }

    func testLoad_invalidTimeout_fallsToDefault() {
        let client = UserDefaultsClient(
            boolForKey: { _ in false },
            setBool: { _, _ in },
            stringForKey: { key in
                if key == UserDefaultsKey.bufferTimeoutSeconds { return "abc" }
                return nil
            },
            setString: { _, _ in }
        )
        let prefs = UserPreferences.load(from: client)
        XCTAssertEqual(prefs.bufferTimeoutSeconds, 10)
    }

    func testSave_persistsAllValues() {
        let saved = LockIsolated<[String: String]>([:])
        let client = UserDefaultsClient(
            boolForKey: { _ in false },
            setBool: { _, _ in },
            stringForKey: { _ in nil },
            setString: { value, key in
                saved.withValue { $0[key] = value }
            }
        )
        let prefs = UserPreferences(
            preferredEngine: .avPlayer,
            resumePlaybackEnabled: false,
            bufferTimeoutSeconds: 15
        )
        prefs.save(to: client)

        XCTAssertEqual(saved.value[UserDefaultsKey.preferredPlayerEngine], "avPlayer")
        XCTAssertEqual(saved.value[UserDefaultsKey.resumePlaybackEnabled], "false")
        XCTAssertEqual(saved.value[UserDefaultsKey.bufferTimeoutSeconds], "15")
    }
}
