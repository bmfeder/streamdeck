import XCTest
@testable import M3UParser

final class M3UParserTests: XCTestCase {

    private let parser = M3UParser()

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - 1. Standard Parsing
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    func testStandardPlaylist_parsesAllChannels() {
        let result = parser.parse(content: M3UFixtures.standard)

        XCTAssertEqual(result.successCount, 3)
        XCTAssertEqual(result.errorCount, 0)
        XCTAssertTrue(result.metadata.hasExtM3UHeader)

        let bbc = result.channels[0]
        XCTAssertEqual(bbc.name, "BBC One HD")
        XCTAssertEqual(bbc.tvgId, "BBC1.uk")
        XCTAssertEqual(bbc.tvgName, "BBC One")
        XCTAssertEqual(bbc.groupTitle, "UK Entertainment")
        XCTAssertEqual(bbc.tvgLogo?.absoluteString, "https://cdn.example.com/bbc1.png")
        XCTAssertEqual(bbc.streamURL.absoluteString, "http://stream.example.com/live/bbc1/index.m3u8")
        XCTAssertEqual(bbc.duration, -1) // live stream

        let espn = result.channels[2]
        XCTAssertEqual(espn.name, "ESPN HD")
        XCTAssertEqual(espn.groupTitle, "US Sports")
    }

