import Foundation

// MARK: - XMLTV Test Fixtures

enum XMLTVFixtures {

    // MARK: 1. Standard Well-Formed XMLTV

    static let standard = """
    <?xml version="1.0" encoding="UTF-8"?>
    <!DOCTYPE tv SYSTEM "xmltv.dtd">
    <tv generator-info-name="TestGen" generator-info-url="https://example.com/gen" source-info-url="https://example.com/src" source-info-name="TestSource">
      <channel id="BBC1.uk">
        <display-name>BBC One</display-name>
        <icon src="https://example.com/bbc1.png"/>
      </channel>
      <channel id="CNN.us">
        <display-name>CNN</display-name>
        <icon src="https://example.com/cnn.png"/>
        <url>https://www.cnn.com</url>
      </channel>
      <programme start="20240301120000 +0000" stop="20240301130000 +0000" channel="BBC1.uk">
        <title lang="en">News at Noon</title>
        <desc lang="en">The latest headlines from around the world.</desc>
        <category lang="en">News</category>
        <icon src="https://example.com/news.png"/>
      </programme>
      <programme start="20240301130000 +0000" stop="20240301140000 +0000" channel="BBC1.uk">
        <title lang="en">Afternoon Show</title>
        <desc lang="en">Entertainment and interviews.</desc>
        <category lang="en">Entertainment</category>
      </programme>
      <programme start="20240301120000 +0000" stop="20240301133000 +0000" channel="CNN.us">
        <title lang="en">CNN Newsroom</title>
        <desc lang="en">Breaking news coverage.</desc>
        <category lang="en">News</category>
      </programme>
      <programme start="20240301133000 +0000" stop="20240301150000 +0000" channel="CNN.us">
        <title lang="en">The Lead</title>
        <category lang="en">News</category>
        <category lang="en">Politics</category>
      </programme>
    </tv>
    """

    // MARK: 2. Channels Only

    static let channelsOnly = """
    <?xml version="1.0" encoding="UTF-8"?>
    <tv>
      <channel id="CH1">
        <display-name>Channel One</display-name>
      </channel>
      <channel id="CH2">
        <display-name>Channel Two</display-name>
        <icon src="https://example.com/ch2.png"/>
      </channel>
    </tv>
    """

    // MARK: 3. Programmes Without Channel Definitions

    static let programmesWithoutChannels = """
    <?xml version="1.0" encoding="UTF-8"?>
    <tv>
      <programme start="20240301120000 +0000" stop="20240301130000 +0000" channel="MYSTERY.ch">
        <title>Mystery Show</title>
        <desc>A mysterious programme.</desc>
      </programme>
    </tv>
    """

    // MARK: 4. Multiple Display Names

    static let multipleDisplayNames = """
    <?xml version="1.0" encoding="UTF-8"?>
    <tv>
      <channel id="ARD.de">
        <display-name lang="de">Das Erste</display-name>
        <display-name lang="en">ARD</display-name>
        <display-name>Channel 1</display-name>
      </channel>
    </tv>
    """

    // MARK: 5. Missing Optional Fields

    static let missingOptionalFields = """
    <?xml version="1.0" encoding="UTF-8"?>
    <tv>
      <channel id="MIN.ch">
        <display-name>Minimal Channel</display-name>
      </channel>
      <programme start="20240301120000 +0000" stop="20240301130000 +0000" channel="MIN.ch">
        <title>Minimal Show</title>
      </programme>
    </tv>
    """

    // MARK: 6. No Timezone Offset

    static let noTimezoneOffset = """
    <?xml version="1.0" encoding="UTF-8"?>
    <tv>
      <programme start="20240301120000" stop="20240301130000" channel="TEST.ch">
        <title>No TZ Show</title>
      </programme>
    </tv>
    """

    // MARK: 7. Half-Hour Timezone Offset (India)

    static let halfHourTimezoneOffset = """
    <?xml version="1.0" encoding="UTF-8"?>
    <tv>
      <programme start="20240301173000 +0530" stop="20240301183000 +0530" channel="STAR.in">
        <title>Bollywood Hour</title>
      </programme>
    </tv>
    """

