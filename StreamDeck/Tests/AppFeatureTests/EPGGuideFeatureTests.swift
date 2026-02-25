import ComposableArchitecture
import XCTest
import Database
import Repositories
@testable import AppFeature

@MainActor
final class EPGGuideFeatureTests: XCTestCase {

    // MARK: - Helpers

    private func makePlaylist(
        id: String = "pl-1",
        name: String = "My Playlist",
        epgURL: String? = nil
    ) -> PlaylistRecord {
        PlaylistRecord(id: id, name: name, type: "m3u", url: "http://example.com/pl.m3u", epgURL: epgURL)
    }

    private func makeChannel(
        id: String,
        name: String = "Channel",
        epgID: String? = nil,
        tvgID: String? = nil
    ) -> ChannelRecord {
        ChannelRecord(
            id: id,
            playlistID: "pl-1",
            name: name,
            streamURL: "http://example.com/\(id).ts",
            epgID: epgID,
            tvgID: tvgID
        )
    }

    private func makeProgram(
        id: String,
        channelEpgID: String,
        title: String = "Show",
        startTime: Int,
        endTime: Int
    ) -> EpgProgramRecord {
        EpgProgramRecord(
            id: id,
            channelEpgID: channelEpgID,
            title: title,
            startTime: startTime,
            endTime: endTime
        )
    }

    // Fixed time for tests: 2026-02-25 12:00:00 UTC
    private let testNow = Date(timeIntervalSince1970: 1740484800)
    private let testNowEpoch = 1740484800

    // MARK: - Initial State

    func testInitialState_isEmpty() {
        let state = EPGGuideFeature.State()
        XCTAssertTrue(state.playlists.isEmpty)
        XCTAssertNil(state.selectedPlaylistID)
        XCTAssertTrue(state.channels.isEmpty)
        XCTAssertTrue(state.programsByChannel.isEmpty)
        XCTAssertFalse(state.isLoading)
        XCTAssertFalse(state.hasData)
    }

    func testInitialState_timeWindowDefaults() {
        let state = EPGGuideFeature.State()
        XCTAssertEqual(state.windowStart, 0)
        XCTAssertEqual(state.windowEnd, 0)
        XCTAssertEqual(state.currentTime, 0)
    }

    // MARK: - On Appear

    func testOnAppear_loadsPlaylists() async {
        let playlist = makePlaylist()
        let channels = [makeChannel(id: "ch-1", name: "CNN")]

        let store = TestStore(initialState: EPGGuideFeature.State()) {
            EPGGuideFeature()
        } withDependencies: {
            $0.channelListClient.fetchPlaylists = { [playlist] }
            $0.channelListClient.fetchGroupedChannels = { _ in
                GroupedChannels(groups: ["All"], channelsByGroup: ["All": channels])
            }
            $0.epgClient.fetchProgramsBatch = { _, _, _ in [:] }
            $0.date = .constant(testNow)
        }

        await store.send(.onAppear) {
            $0.isLoading = true
        }

        await store.receive(\.playlistsLoaded.success) {
            $0.playlists = [playlist]
            $0.selectedPlaylistID = "pl-1"
        }

        await store.receive(\.channelsLoaded.success) {
            $0.channels = channels
            $0.currentTime = self.testNowEpoch
            $0.windowStart = EPGGuideLayout.snapToHour(self.testNowEpoch - 2 * 3600)
            $0.windowEnd = EPGGuideLayout.snapToHour(self.testNowEpoch + 4 * 3600) + 3600
        }

        await store.receive(\.programsLoaded.success) {
            $0.isLoading = false
            $0.programsByChannel = [:]
            $0.errorMessage = nil
        }
    }

    func testOnAppear_noPlaylists_showsEmpty() async {
        let store = TestStore(initialState: EPGGuideFeature.State()) {
            EPGGuideFeature()
        } withDependencies: {
            $0.channelListClient.fetchPlaylists = { [] }
        }

        await store.send(.onAppear) {
            $0.isLoading = true
        }

        await store.receive(\.playlistsLoaded.success) {
            $0.playlists = []
            $0.isLoading = false
        }
    }

