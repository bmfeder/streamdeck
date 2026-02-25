import XCTest
@testable import Repositories

final class KeychainHelperTests: XCTestCase {

    private let testPrefix = "test-keychain-\(UUID().uuidString)-"

    override func tearDown() {
        // Clean up any test keys
        for i in 0..<10 {
            KeychainHelper.delete(key: "\(testPrefix)\(i)")
        }
        KeychainHelper.delete(key: "\(testPrefix)main")
        KeychainHelper.delete(key: "\(testPrefix)empty")
        super.tearDown()
    }

    func testSave_andLoad_returnsValue() {
        let key = "\(testPrefix)main"
        let saved = KeychainHelper.save(key: key, value: "secret123")
        XCTAssertTrue(saved)

        let loaded = KeychainHelper.load(key: key)
        XCTAssertEqual(loaded, "secret123")
    }

    func testLoad_nonExistentKey_returnsNil() {
        let loaded = KeychainHelper.load(key: "\(testPrefix)nonexistent")
        XCTAssertNil(loaded)
    }

    func testSave_overwritesExistingKey() {
        let key = "\(testPrefix)main"
        KeychainHelper.save(key: key, value: "first")
        KeychainHelper.save(key: key, value: "second")

        let loaded = KeychainHelper.load(key: key)
        XCTAssertEqual(loaded, "second")
    }

    func testDelete_removesValue() {
        let key = "\(testPrefix)main"
        KeychainHelper.save(key: key, value: "todelete")

        let deleted = KeychainHelper.delete(key: key)
        XCTAssertTrue(deleted)

        let loaded = KeychainHelper.load(key: key)
        XCTAssertNil(loaded)
    }

    func testDelete_nonExistentKey_returnsTrue() {
        let deleted = KeychainHelper.delete(key: "\(testPrefix)nonexistent")
        XCTAssertTrue(deleted)
    }

    func testSave_emptyString_loadsEmpty() {
        let key = "\(testPrefix)empty"
        KeychainHelper.save(key: key, value: "")

        let loaded = KeychainHelper.load(key: key)
        XCTAssertEqual(loaded, "")
    }
}