    // MARK: 8. Negative Timezone Offset

    static let negativeTimezoneOffset = """
    <?xml version="1.0" encoding="UTF-8"?>
    <tv>
      <programme start="20240301070000 -0500" stop="20240301080000 -0500" channel="NBC.us">
        <title>Today Show</title>
      </programme>
    </tv>
    """

    // MARK: 9. Multiple Categories

    static let multipleCategories = """
    <?xml version="1.0" encoding="UTF-8"?>
    <tv>
      <programme start="20240301200000 +0000" stop="20240301210000 +0000" channel="BBC2.uk">
        <title>Documentary Night</title>
        <category lang="en">Documentary</category>
        <category lang="en">Science</category>
        <category lang="en">Nature</category>
      </programme>
    </tv>
    """

    // MARK: 10. Special Characters (XML Entities)

    static let specialCharacters = """
    <?xml version="1.0" encoding="UTF-8"?>
    <tv>
      <channel id="SPEC.ch">
        <display-name>Tom &amp; Jerry's "Show"</display-name>
      </channel>
      <programme start="20240301120000 +0000" stop="20240301130000 +0000" channel="SPEC.ch">
        <title>Rock &amp; Roll &lt;Live&gt;</title>
        <desc>A show about "music" &amp; more.</desc>
      </programme>
    </tv>
    """

    // MARK: 11. Unicode Content

    static let unicodeContent = """
    <?xml version="1.0" encoding="UTF-8"?>
    <tv>
      <channel id="AR.ch">
        <display-name>الجزيرة</display-name>
      </channel>
      <channel id="CN.ch">
        <display-name>中央电视台</display-name>
      </channel>
      <channel id="RU.ch">
        <display-name>Первый канал</display-name>
      </channel>
      <programme start="20240301120000 +0000" stop="20240301130000 +0000" channel="AR.ch">
        <title>الأخبار</title>
        <desc>نشرة الأخبار المسائية</desc>
      </programme>
    </tv>
    """

    // MARK: 12. Empty Document

    static let emptyDocument = """
    <?xml version="1.0" encoding="UTF-8"?>
    <tv></tv>
    """

    // MARK: 13. Not XMLTV (HTML page)

    static let notXMLTV = """
    <html>
    <head><title>Error</title></head>
    <body><h1>404 Not Found</h1></body>
    </html>
    """

    // MARK: 14. Malformed XML

    static let malformedXML = """
    <?xml version="1.0" encoding="UTF-8"?>
    <tv>
      <channel id="BROKEN">
        <display-name>Broken Channel
      </channel>
      <programme start="20240301120000 +0000" stop="20240301130000 +0000" channel="OK.ch">
        <title>This should still parse if XMLParser recovers</title>
      </programme>
    </tv>
    """

    // MARK: 15. Mixed Valid and Invalid

    static let mixedValidInvalid = """
    <?xml version="1.0" encoding="UTF-8"?>
    <tv>
      <channel id="GOOD.ch">
        <display-name>Good Channel</display-name>
      </channel>
      <channel id="">
        <display-name>Empty ID Channel</display-name>
      </channel>
      <programme start="20240301120000 +0000" stop="20240301130000 +0000" channel="GOOD.ch">
        <title>Good Show</title>
      </programme>
      <programme start="INVALID" stop="20240301130000 +0000" channel="GOOD.ch">
        <title>Bad Timestamp Show</title>
      </programme>
      <programme start="20240301140000 +0000" stop="20240301150000 +0000" channel="GOOD.ch">
        <title>Another Good Show</title>
      </programme>
    </tv>
    """

    // MARK: 16. Rating and Episode Number

    static let ratingAndEpisodeNum = """
    <?xml version="1.0" encoding="UTF-8"?>
    <tv>
      <programme start="20240301200000 +0000" stop="20240301210000 +0000" channel="HBO.us">
        <title>Drama Series</title>
        <sub-title>Episode Title</sub-title>
        <desc>An intense drama.</desc>
        <date>2024</date>
        <episode-num system="xmltv_ns">2.5.</episode-num>
        <rating system="MPAA">
          <value>TV-MA</value>
        </rating>
      </programme>
    </tv>
    """

