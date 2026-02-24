import XCTest
@testable import XtreamClient

final class XtreamDecodingTests: XCTestCase {

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - LenientInt
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    func testLenientInt_decodesFromInt() throws {
        let json = Data(#"{"value": 42}"#.utf8)
        let result = try JSONDecoder().decode(Wrapper<LenientInt>.self, from: json)
        XCTAssertEqual(result.value.value, 42)
    }

    func testLenientInt_decodesFromString() throws {
        let json = Data(#"{"value": "99"}"#.utf8)
        let result = try JSONDecoder().decode(Wrapper<LenientInt>.self, from: json)
        XCTAssertEqual(result.value.value, 99)
    }

    func testLenientInt_nonNumericString_defaultsToZero() throws {
        let json = Data(#"{"value": "abc"}"#.utf8)
        let result = try JSONDecoder().decode(Wrapper<LenientInt>.self, from: json)
        XCTAssertEqual(result.value.value, 0)
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - LenientOptionalInt
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    func testLenientOptionalInt_null_returnsNil() throws {
        let json = Data(#"{"value": null}"#.utf8)
        let result = try JSONDecoder().decode(Wrapper<LenientOptionalInt>.self, from: json)
        XCTAssertNil(result.value.value)
    }

    func testLenientOptionalInt_emptyString_returnsNil() throws {
        let json = Data(#"{"value": ""}"#.utf8)
        let result = try JSONDecoder().decode(Wrapper<LenientOptionalInt>.self, from: json)
        XCTAssertNil(result.value.value)
    }

    func testLenientOptionalInt_stringNumber_parsesCorrectly() throws {
        let json = Data(#"{"value": "1735689600"}"#.utf8)
        let result = try JSONDecoder().decode(Wrapper<LenientOptionalInt>.self, from: json)
        XCTAssertEqual(result.value.value, 1735689600)
    }

    func testLenientOptionalInt_intValue_parsesCorrectly() throws {
        let json = Data(#"{"value": 1735689600}"#.utf8)
        let result = try JSONDecoder().decode(Wrapper<LenientOptionalInt>.self, from: json)
        XCTAssertEqual(result.value.value, 1735689600)
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - LenientOptionalDouble
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    func testLenientOptionalDouble_stringRating() throws {
        let json = Data(#"{"value": "8.7"}"#.utf8)
        let result = try JSONDecoder().decode(Wrapper<LenientOptionalDouble>.self, from: json)
        let unwrapped = try XCTUnwrap(result.value.value)
        XCTAssertEqual(unwrapped, 8.7, accuracy: 0.01)
    }

    func testLenientOptionalDouble_numericRating() throws {
        let json = Data(#"{"value": 8.8}"#.utf8)
        let result = try JSONDecoder().decode(Wrapper<LenientOptionalDouble>.self, from: json)
        let unwrapped = try XCTUnwrap(result.value.value)
        XCTAssertEqual(unwrapped, 8.8, accuracy: 0.01)
    }

    func testLenientOptionalDouble_emptyString_returnsNil() throws {
        let json = Data(#"{"value": ""}"#.utf8)
        let result = try JSONDecoder().decode(Wrapper<LenientOptionalDouble>.self, from: json)
        XCTAssertNil(result.value.value)
    }

    func testLenientOptionalDouble_null_returnsNil() throws {
        let json = Data(#"{"value": null}"#.utf8)
        let result = try JSONDecoder().decode(Wrapper<LenientOptionalDouble>.self, from: json)
        XCTAssertNil(result.value.value)
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - LenientString
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    func testLenientString_decodesFromString() throws {
        let json = Data(#"{"value": "8080"}"#.utf8)
        let result = try JSONDecoder().decode(Wrapper<LenientString>.self, from: json)
        XCTAssertEqual(result.value.value, "8080")
    }

    func testLenientString_decodesFromInt() throws {
        let json = Data(#"{"value": 8080}"#.utf8)
        let result = try JSONDecoder().decode(Wrapper<LenientString>.self, from: json)
        XCTAssertEqual(result.value.value, "8080")
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - LenientStringOrArray
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    func testLenientStringOrArray_array() throws {
        let json = Data(#"{"value": ["url1", "url2"]}"#.utf8)
        let result = try JSONDecoder().decode(Wrapper<LenientStringOrArray>.self, from: json)
        XCTAssertEqual(result.value.values, ["url1", "url2"])
    }

    func testLenientStringOrArray_singleString() throws {
        let json = Data(#"{"value": "url1"}"#.utf8)
        let result = try JSONDecoder().decode(Wrapper<LenientStringOrArray>.self, from: json)
        XCTAssertEqual(result.value.values, ["url1"])
    }

    func testLenientStringOrArray_emptyString_returnsEmpty() throws {
        let json = Data(#"{"value": ""}"#.utf8)
        let result = try JSONDecoder().decode(Wrapper<LenientStringOrArray>.self, from: json)
        XCTAssertTrue(result.value.values.isEmpty)
    }

    func testLenientStringOrArray_null_returnsEmpty() throws {
        let json = Data(#"{"value": null}"#.utf8)
        let result = try JSONDecoder().decode(Wrapper<LenientStringOrArray?>.self, from: json)
        XCTAssertNil(result.value)
    }

    func testLenientStringOrArray_filtersEmptyStrings() throws {
        let json = Data(#"{"value": ["url1", "", "url2"]}"#.utf8)
        let result = try JSONDecoder().decode(Wrapper<LenientStringOrArray>.self, from: json)
        XCTAssertEqual(result.value.values, ["url1", "url2"])
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - EPG Base64 Decoding
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    func testEPGListing_base64Decoding() async throws {
        let mockHTTP = MockHTTPClient()
        let creds = XtreamCredentials(
            serverURL: URL(string: "http://provider.example.com:8080")!,
            username: "testuser",
            password: "testpass"
        )
        let client = XtreamClient(credentials: creds, httpClient: mockHTTP)
        mockHTTP.enqueue(for: "get_short_epg", json: XtreamFixtures.shortEPG)

        let listings = try await client.getShortEPG(streamId: "1001")

        XCTAssertEqual(listings.count, 2)
        XCTAssertEqual(listings[0].decodedTitle, "Morning News")
        XCTAssertEqual(listings[0].decodedDescription, "Your daily morning news update.")
        XCTAssertEqual(listings[1].decodedTitle, "Sports Center")
    }
}

// MARK: - Test Helper

private struct Wrapper<T: Decodable>: Decodable {
    let value: T
}