    func testOnAppear_alreadyLoaded_noOp() async {
        var state = EPGGuideFeature.State()
        state.playlists = [makePlaylist()]

        let store = TestStore(initialState: state) {
            EPGGuideFeature()
        }

        await store.send(.onAppear)
    }

    // MARK: - Playlist Selection

    func testPlaylistSelected_reloadsChannelsAndPrograms() async {
        let channels = [makeChannel(id: "ch-1", name: "CNN")]
        var state = EPGGuideFeature.State()
        state.playlists = [makePlaylist(id: "pl-1"), makePlaylist(id: "pl-2", name: "Second")]
        state.selectedPlaylistID = "pl-1"

        let store = TestStore(initialState: state) {
            EPGGuideFeature()
        } withDependencies: {
            $0.channelListClient.fetchGroupedChannels = { _ in
                GroupedChannels(groups: ["All"], channelsByGroup: ["All": channels])
            }
            $0.epgClient.fetchProgramsBatch = { _, _, _ in [:] }
            $0.date = .constant(testNow)
        }

        await store.send(.playlistSelected("pl-2")) {
            $0.selectedPlaylistID = "pl-2"
            $0.isLoading = true
            $0.programsByChannel = [:]
        }

        await store.receive(\.channelsLoaded.success) {
            $0.channels = channels
            $0.currentTime = self.testNowEpoch
            $0.windowStart = EPGGuideLayout.snapToHour(self.testNowEpoch - 2 * 3600)
            $0.windowEnd = EPGGuideLayout.snapToHour(self.testNowEpoch + 4 * 3600) + 3600
        }

        await store.receive(\.programsLoaded.success) {
            $0.isLoading = false
            $0.programsByChannel = [:]
            $0.errorMessage = nil
        }
    }

    func testPlaylistSelected_samePlaylist_noOp() async {
        var state = EPGGuideFeature.State()
        state.playlists = [makePlaylist()]
        state.selectedPlaylistID = "pl-1"

        let store = TestStore(initialState: state) {
            EPGGuideFeature()
        }

        await store.send(.playlistSelected("pl-1"))
    }

    // MARK: - Channels Loaded

    func testChannelsLoaded_computesTimeWindowAndFetchesPrograms() async {
        let channels = [makeChannel(id: "ch-1", name: "CNN", epgID: "CNN.us")]
        let programs: [String: [EpgProgramRecord]] = [
            "CNN.us": [makeProgram(id: "p1", channelEpgID: "CNN.us", title: "News", startTime: testNowEpoch, endTime: testNowEpoch + 3600)]
        ]

        var state = EPGGuideFeature.State()
        state.isLoading = true

        let store = TestStore(initialState: state) {
            EPGGuideFeature()
        } withDependencies: {
            $0.epgClient.fetchProgramsBatch = { _, _, _ in programs }
            $0.date = .constant(testNow)
        }

        await store.send(.channelsLoaded(.success(channels))) {
            $0.channels = channels
            $0.currentTime = self.testNowEpoch
            $0.windowStart = EPGGuideLayout.snapToHour(self.testNowEpoch - 2 * 3600)
            $0.windowEnd = EPGGuideLayout.snapToHour(self.testNowEpoch + 4 * 3600) + 3600
        }

        await store.receive(\.programsLoaded.success) {
            $0.isLoading = false
            $0.programsByChannel = programs
            $0.errorMessage = nil
        }
    }

    func testChannelsLoaded_failure_setsError() async {
        var state = EPGGuideFeature.State()
        state.isLoading = true

        let store = TestStore(initialState: state) {
            EPGGuideFeature()
        }

        let error = NSError(domain: "test", code: 42, userInfo: [NSLocalizedDescriptionKey: "Read error"])
        await store.send(.channelsLoaded(.failure(error))) {
            $0.isLoading = false
            $0.errorMessage = "Failed to load channels: Read error"
        }
    }

    func testChannelsLoaded_emptyNoEpgIDs_loadsEmptyPrograms() async {
        let channels = [makeChannel(id: "ch-1", name: "CNN")] // no epgID/tvgID

        var state = EPGGuideFeature.State()
        state.isLoading = true

        let store = TestStore(initialState: state) {
            EPGGuideFeature()
        } withDependencies: {
            $0.date = .constant(testNow)
        }

        await store.send(.channelsLoaded(.success(channels))) {
            $0.channels = channels
            $0.currentTime = self.testNowEpoch
            $0.windowStart = EPGGuideLayout.snapToHour(self.testNowEpoch - 2 * 3600)
            $0.windowEnd = EPGGuideLayout.snapToHour(self.testNowEpoch + 4 * 3600) + 3600
        }

        await store.receive(\.programsLoaded.success) {
            $0.isLoading = false
            $0.programsByChannel = [:]
            $0.errorMessage = nil
        }
    }

