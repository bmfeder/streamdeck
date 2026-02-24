import XCTest
@testable import XMLTVParser

final class XMLTVParserTests: XCTestCase {

    private let parser = XMLTVParser()

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: 1 · Standard Parsing
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    func testStandard_parsesAllChannels() {
        let result = parser.parse(content: XMLTVFixtures.standard)
        XCTAssertEqual(result.channelCount, 2)
    }

    func testStandard_parsesAllProgrammes() {
        let result = parser.parse(content: XMLTVFixtures.standard)
        XCTAssertEqual(result.programCount, 4)
    }

    func testStandard_channelFieldsCorrect() {
        let result = parser.parse(content: XMLTVFixtures.standard)
        let bbc = result.channels.first { $0.id == "BBC1.uk" }
        XCTAssertNotNil(bbc)
        XCTAssertEqual(bbc?.displayName, "BBC One")
        XCTAssertEqual(bbc?.iconURL, URL(string: "https://example.com/bbc1.png"))
    }

    func testStandard_programmeFieldsCorrect() {
        let result = parser.parse(content: XMLTVFixtures.standard)
        let news = result.programs.first { $0.title == "News at Noon" }
        XCTAssertNotNil(news)
        XCTAssertEqual(news?.channelID, "BBC1.uk")
        XCTAssertEqual(news?.startTimestamp, 1709294400) // 2024-03-01 12:00 UTC
        XCTAssertEqual(news?.stopTimestamp, 1709298000)  // 2024-03-01 13:00 UTC
        XCTAssertEqual(news?.description, "The latest headlines from around the world.")
        XCTAssertEqual(news?.category, "News")
        XCTAssertEqual(news?.iconURL, URL(string: "https://example.com/news.png"))
    }

    func testStandard_metadataExtracted() {
        let result = parser.parse(content: XMLTVFixtures.standard)
        XCTAssertEqual(result.metadata.generatorName, "TestGen")
        XCTAssertEqual(result.metadata.generatorURL, "https://example.com/gen")
        XCTAssertEqual(result.metadata.sourceInfoURL, "https://example.com/src")
        XCTAssertEqual(result.metadata.sourceInfoName, "TestSource")
    }

    func testStandard_noErrors() {
        let result = parser.parse(content: XMLTVFixtures.standard)
        XCTAssertEqual(result.errorCount, 0)
    }

