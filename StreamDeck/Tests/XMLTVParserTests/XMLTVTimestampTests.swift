import XCTest
@testable import XMLTVParser

final class XMLTVTimestampTests: XCTestCase {

    // MARK: - Standard Timestamps

    func testStandardTimestamp_withUTCOffset_correctEpoch() {
        // 2024-03-01 12:00:00 UTC = 1709294400
        let result = XMLTVTimestamp.parse("20240301120000 +0000")
        XCTAssertEqual(result, 1709294400)
    }

    func testTimestamp_2024NewYear_correctEpoch() {
        // 2024-01-01 00:00:00 UTC = 1704067200
        let result = XMLTVTimestamp.parse("20240101000000 +0000")
        XCTAssertEqual(result, 1704067200)
    }

    func testTimestamp_unixEpoch() {
        // 1970-01-01 00:00:00 UTC = 0
        let result = XMLTVTimestamp.parse("19700101000000 +0000")
        XCTAssertEqual(result, 0)
    }

    // MARK: - Timezone Offsets

    func testTimestamp_positiveOffset_convertedToUTC() {
        // 20240301120000 +0100 means 12:00 local = 11:00 UTC
        // 2024-03-01 11:00:00 UTC = 1709290800
        let result = XMLTVTimestamp.parse("20240301120000 +0100")
        XCTAssertEqual(result, 1709290800)
    }

    func testTimestamp_negativeOffset_convertedToUTC() {
        // 20240301120000 -0500 means 12:00 local = 17:00 UTC
        // 2024-03-01 17:00:00 UTC = 1709312400
        let result = XMLTVTimestamp.parse("20240301120000 -0500")
        XCTAssertEqual(result, 1709312400)
    }

    func testTimestamp_halfHourOffset_convertedToUTC() {
        // 20240301120000 +0530 means 12:00 IST = 06:30 UTC
        // 2024-03-01 06:30:00 UTC = 1709274600
        let result = XMLTVTimestamp.parse("20240301120000 +0530")
        XCTAssertEqual(result, 1709274600)
    }

    func testTimestamp_noSpaceBeforeOffset_stillParses() {
        // Same as +0000 but no space separator
        let result = XMLTVTimestamp.parse("20240301120000+0000")
        XCTAssertEqual(result, 1709294400)
    }

    // MARK: - No Offset (Assume UTC)

    func testTimestamp_noOffset_treatedAsUTC() {
        let result = XMLTVTimestamp.parse("20240301120000")
        XCTAssertEqual(result, 1709294400)
    }

    // MARK: - Truncated Timestamps

    func testTimestamp_hoursOnly_zeroFillsMinutesSeconds() {
        // 2024030112 -> 2024-03-01 12:00:00 UTC
        let result = XMLTVTimestamp.parse("2024030112")
        XCTAssertEqual(result, 1709294400)
    }

    func testTimestamp_dateOnly_zeroFillsTime() {
        // 20240301 -> 2024-03-01 00:00:00 UTC
        let result = XMLTVTimestamp.parse("20240301")
        XCTAssertEqual(result, 1709251200)
    }

    // MARK: - Invalid Input

    func testInvalidTimestamp_returnsNil() {
        XCTAssertNil(XMLTVTimestamp.parse("not-a-timestamp"))
    }

    func testEmptyString_returnsNil() {
        XCTAssertNil(XMLTVTimestamp.parse(""))
    }

    func testGarbageInput_returnsNil() {
        XCTAssertNil(XMLTVTimestamp.parse("abc12345"))
    }

    func testTooShort_returnsNil() {
        XCTAssertNil(XMLTVTimestamp.parse("202403"))
    }

    func testInvalidMonth_returnsNil() {
        XCTAssertNil(XMLTVTimestamp.parse("20241301120000"))
    }

    func testInvalidDay_returnsNil() {
        XCTAssertNil(XMLTVTimestamp.parse("20240332120000"))
    }

    func testInvalidHour_returnsNil() {
        XCTAssertNil(XMLTVTimestamp.parse("20240301250000"))
    }

    // MARK: - Whitespace Handling

    func testTimestamp_leadingTrailingWhitespace_trimmed() {
        let result = XMLTVTimestamp.parse("  20240301120000 +0000  ")
        XCTAssertEqual(result, 1709294400)
    }
}