    // MARK: - Programs Loaded

    func testProgramsLoaded_storesByChannel() async {
        let programs: [String: [EpgProgramRecord]] = [
            "CNN.us": [makeProgram(id: "p1", channelEpgID: "CNN.us", title: "News", startTime: 1000, endTime: 2000)]
        ]
        var state = EPGGuideFeature.State()
        state.isLoading = true

        let store = TestStore(initialState: state) {
            EPGGuideFeature()
        } withDependencies: {
            $0.date = .constant(testNow)
        }

        await store.send(.programsLoaded(.success(programs))) {
            $0.isLoading = false
            $0.programsByChannel = programs
            $0.errorMessage = nil
        }
    }

    func testProgramsLoaded_failure_setsError() async {
        var state = EPGGuideFeature.State()
        state.isLoading = true

        let store = TestStore(initialState: state) {
            EPGGuideFeature()
        }

        let error = NSError(domain: "test", code: 42, userInfo: [NSLocalizedDescriptionKey: "Query failed"])
        await store.send(.programsLoaded(.failure(error))) {
            $0.isLoading = false
            $0.errorMessage = "Failed to load guide data: Query failed"
        }
    }

    // MARK: - Time Window

    func testWindowStart_snappedToHour() {
        // 12:34:56 should snap to 10:00 (2h back, snap to hour)
        let timestamp = 1740486896 // some mid-hour time
        let twoHoursBack = timestamp - 2 * 3600
        let snapped = EPGGuideLayout.snapToHour(twoHoursBack)
        XCTAssertEqual(snapped % 3600, 0)
    }

    func testScrolledNearEdgeEarlier_extendsWindow() async {
        var state = EPGGuideFeature.State()
        state.windowStart = 10800 // 3:00
        state.windowEnd = 32400  // 9:00
        state.channels = [makeChannel(id: "ch-1", epgID: "CNN.us")]

        let store = TestStore(initialState: state) {
            EPGGuideFeature()
        } withDependencies: {
            $0.epgClient.fetchProgramsBatch = { _, _, _ in [:] }
        }

        await store.send(.scrolledNearEdge(.earlier)) {
            $0.windowStart = 10800 - 3 * 3600 // -2h
        }

        await store.receive(\.additionalProgramsLoaded.success)
    }

    func testScrolledNearEdgeLater_extendsWindow() async {
        var state = EPGGuideFeature.State()
        state.windowStart = 10800
        state.windowEnd = 32400
        state.channels = [makeChannel(id: "ch-1", epgID: "CNN.us")]

        let store = TestStore(initialState: state) {
            EPGGuideFeature()
        } withDependencies: {
            $0.epgClient.fetchProgramsBatch = { _, _, _ in [:] }
        }

        await store.send(.scrolledNearEdge(.later)) {
            $0.windowEnd = 32400 + 3 * 3600
        }

        await store.receive(\.additionalProgramsLoaded.success)
    }

    func testAdditionalProgramsLoaded_mergesWithExisting() async {
        var state = EPGGuideFeature.State()
        state.programsByChannel = [
            "CNN.us": [makeProgram(id: "p1", channelEpgID: "CNN.us", title: "Early", startTime: 1000, endTime: 2000)]
        ]

        let additional: [String: [EpgProgramRecord]] = [
            "CNN.us": [makeProgram(id: "p2", channelEpgID: "CNN.us", title: "Late", startTime: 2000, endTime: 3000)]
        ]

        let store = TestStore(initialState: state) {
            EPGGuideFeature()
        }

        await store.send(.additionalProgramsLoaded(.success(additional))) {
            $0.programsByChannel = [
                "CNN.us": [
                    self.makeProgram(id: "p1", channelEpgID: "CNN.us", title: "Early", startTime: 1000, endTime: 2000),
                    self.makeProgram(id: "p2", channelEpgID: "CNN.us", title: "Late", startTime: 2000, endTime: 3000),
                ]
            ]
        }
    }