    // MARK: 17. Duplicate Programmes

    static let duplicateProgrammes = """
    <?xml version="1.0" encoding="UTF-8"?>
    <tv>
      <programme start="20240301120000 +0000" stop="20240301130000 +0000" channel="DUP.ch">
        <title>Show A</title>
      </programme>
      <programme start="20240301120000 +0000" stop="20240301130000 +0000" channel="DUP.ch">
        <title>Show B</title>
      </programme>
    </tv>
    """

    // MARK: 18. Empty String

    static let emptyString = ""

    // MARK: 19. Whitespace in Text

    static let whitespaceInText = """
    <?xml version="1.0" encoding="UTF-8"?>
    <tv>
      <channel id="WS.ch">
        <display-name>  Whitespace Channel  </display-name>
      </channel>
      <programme start="20240301120000 +0000" stop="20240301130000 +0000" channel="WS.ch">
        <title>  Padded Title  </title>
        <desc>  Padded description  </desc>
      </programme>
    </tv>
    """

    // MARK: 20. Channel with Icon Variations

    static let iconVariations = """
    <?xml version="1.0" encoding="UTF-8"?>
    <tv>
      <channel id="ICON1.ch">
        <display-name>Has Icon</display-name>
        <icon src="https://example.com/logo.png"/>
      </channel>
      <channel id="ICON2.ch">
        <display-name>No Icon</display-name>
      </channel>
      <programme start="20240301120000 +0000" stop="20240301130000 +0000" channel="ICON1.ch">
        <title>Show With Icon</title>
        <icon src="https://example.com/show.png"/>
      </programme>
      <programme start="20240301120000 +0000" stop="20240301130000 +0000" channel="ICON2.ch">
        <title>Show Without Icon</title>
      </programme>
    </tv>
    """

    // MARK: 21. Missing Required Programme Fields

    static let missingRequiredFields = """
    <?xml version="1.0" encoding="UTF-8"?>
    <tv>
      <programme stop="20240301130000 +0000" channel="TEST.ch">
        <title>Missing Start</title>
      </programme>
      <programme start="20240301120000 +0000" channel="TEST.ch">
        <title>Missing Stop</title>
      </programme>
      <programme start="20240301120000 +0000" stop="20240301130000 +0000">
        <title>Missing Channel</title>
      </programme>
      <programme start="20240301120000 +0000" stop="20240301130000 +0000" channel="TEST.ch">
      </programme>
    </tv>
    """

    // MARK: 22. Large EPG Generator

    static func largeEPG(channelCount: Int = 500, programmesPerChannel: Int = 48) -> String {
        var xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <tv generator-info-name="TestGenerator">

        """

        for c in 1...channelCount {
            xml += """
              <channel id="CH\(c).test">
                <display-name>Channel \(c)</display-name>
              </channel>\n
            """
        }

        // Base: 2024-03-01 00:00:00 UTC = 1709251200
        let baseEpoch = 1709251200
        let slotDuration = 1800 // 30-minute slots

        for c in 1...channelCount {
            for p in 0..<programmesPerChannel {
                let startEpoch = baseEpoch + p * slotDuration
                let stopEpoch = startEpoch + slotDuration

                let startTS = epochToXMLTV(startEpoch)
                let stopTS = epochToXMLTV(stopEpoch)

                xml += """
                  <programme start="\(startTS) +0000" stop="\(stopTS) +0000" channel="CH\(c).test">
                    <title>Show \(p + 1) on Channel \(c)</title>
                    <desc>Description for show \(p + 1)</desc>
                    <category>General</category>
                  </programme>\n
                """
            }
        }

        xml += "</tv>"
        return xml
    }

    // MARK: - Helpers

    private static func epochToXMLTV(_ epoch: Int) -> String {
        let date = Date(timeIntervalSince1970: Double(epoch))
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMddHHmmss"
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter.string(from: date)
    }
}