    func testStandard_channelWithURL() {
        let result = parser.parse(content: XMLTVFixtures.standard)
        let cnn = result.channels.first { $0.id == "CNN.us" }
        XCTAssertEqual(cnn?.urls, [URL(string: "https://www.cnn.com")!])
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: 2 · Channel Parsing
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    func testChannelsOnly_parsesWithNoProgrammes() {
        let result = parser.parse(content: XMLTVFixtures.channelsOnly)
        XCTAssertEqual(result.channelCount, 2)
        XCTAssertEqual(result.programCount, 0)
        XCTAssertEqual(result.errorCount, 0)
    }

    func testMultipleDisplayNames_allCaptured() {
        let result = parser.parse(content: XMLTVFixtures.multipleDisplayNames)
        let ard = result.channels.first { $0.id == "ARD.de" }
        XCTAssertNotNil(ard)
        XCTAssertEqual(ard?.displayName, "Das Erste")
        XCTAssertEqual(ard?.displayNames, ["Das Erste", "ARD", "Channel 1"])
    }

    func testMissingChannelID_recordsError() {
        let result = parser.parse(content: XMLTVFixtures.mixedValidInvalid)
        let idErrors = result.errors.filter { $0.reason == .missingChannelID }
        XCTAssertEqual(idErrors.count, 1)
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: 3 · Programme Parsing
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    func testProgrammesWithoutChannels_stillParses() {
        let result = parser.parse(content: XMLTVFixtures.programmesWithoutChannels)
        XCTAssertEqual(result.channelCount, 0)
        XCTAssertEqual(result.programCount, 1)
        XCTAssertEqual(result.programs[0].channelID, "MYSTERY.ch")
    }

    func testMissingOptionalFields_nilValues() {
        let result = parser.parse(content: XMLTVFixtures.missingOptionalFields)
        let show = result.programs[0]
        XCTAssertEqual(show.title, "Minimal Show")
        XCTAssertNil(show.description)
        XCTAssertNil(show.category)
        XCTAssertNil(show.iconURL)
        XCTAssertNil(show.subtitle)
        XCTAssertNil(show.date)
        XCTAssertNil(show.episodeNum)
        XCTAssertNil(show.rating)
    }

    func testMultipleCategories_allCaptured() {
        let result = parser.parse(content: XMLTVFixtures.multipleCategories)
        let show = result.programs[0]
        XCTAssertEqual(show.categories, ["Documentary", "Science", "Nature"])
        XCTAssertEqual(show.category, "Documentary") // first category
    }

    func testMultipleCategories_inStandard() {
        let result = parser.parse(content: XMLTVFixtures.standard)
        let lead = result.programs.first { $0.title == "The Lead" }
        XCTAssertEqual(lead?.categories, ["News", "Politics"])
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: 4 · Timestamp Parsing (via parser)
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    func testNoTimezoneOffset_treatedAsUTC() {
        let result = parser.parse(content: XMLTVFixtures.noTimezoneOffset)
        XCTAssertEqual(result.programs[0].startTimestamp, 1709294400)
    }

    func testHalfHourOffset_convertedToUTC() {
        let result = parser.parse(content: XMLTVFixtures.halfHourTimezoneOffset)
        // 17:30 IST (+0530) = 12:00 UTC = 1709294400
        XCTAssertEqual(result.programs[0].startTimestamp, 1709294400)
    }

    func testNegativeOffset_convertedToUTC() {
        let result = parser.parse(content: XMLTVFixtures.negativeTimezoneOffset)
        // 07:00 EST (-0500) = 12:00 UTC = 1709294400
        XCTAssertEqual(result.programs[0].startTimestamp, 1709294400)
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: 5 · Special Characters / Unicode
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    func testXMLEntities_decodedCorrectly() {
        let result = parser.parse(content: XMLTVFixtures.specialCharacters)
        let channel = result.channels.first { $0.id == "SPEC.ch" }
        XCTAssertEqual(channel?.displayName, "Tom & Jerry's \"Show\"")

        let show = result.programs[0]
        XCTAssertEqual(show.title, "Rock & Roll <Live>")
        XCTAssertEqual(show.description, "A show about \"music\" & more.")
    }

    func testUnicodeText_parsedCorrectly() {
        let result = parser.parse(content: XMLTVFixtures.unicodeContent)
        XCTAssertEqual(result.channelCount, 3)

        let arabic = result.channels.first { $0.id == "AR.ch" }
        XCTAssertEqual(arabic?.displayName, "الجزيرة")

        let chinese = result.channels.first { $0.id == "CN.ch" }
        XCTAssertEqual(chinese?.displayName, "中央电视台")

        let russian = result.channels.first { $0.id == "RU.ch" }
        XCTAssertEqual(russian?.displayName, "Первый канал")

        let program = result.programs[0]
        XCTAssertEqual(program.title, "الأخبار")
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: 6 · Error Handling
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    func testMalformedXML_doesNotCrash() {
        let result = parser.parse(content: XMLTVFixtures.malformedXML)
        // Should not crash; may have XML parser errors
        let xmlErrors = result.errors.filter { $0.reason == .xmlParserError }
        XCTAssertFalse(xmlErrors.isEmpty)
    }

    func testNotXMLTV_returnsEmptyResult() {
        let result = parser.parse(content: XMLTVFixtures.notXMLTV)
        XCTAssertEqual(result.channelCount, 0)
        XCTAssertEqual(result.programCount, 0)
    }

    func testMixedValidInvalid_parsesGoodSkipsBad() {
        let result = parser.parse(content: XMLTVFixtures.mixedValidInvalid)
        // 1 good channel (GOOD.ch), 1 bad (empty id)
        XCTAssertEqual(result.channelCount, 1)
        // 2 good programmes, 1 bad timestamp
        XCTAssertEqual(result.programCount, 2)
        XCTAssertTrue(result.errorCount >= 2) // at least: empty id + bad timestamp
    }

    func testEmptyDocument_returnsEmptyResult() {
        let result = parser.parse(content: XMLTVFixtures.emptyDocument)
        XCTAssertEqual(result.channelCount, 0)
        XCTAssertEqual(result.programCount, 0)
        XCTAssertEqual(result.errorCount, 0)
    }

    func testMissingRequiredFields_recordsErrors() {
        let result = parser.parse(content: XMLTVFixtures.missingRequiredFields)
        XCTAssertEqual(result.programCount, 0)

        let startErrors = result.errors.filter { $0.reason == .missingProgrammeStart }
        XCTAssertEqual(startErrors.count, 1)

        let stopErrors = result.errors.filter { $0.reason == .missingProgrammeStop }
        XCTAssertEqual(stopErrors.count, 1)

        let channelErrors = result.errors.filter { $0.reason == .missingProgrammeChannel }
        XCTAssertEqual(channelErrors.count, 1)

        let titleErrors = result.errors.filter { $0.reason == .missingTitle }
        XCTAssertEqual(titleErrors.count, 1)
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: 7 · Edge Cases
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    func testEmptyString_returnsEmptyResult() {
        let result = parser.parse(content: XMLTVFixtures.emptyString)
        XCTAssertEqual(result.channelCount, 0)
        XCTAssertEqual(result.programCount, 0)
        XCTAssertEqual(result.errorCount, 0)
    }

    func testWhitespaceInText_trimmed() {
        let result = parser.parse(content: XMLTVFixtures.whitespaceInText)
        let channel = result.channels.first { $0.id == "WS.ch" }
        XCTAssertEqual(channel?.displayName, "Whitespace Channel")

        let show = result.programs[0]
        XCTAssertEqual(show.title, "Padded Title")
        XCTAssertEqual(show.description, "Padded description")
    }

    func testDuplicateProgrammes_allPreserved() {
        let result = parser.parse(content: XMLTVFixtures.duplicateProgrammes)
        XCTAssertEqual(result.programCount, 2)
        let titles = result.programs.map(\.title)
        XCTAssertTrue(titles.contains("Show A"))
        XCTAssertTrue(titles.contains("Show B"))
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: 8 · Ratings and Episode Numbers
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    func testRating_parsedFromNestedElement() {
        let result = parser.parse(content: XMLTVFixtures.ratingAndEpisodeNum)
        let show = result.programs[0]
        XCTAssertEqual(show.rating, "TV-MA")
    }

    func testEpisodeNum_rawValueCaptured() {
        let result = parser.parse(content: XMLTVFixtures.ratingAndEpisodeNum)
        let show = result.programs[0]
        XCTAssertEqual(show.episodeNum, "2.5.")
    }

    func testSubtitleAndDate_captured() {
        let result = parser.parse(content: XMLTVFixtures.ratingAndEpisodeNum)
        let show = result.programs[0]
        XCTAssertEqual(show.subtitle, "Episode Title")
        XCTAssertEqual(show.date, "2024")
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: 9 · Icon URLs
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    func testChannelIcons_parsedCorrectly() {
        let result = parser.parse(content: XMLTVFixtures.iconVariations)
        let withIcon = result.channels.first { $0.id == "ICON1.ch" }
        let withoutIcon = result.channels.first { $0.id == "ICON2.ch" }
        XCTAssertEqual(withIcon?.iconURL, URL(string: "https://example.com/logo.png"))
        XCTAssertNil(withoutIcon?.iconURL)
    }

    func testProgrammeIcons_parsedCorrectly() {
        let result = parser.parse(content: XMLTVFixtures.iconVariations)
        let withIcon = result.programs.first { $0.title == "Show With Icon" }
        let withoutIcon = result.programs.first { $0.title == "Show Without Icon" }
        XCTAssertEqual(withIcon?.iconURL, URL(string: "https://example.com/show.png"))
        XCTAssertNil(withoutIcon?.iconURL)
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: 10 · Data Input Methods
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    func testParseData_identicalToParseContent() {
        let contentResult = parser.parse(content: XMLTVFixtures.standard)
        let data = XMLTVFixtures.standard.data(using: .utf8)!
        let dataResult = parser.parse(data: data)

        XCTAssertEqual(contentResult.channelCount, dataResult.channelCount)
        XCTAssertEqual(contentResult.programCount, dataResult.programCount)
        XCTAssertEqual(contentResult.channels, dataResult.channels)
        XCTAssertEqual(contentResult.programs, dataResult.programs)
    }

    func testParseFileURL_works() throws {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("test_xmltv_\(UUID().uuidString).xml")
        let data = XMLTVFixtures.standard.data(using: .utf8)!
        try data.write(to: tempURL)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let result = try parser.parse(fileURL: tempURL)
        XCTAssertEqual(result.channelCount, 2)
        XCTAssertEqual(result.programCount, 4)
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: 11 · Sendable / Thread Safety
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    func testParserIsSendable_canCallFromMultipleTasks() async {
        let sharedParser = XMLTVParser()
        let content = XMLTVFixtures.standard

        await withTaskGroup(of: Int.self) { group in
            for _ in 0..<10 {
                group.addTask {
                    let result = sharedParser.parse(content: content)
                    return result.programCount
                }
            }
            for await count in group {
                XCTAssertEqual(count, 4)
            }
        }
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: 12 · Performance
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    func testLargeEPG_24000programmes_parsesCompletely() {
        let xml = XMLTVFixtures.largeEPG(channelCount: 500, programmesPerChannel: 48)
        let result = parser.parse(content: xml)
        XCTAssertEqual(result.channelCount, 500)
        XCTAssertEqual(result.programCount, 24_000)
        XCTAssertEqual(result.errorCount, 0)
    }

    func testLargeEPG_measuredPerformance() {
        let xml = XMLTVFixtures.largeEPG(channelCount: 500, programmesPerChannel: 48)
        measure {
            _ = parser.parse(content: xml)
        }
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: 13 · Error Reporting Quality
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    func testErrors_rawTextTruncated() {
        let longTitle = String(repeating: "x", count: 300)
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <tv>
          <programme start="INVALID" stop="20240301130000 +0000" channel="TEST.ch">
            <title>\(longTitle)</title>
          </programme>
        </tv>
        """
        let result = parser.parse(content: xml)
        let error = result.errors.first { $0.reason == .invalidTimestamp }
        XCTAssertNotNil(error)
        XCTAssertLessThanOrEqual(error?.rawText.count ?? 0, 200)
    }

    func testErrors_includeElementContext() {
        let result = parser.parse(content: XMLTVFixtures.mixedValidInvalid)
        let tsError = result.errors.first { $0.reason == .invalidTimestamp }
        XCTAssertNotNil(tsError)
        XCTAssertTrue(tsError?.element.contains("programme") ?? false)
    }
}