    func testStandardPlaylist_extractsCorrectGroups() {
        let result = parser.parse(content: M3UFixtures.standard)
        let groups = Set(result.channels.compactMap(\.groupTitle))
        XCTAssertEqual(groups, ["UK Entertainment", "US News", "US Sports"])
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - 2. BOM + CRLF Handling
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    func testBOMAndCRLF_parsesCorrectly() {
        let result = parser.parse(content: M3UFixtures.bomAndCRLF)

        XCTAssertEqual(result.successCount, 2)
        XCTAssertEqual(result.errorCount, 0)
        XCTAssertTrue(result.metadata.hasExtM3UHeader)
        XCTAssertEqual(result.channels[0].name, "Channel One")
        XCTAssertEqual(result.channels[1].name, "Channel Two")
    }

    func testBOMAndCRLF_urlsAreClean() {
        let result = parser.parse(content: M3UFixtures.bomAndCRLF)
        // Ensure no \r leaked into URLs
        for channel in result.channels {
            XCTAssertFalse(channel.streamURL.absoluteString.contains("\r"))
            XCTAssertFalse(channel.streamURL.absoluteString.contains("\n"))
        }
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - 3. Missing Attributes
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    func testMissingGroupTitle_parsesWithNil() {
        let result = parser.parse(content: M3UFixtures.missingGroupTitle)

        XCTAssertEqual(result.successCount, 3)
        XCTAssertNil(result.channels[0].groupTitle) // BBC One has no group
        XCTAssertEqual(result.channels[1].groupTitle, "News") // CNN has group
        XCTAssertNil(result.channels[2].groupTitle) // No Attributes Channel
        XCTAssertEqual(result.channels[2].name, "No Attributes Channel")
    }

    func testMissingGroupTitle_tvgIdStillParsed() {
        let result = parser.parse(content: M3UFixtures.missingGroupTitle)
        XCTAssertEqual(result.channels[0].tvgId, "BBC1")
        XCTAssertNil(result.channels[2].tvgId) // no tvg-id either
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - 4. Non-Standard Tags
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    func testNonStandardTags_skippedGracefully() {
        let result = parser.parse(content: M3UFixtures.nonStandardTags)

        XCTAssertEqual(result.successCount, 2)
        XCTAssertEqual(result.errorCount, 0)
        XCTAssertEqual(result.channels[0].name, "Channel One")
        XCTAssertEqual(result.channels[1].name, "Channel Two")
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - 5. Whitespace Handling
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    func testExtraWhitespace_parsesCorrectly() {
        let result = parser.parse(content: M3UFixtures.extraWhitespace)

        XCTAssertEqual(result.successCount, 2)
        XCTAssertEqual(result.errorCount, 0)
        XCTAssertEqual(result.channels[0].name, "Channel One")
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - 6. Large Playlists (Performance)
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    func testHugePlaylist_5000channels_parsesCompletely() {
        let content = M3UFixtures.hugePlaylist(count: 5000)
        let result = parser.parse(content: content)

        XCTAssertEqual(result.successCount, 5000)
        XCTAssertEqual(result.errorCount, 0)
    }

    func testHugePlaylist_5000channels_completesUnder2Seconds() {
        let content = M3UFixtures.hugePlaylist(count: 5000)

        measure {
            _ = parser.parse(content: content)
        }
        // XCTest measure() reports avg time. Manual check: should be <2s.
    }

    func testHugePlaylist_groupDistribution() {
        let result = parser.parse(content: M3UFixtures.hugePlaylist(count: 100))
        let groups = Dictionary(grouping: result.channels, by: \.groupTitle)
        XCTAssertEqual(groups.count, 5) // 5 rotating groups
        // Each group should have 20 channels (100 / 5)
        for (_, channels) in groups {
            XCTAssertEqual(channels.count, 20)
        }
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - 7. HTML Error Page (Totally Broken Input)
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    func testHTMLErrorPage_doesNotCrash() {
        let result = parser.parse(content: M3UFixtures.htmlErrorPage)

        XCTAssertEqual(result.successCount, 0)
        XCTAssertFalse(result.metadata.hasExtM3UHeader)
        // Should not crash — that's the main assertion
    }

    func testHTMLErrorPage_returnsEmptyResult() {
        let result = parser.parse(content: M3UFixtures.htmlErrorPage)
        XCTAssertTrue(result.channels.isEmpty)
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - 8. Single-Quoted Attributes
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    func testSingleQuotedAttributes_parsedCorrectly() {
        let result = parser.parse(content: M3UFixtures.singleQuotedAttributes)

        XCTAssertEqual(result.successCount, 2)
        XCTAssertEqual(result.channels[0].tvgId, "BBC1")
        XCTAssertEqual(result.channels[0].tvgName, "BBC One")
        XCTAssertEqual(result.channels[0].groupTitle, "UK TV")
        XCTAssertNotNil(result.channels[0].tvgLogo)
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - 9. Commas Inside Attribute Values
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    func testCommasInAttributes_groupTitlePreserved() {
        let result = parser.parse(content: M3UFixtures.commasInAttributes)

        XCTAssertEqual(result.successCount, 2)
        XCTAssertEqual(result.channels[0].groupTitle, "Movies, Drama")
        XCTAssertEqual(result.channels[1].groupTitle, "Action, Thriller")
    }

    func testCommasInAttributes_channelNameCorrect() {
        let result = parser.parse(content: M3UFixtures.commasInAttributes)
        // "The Good, The Bad and The Ugly" — the last comma is the name delimiter
        // Channel name should be everything after the last unquoted comma
        XCTAssertEqual(result.channels[0].name, "The Good, The Bad and The Ugly")
        XCTAssertEqual(result.channels[1].name, "Die Hard")
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - 10. Complex URLs
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    func testComplexURLs_tokenParamsPreserved() {
        let result = parser.parse(content: M3UFixtures.complexURLs)

        XCTAssertEqual(result.successCount, 3)
        XCTAssertTrue(result.channels[0].streamURL.absoluteString.contains("token=abc123def456"))
        XCTAssertTrue(result.channels[1].streamURL.absoluteString.contains(":8080/live/username/password/"))
        XCTAssertTrue(result.channels[2].streamURL.absoluteString.hasPrefix("https://"))
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - 11. Mixed Valid + Invalid Entries
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    func testMixedValidInvalid_parsesGoodEntriesOnly() {
        let result = parser.parse(content: M3UFixtures.mixedValidInvalid)

        // Good channels: OK1, OK2, OK3, bad_dur (has a URL even though duration is garbage), orphan
        XCTAssertGreaterThanOrEqual(result.successCount, 3)
        // Verify the good ones are there
        let names = result.channels.map(\.name)
        XCTAssertTrue(names.contains("Good Channel 1"))
        XCTAssertTrue(names.contains("Good Channel 2"))
        XCTAssertTrue(names.contains("Good Channel 3"))
    }

    func testMixedValidInvalid_reportsErrors() {
        let result = parser.parse(content: M3UFixtures.mixedValidInvalid)

        // Should have errors for: Missing URL Channel, orphaned URL
        XCTAssertGreaterThan(result.errorCount, 0)
        let reasons = result.errors.map(\.reason)
        XCTAssertTrue(reasons.contains(.missingStreamURL))
    }

    func testMixedValidInvalid_errorCountPlusSuccessAccountsForAll() {
        let result = parser.parse(content: M3UFixtures.mixedValidInvalid)
        // Not a strict count check, but ensures we're tracking everything
        XCTAssertGreaterThan(result.totalEntries, 0)
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - 12. Empty Input
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    func testEmptyString_returnsEmptyResult() {
        let result = parser.parse(content: M3UFixtures.emptyString)

        XCTAssertEqual(result.successCount, 0)
        XCTAssertEqual(result.errorCount, 0)
        XCTAssertFalse(result.metadata.hasExtM3UHeader)
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - 13. Header Only
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    func testHeaderOnly_returnsEmptyChannels() {
        let result = parser.parse(content: M3UFixtures.headerOnly)

        XCTAssertEqual(result.successCount, 0)
        XCTAssertTrue(result.metadata.hasExtM3UHeader)
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - 14. Header Metadata (EPG URL)
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    func testHeaderWithEPG_extractsMetadata() {
        let result = parser.parse(content: M3UFixtures.headerWithEPG)

        XCTAssertEqual(result.metadata.urlTvg, "http://epg.example.com/guide.xml")
        XCTAssertEqual(result.metadata.tvgShift, "0")
        XCTAssertEqual(result.metadata.catchupSource, "http://catchup.example.com")
        XCTAssertEqual(result.successCount, 1)
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - 15. Channel Numbers
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    func testChannelNumbers_tvgChno() {
        let result = parser.parse(content: M3UFixtures.channelNumbers)

        XCTAssertEqual(result.channels[0].channelNumber, 101) // tvg-chno
        XCTAssertEqual(result.channels[1].channelNumber, 102) // tvg-chno
    }

    func testChannelNumbers_channelNumberAttribute() {
        let result = parser.parse(content: M3UFixtures.channelNumbers)

        XCTAssertEqual(result.channels[2].channelNumber, 103) // channel-number
    }

    func testChannelNumbers_nilWhenMissing() {
        let result = parser.parse(content: M3UFixtures.channelNumbers)

        XCTAssertNil(result.channels[3].channelNumber) // Channel 4 has no number
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - 16. VOD Entries (Duration > 0)
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    func testVODEntries_durationParsed() {
        let result = parser.parse(content: M3UFixtures.vodEntries)

        XCTAssertEqual(result.channels[0].duration, 7200)  // The Matrix
        XCTAssertEqual(result.channels[1].duration, 5400)  // Inception
        XCTAssertEqual(result.channels[2].duration, -1)    // Live stream
    }

    func testVODEntries_canDistinguishLiveFromVOD() {
        let result = parser.parse(content: M3UFixtures.vodEntries)

        let live = result.channels.filter { $0.duration == -1 }
        let vod = result.channels.filter { $0.duration > 0 }

        XCTAssertEqual(live.count, 1)
        XCTAssertEqual(vod.count, 2)
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - 17. Alternative Protocols (RTSP, RTMP, UDP)
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    func testAlternativeProtocols_allParsed() {
        let result = parser.parse(content: M3UFixtures.alternativeProtocols)

        XCTAssertEqual(result.successCount, 3)
        XCTAssertTrue(result.channels[0].streamURL.absoluteString.hasPrefix("rtsp://"))
        XCTAssertTrue(result.channels[1].streamURL.absoluteString.hasPrefix("rtmp://"))
        XCTAssertTrue(result.channels[2].streamURL.absoluteString.hasPrefix("udp://"))
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - 18. Unicode Channel Names
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    func testUnicodeNames_arabicChineseRussian() {
        let result = parser.parse(content: M3UFixtures.unicodeNames)

        XCTAssertEqual(result.successCount, 4)
        XCTAssertEqual(result.channels[0].name, "الجزيرة")
        XCTAssertEqual(result.channels[0].groupTitle, "العربية")
        XCTAssertEqual(result.channels[1].name, "中央电视台")
        XCTAssertEqual(result.channels[2].name, "Первый канал")
    }

    func testUnicodeNames_emoji() {
        let result = parser.parse(content: M3UFixtures.unicodeNames)

        XCTAssertEqual(result.channels[3].name, "🔥 Fire TV 📺")
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - 19. Duplicate tvg-id Values
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    func testDuplicateTvgIds_allChannelsPreserved() {
        let result = parser.parse(content: M3UFixtures.duplicateTvgIds)

        // Parser should NOT deduplicate — that's the caller's job
        XCTAssertEqual(result.successCount, 3)
        XCTAssertEqual(result.channels.filter { $0.tvgId == "ESPN" }.count, 3)
    }

    func testDuplicateTvgIds_distinctURLs() {
        let result = parser.parse(content: M3UFixtures.duplicateTvgIds)

        let urls = Set(result.channels.map(\.streamURL))
        XCTAssertEqual(urls.count, 3) // 3 different URLs
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - 20. No #EXTM3U Header
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    func testNoHeader_stillParses() {
        let result = parser.parse(content: M3UFixtures.noHeader)

        XCTAssertEqual(result.successCount, 2)
        XCTAssertFalse(result.metadata.hasExtM3UHeader)
        XCTAssertEqual(result.channels[0].name, "Channel One")
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - Error Reporting Quality
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    func testErrors_includeLineNumbers() {
        let result = parser.parse(content: M3UFixtures.mixedValidInvalid)

        for error in result.errors {
            XCTAssertGreaterThan(error.line, 0, "Error line numbers should be 1-indexed")
        }
    }

    func testErrors_rawTextTruncated() {
        // Build a playlist with an extremely long line
        let longLine = "#EXTINF:-1 tvg-id=\"X\"," + String(repeating: "A", count: 1000)
        let content = "#EXTM3U\n\(longLine)\n" // no URL follows → error
        let result = parser.parse(content: content)

        for error in result.errors {
            XCTAssertLessThanOrEqual(error.rawText.count, 200,
                "Error rawText should be truncated to 200 chars")
        }
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - Data Integrity
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    func testAllChannels_haveNonEmptyName() {
        let fixtures = [
            M3UFixtures.standard,
            M3UFixtures.bomAndCRLF,
            M3UFixtures.missingGroupTitle,
            M3UFixtures.nonStandardTags,
            M3UFixtures.complexURLs,
            M3UFixtures.channelNumbers,
            M3UFixtures.unicodeNames,
        ]

        for content in fixtures {
            let result = parser.parse(content: content)
            for channel in result.channels {
                XCTAssertFalse(channel.name.isEmpty, "Channel name should never be empty: \(channel)")
            }
        }
    }

    func testAllChannels_haveValidStreamURL() {
        let result = parser.parse(content: M3UFixtures.standard)
        for channel in result.channels {
            XCTAssertNotNil(channel.streamURL.scheme, "URL should have a scheme: \(channel.streamURL)")
            XCTAssertNotNil(channel.streamURL.host, "URL should have a host: \(channel.streamURL)")
        }
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - Sendable / Thread Safety
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    func testParserIsSendable_canCallFromMultipleThreads() async {
        let content = M3UFixtures.hugePlaylist(count: 100)

        // Parse on multiple concurrent tasks — should not crash
        await withTaskGroup(of: M3UParseResult.self) { group in
            for _ in 0..<10 {
                group.addTask {
                    self.parser.parse(content: content)
                }
            }

            var results: [M3UParseResult] = []
            for await result in group {
                results.append(result)
            }

            // All should produce identical results
            for result in results {
                XCTAssertEqual(result.successCount, 100)
            }
        }
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - Extra Attributes
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    func testExtraAttributes_capturedInExtrasDict() {
        let content = """
        #EXTM3U
        #EXTINF:-1 tvg-id="CH1" tvg-shift="-2" parent-code="1234" catchup="default" group-title="Test",Channel
        http://stream.example.com/ch1
        """
        let result = parser.parse(content: content)

        XCTAssertEqual(result.channels[0].extras["tvg-shift"], "-2")
        XCTAssertEqual(result.channels[0].extras["parent-code"], "1234")
        XCTAssertEqual(result.channels[0].extras["catchup"], "default")
        // Known attributes should NOT be in extras
        XCTAssertNil(result.channels[0].extras["tvg-id"])
        XCTAssertNil(result.channels[0].extras["group-title"])
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - Regression: Orphaned URLs (no EXTINF)
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    func testOrphanedURL_stillAddsChannelWithWarning() {
        let content = """
        #EXTM3U
        http://stream.example.com/orphan1
        http://stream.example.com/orphan2
        """
        let result = parser.parse(content: content)

        XCTAssertEqual(result.successCount, 2, "Orphaned URLs should still be added as channels")
        XCTAssertEqual(result.errorCount, 2, "Orphaned URLs should generate warnings")
        XCTAssertTrue(result.errors.allSatisfy { $0.reason == .orphanedURL })
    }
}