    // MARK: - Current Time

    func testCurrentTimeTick_updatesCurrentTime() async {
        let laterDate = Date(timeIntervalSince1970: 1740484860) // 60s later
        var state = EPGGuideFeature.State()
        state.currentTime = testNowEpoch

        let store = TestStore(initialState: state) {
            EPGGuideFeature()
        } withDependencies: {
            $0.date = .constant(laterDate)
        }

        await store.send(.currentTimeTick) {
            $0.currentTime = 1740484860
        }
    }

    // MARK: - Program Tap

    func testProgramTapped_presentsVideoPlayer() async {
        let channel = makeChannel(id: "ch-1", name: "CNN")
        let program = makeProgram(id: "p1", channelEpgID: "CNN.us", title: "News", startTime: 1000, endTime: 2000)

        let store = TestStore(initialState: EPGGuideFeature.State()) {
            EPGGuideFeature()
        }

        await store.send(.programTapped(program, channel)) {
            $0.focusedProgramID = nil
            $0.videoPlayer = VideoPlayerFeature.State(channel: channel)
        }

        await store.receive(\.delegate.playChannel)
    }

    // MARK: - Video Player

    func testVideoPlayerDismissed_nilsState() async {
        let channel = makeChannel(id: "ch-1", name: "CNN")
        var state = EPGGuideFeature.State()
        state.videoPlayer = VideoPlayerFeature.State(channel: channel)

        let store = TestStore(initialState: state) {
            EPGGuideFeature()
        }

        await store.send(.videoPlayer(.presented(.delegate(.dismissed)))) {
            $0.videoPlayer = nil
        }
    }

    // MARK: - Retry

    func testRetryTapped_withPlaylist_reloadsChannels() async {
        let channels = [makeChannel(id: "ch-1")]
        var state = EPGGuideFeature.State()
        state.errorMessage = "Some error"
        state.selectedPlaylistID = "pl-1"

        let store = TestStore(initialState: state) {
            EPGGuideFeature()
        } withDependencies: {
            $0.channelListClient.fetchGroupedChannels = { _ in
                GroupedChannels(groups: ["All"], channelsByGroup: ["All": channels])
            }
            $0.epgClient.fetchProgramsBatch = { _, _, _ in [:] }
            $0.date = .constant(testNow)
        }

        await store.send(.retryTapped) {
            $0.errorMessage = nil
            $0.isLoading = true
        }

        await store.receive(\.channelsLoaded.success) {
            $0.channels = channels
            $0.currentTime = self.testNowEpoch
            $0.windowStart = EPGGuideLayout.snapToHour(self.testNowEpoch - 2 * 3600)
            $0.windowEnd = EPGGuideLayout.snapToHour(self.testNowEpoch + 4 * 3600) + 3600
        }

        await store.receive(\.programsLoaded.success) {
            $0.isLoading = false
            $0.programsByChannel = [:]
            $0.errorMessage = nil
        }
    }

    func testRetryTapped_noPlaylist_reloadsPlaylists() async {
        var state = EPGGuideFeature.State()
        state.errorMessage = "Some error"

        let store = TestStore(initialState: state) {
            EPGGuideFeature()
        } withDependencies: {
            $0.channelListClient.fetchPlaylists = { [] }
        }

        await store.send(.retryTapped) {
            $0.errorMessage = nil
            $0.isLoading = true
        }

        await store.receive(\.playlistsLoaded.success) {
            $0.playlists = []
            $0.isLoading = false
        }
    }

    // MARK: - Has Data

    func testHasData_withChannelsAndPrograms_true() {
        var state = EPGGuideFeature.State()
        state.channels = [makeChannel(id: "ch-1")]
        state.programsByChannel = ["CNN.us": [makeProgram(id: "p1", channelEpgID: "CNN.us", startTime: 1000, endTime: 2000)]]
        XCTAssertTrue(state.hasData)
    }

    func testHasData_noPrograms_false() {
        var state = EPGGuideFeature.State()
        state.channels = [makeChannel(id: "ch-1")]
        XCTAssertFalse(state.hasData)
    }
}
