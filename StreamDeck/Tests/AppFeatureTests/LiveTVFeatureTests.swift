import ComposableArchitecture
import XCTest
import Database
import Repositories
@testable import AppFeature

@MainActor
final class LiveTVFeatureTests: XCTestCase {

    // MARK: - Helpers

    private func makePlaylist(id: String = "pl-1", name: String = "My Playlist") -> PlaylistRecord {
        PlaylistRecord(id: id, name: name, type: "m3u", url: "http://example.com/pl.m3u")
    }

    private func makeChannel(
        id: String,
        playlistID: String = "pl-1",
        name: String = "Channel",
        groupName: String? = nil,
        isFavorite: Bool = false
    ) -> ChannelRecord {
        ChannelRecord(
            id: id,
            playlistID: playlistID,
            name: name,
            groupName: groupName,
            streamURL: "http://example.com/\(id).ts",
            isFavorite: isFavorite
        )
    }

    private func makeGroupedChannels() -> GroupedChannels {
        let news = [
            makeChannel(id: "ch-1", name: "CNN", groupName: "News"),
            makeChannel(id: "ch-2", name: "BBC", groupName: "News"),
        ]
        let sports = [
            makeChannel(id: "ch-3", name: "ESPN", groupName: "Sports"),
        ]
        return GroupedChannels(
            groups: ["News", "Sports"],
            channelsByGroup: ["News": news, "Sports": sports]
        )
    }

    // MARK: - Initial State

    func testInitialState_isEmpty() {
        let state = LiveTVFeature.State()
        XCTAssertTrue(state.playlists.isEmpty)
        XCTAssertNil(state.selectedPlaylistID)
        XCTAssertFalse(state.isLoading)
        XCTAssertTrue(state.groups.isEmpty)
        XCTAssertTrue(state.displayedChannels.isEmpty)
    }

    func testInitialState_defaultGroupIsAll() {
        let state = LiveTVFeature.State()
        XCTAssertEqual(state.selectedGroup, "All")
    }

    // MARK: - On Appear

    func testOnAppear_loadsPlaylistsAndChannels() async {
        let playlist = makePlaylist()
        let grouped = makeGroupedChannels()

        let store = TestStore(initialState: LiveTVFeature.State()) {
            LiveTVFeature()
        } withDependencies: {
            $0.channelListClient.fetchPlaylists = { [playlist] }
            $0.channelListClient.fetchGroupedChannels = { _ in grouped }
        }

        await store.send(.onAppear) {
            $0.isLoading = true
        }

        await store.receive(\.playlistsLoaded.success) {
            $0.playlists = [playlist]
            $0.selectedPlaylistID = "pl-1"
        }

        await store.receive(\.channelsLoaded.success) {
            $0.isLoading = false
            $0.groupedChannels = grouped
            $0.groups = ["All", "News", "Sports"]
            $0.selectedGroup = "All"
            $0.displayedChannels = grouped.allChannels
            $0.errorMessage = nil
        }
    }

    func testOnAppear_noPlaylists_showsEmpty() async {
        let store = TestStore(initialState: LiveTVFeature.State()) {
            LiveTVFeature()
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
        var state = LiveTVFeature.State()
        state.playlists = [makePlaylist()]

        let store = TestStore(initialState: state) {
            LiveTVFeature()
        }

        await store.send(.onAppear)
    }

    // MARK: - Playlist Selection

    func testPlaylistSelected_reloadsChannels() async {
        let grouped = makeGroupedChannels()
        var state = LiveTVFeature.State()
        state.playlists = [makePlaylist(id: "pl-1"), makePlaylist(id: "pl-2", name: "Second")]
        state.selectedPlaylistID = "pl-1"

        let store = TestStore(initialState: state) {
            LiveTVFeature()
        } withDependencies: {
            $0.channelListClient.fetchGroupedChannels = { _ in grouped }
        }

        await store.send(.playlistSelected("pl-2")) {
            $0.selectedPlaylistID = "pl-2"
            $0.searchQuery = ""
            $0.searchResults = nil
            $0.isLoading = true
        }

        await store.receive(\.channelsLoaded.success) {
            $0.isLoading = false
            $0.groupedChannels = grouped
            $0.groups = ["All", "News", "Sports"]
            $0.selectedGroup = "All"
            $0.displayedChannels = grouped.allChannels
            $0.errorMessage = nil
        }
    }

    func testPlaylistSelected_samePlaylist_noOp() async {
        var state = LiveTVFeature.State()
        state.playlists = [makePlaylist()]
        state.selectedPlaylistID = "pl-1"

        let store = TestStore(initialState: state) {
            LiveTVFeature()
        }

        await store.send(.playlistSelected("pl-1"))
    }

    // MARK: - Group Filtering

    func testGroupSelected_all_showsAllChannels() async {
        let grouped = makeGroupedChannels()
        var state = LiveTVFeature.State()
        state.groupedChannels = grouped
        state.groups = ["All", "News", "Sports"]
        state.selectedGroup = "News"
        state.displayedChannels = grouped.channelsByGroup["News"]!

        let store = TestStore(initialState: state) {
            LiveTVFeature()
        }

        await store.send(.groupSelected("All")) {
            $0.selectedGroup = "All"
            $0.displayedChannels = grouped.allChannels
        }
    }

    func testGroupSelected_specificGroup_filtersChannels() async {
        let grouped = makeGroupedChannels()
        var state = LiveTVFeature.State()
        state.groupedChannels = grouped
        state.groups = ["All", "News", "Sports"]
        state.displayedChannels = grouped.allChannels

        let store = TestStore(initialState: state) {
            LiveTVFeature()
        }

        await store.send(.groupSelected("Sports")) {
            $0.selectedGroup = "Sports"
            $0.displayedChannels = grouped.channelsByGroup["Sports"]!
        }
    }

    func testGroupSelected_nonexistentGroup_showsEmpty() async {
        let grouped = makeGroupedChannels()
        var state = LiveTVFeature.State()
        state.groupedChannels = grouped
        state.groups = ["All", "News", "Sports"]
        state.displayedChannels = grouped.allChannels

        let store = TestStore(initialState: state) {
            LiveTVFeature()
        }

        await store.send(.groupSelected("Movies")) {
            $0.selectedGroup = "Movies"
            $0.displayedChannels = []
        }
    }

    // MARK: - Search

    func testSearchQueryChanged_triggersSearch() async {
        let searchResults = [makeChannel(id: "ch-1", name: "CNN", groupName: "News")]
        var state = LiveTVFeature.State()
        state.selectedPlaylistID = "pl-1"

        let store = TestStore(initialState: state) {
            LiveTVFeature()
        } withDependencies: {
            $0.channelListClient.searchChannels = { _, _ in searchResults }
        }

        await store.send(.searchQueryChanged("CNN")) {
            $0.searchQuery = "CNN"
        }

        await store.receive(\.searchResultsLoaded.success) {
            $0.searchResults = searchResults
            $0.displayedChannels = searchResults
        }
    }

    func testSearchQueryChanged_emptyClearsAndRestoresGroup() async {
        let grouped = makeGroupedChannels()
        var state = LiveTVFeature.State()
        state.groupedChannels = grouped
        state.groups = ["All", "News", "Sports"]
        state.selectedGroup = "News"
        state.searchQuery = "CNN"
        state.searchResults = [makeChannel(id: "ch-1", name: "CNN", groupName: "News")]
        state.displayedChannels = state.searchResults!

        let store = TestStore(initialState: state) {
            LiveTVFeature()
        }

        await store.send(.searchQueryChanged("")) {
            $0.searchQuery = ""
            $0.searchResults = nil
        }

        await store.receive(\.groupSelected) {
            $0.selectedGroup = "News"
            $0.displayedChannels = grouped.channelsByGroup["News"]!
        }
    }

    func testSearchResultsLoaded_failure_showsEmpty() async {
        let store = TestStore(initialState: LiveTVFeature.State()) {
            LiveTVFeature()
        }

        await store.send(.searchResultsLoaded(.failure(NSError(domain: "", code: 0)))) {
            $0.searchResults = []
            $0.displayedChannels = []
        }
    }

    // MARK: - Channel Tap

    func testChannelTapped_setsFocusAndDelegates() async {
        let channel = makeChannel(id: "ch-1", name: "CNN")

        let store = TestStore(initialState: LiveTVFeature.State()) {
            LiveTVFeature()
        }

        await store.send(.channelTapped(channel)) {
            $0.focusedChannelID = "ch-1"
            $0.videoPlayer = VideoPlayerFeature.State(channel: channel)
        }

        await store.receive(\.delegate.playChannel)
    }

    // MARK: - Favorites Toggle

    func testToggleFavoriteTapped_togglesInDisplayedChannels() async {
        let channel = makeChannel(id: "ch-1", name: "CNN", groupName: "News")
        let grouped = GroupedChannels(
            groups: ["News"],
            channelsByGroup: ["News": [channel]]
        )
        var state = LiveTVFeature.State()
        state.groupedChannels = grouped
        state.displayedChannels = [channel]

        let store = TestStore(initialState: state) {
            LiveTVFeature()
        } withDependencies: {
            $0.channelListClient.toggleFavorite = { _ in }
            $0.cloudKitSyncClient.pushFavorite = { _, _, _ in }
        }

        await store.send(.toggleFavoriteTapped("ch-1"))

        await store.receive(\.favoriteToggled.success) {
            $0.displayedChannels[0].isFavorite = true
            $0.groupedChannels = GroupedChannels(
                groups: ["News"],
                channelsByGroup: ["News": [ChannelRecord(
                    id: "ch-1",
                    playlistID: "pl-1",
                    name: "CNN",
                    groupName: "News",
                    streamURL: "http://example.com/ch-1.ts",
                    isFavorite: true
                )]]
            )
        }
    }

    func testToggleFavoriteTapped_failure_noStateChange() async {
        var state = LiveTVFeature.State()
        state.displayedChannels = [makeChannel(id: "ch-1", name: "CNN")]

        let store = TestStore(initialState: state) {
            LiveTVFeature()
        } withDependencies: {
            $0.channelListClient.toggleFavorite = { _ in throw NSError(domain: "", code: 0) }
        }

        await store.send(.toggleFavoriteTapped("ch-1"))
        await store.receive(\.favoriteToggled.failure)
    }

    // MARK: - Error Handling

    func testPlaylistsLoaded_failure_setsError() async {
        var state = LiveTVFeature.State()
        state.isLoading = true

        let store = TestStore(initialState: state) {
            LiveTVFeature()
        }

        let error = NSError(domain: "test", code: 42, userInfo: [NSLocalizedDescriptionKey: "DB error"])
        await store.send(.playlistsLoaded(.failure(error))) {
            $0.isLoading = false
            $0.errorMessage = "Failed to load playlists: DB error"
        }
    }

    func testChannelsLoaded_failure_setsError() async {
        var state = LiveTVFeature.State()
        state.isLoading = true

        let store = TestStore(initialState: state) {
            LiveTVFeature()
        }

        let error = NSError(domain: "test", code: 42, userInfo: [NSLocalizedDescriptionKey: "Read error"])
        await store.send(.channelsLoaded(.failure(error))) {
            $0.isLoading = false
            $0.errorMessage = "Failed to load channels: Read error"
        }
    }

    func testRetryTapped_withPlaylist_reloadsChannels() async {
        let grouped = makeGroupedChannels()
        var state = LiveTVFeature.State()
        state.errorMessage = "Some error"
        state.selectedPlaylistID = "pl-1"

        let store = TestStore(initialState: state) {
            LiveTVFeature()
        } withDependencies: {
            $0.channelListClient.fetchGroupedChannels = { _ in grouped }
        }

        await store.send(.retryTapped) {
            $0.errorMessage = nil
            $0.isLoading = true
        }

        await store.receive(\.channelsLoaded.success) {
            $0.isLoading = false
            $0.groupedChannels = grouped
            $0.groups = ["All", "News", "Sports"]
            $0.selectedGroup = "All"
            $0.displayedChannels = grouped.allChannels
            $0.errorMessage = nil
        }
    }

    func testRetryTapped_noPlaylist_reloadsPlaylists() async {
        var state = LiveTVFeature.State()
        state.errorMessage = "Some error"

        let store = TestStore(initialState: state) {
            LiveTVFeature()
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

    // MARK: - Channels Loaded

    func testChannelsLoaded_populatesGroupsWithAllPrefix() async {
        let grouped = GroupedChannels(
            groups: ["Entertainment", "News"],
            channelsByGroup: [
                "Entertainment": [makeChannel(id: "ch-1", name: "HBO", groupName: "Entertainment")],
                "News": [makeChannel(id: "ch-2", name: "CNN", groupName: "News")],
            ]
        )
        var state = LiveTVFeature.State()
        state.isLoading = true

        let store = TestStore(initialState: state) {
            LiveTVFeature()
        }

        await store.send(.channelsLoaded(.success(grouped))) {
            $0.isLoading = false
            $0.groupedChannels = grouped
            $0.groups = ["All", "Entertainment", "News"]
            $0.selectedGroup = "All"
            $0.displayedChannels = grouped.allChannels
            $0.errorMessage = nil
        }
    }

    func testChannelsLoaded_clearsExistingError() async {
        var state = LiveTVFeature.State()
        state.isLoading = true
        state.errorMessage = "Previous error"

        let grouped = GroupedChannels(groups: [], channelsByGroup: [:])

        let store = TestStore(initialState: state) {
            LiveTVFeature()
        }

        await store.send(.channelsLoaded(.success(grouped))) {
            $0.isLoading = false
            $0.groupedChannels = grouped
            $0.groups = ["All"]
            $0.selectedGroup = "All"
            $0.displayedChannels = []
            $0.errorMessage = nil
        }
    }

    // MARK: - Pull to Refresh

    func testRefreshTapped_resetsAndReloads() async {
        let playlist = makePlaylist()
        let grouped = makeGroupedChannels()
        var state = LiveTVFeature.State()
        state.playlists = [playlist]
        state.selectedPlaylistID = "pl-1"
        state.groupedChannels = grouped
        state.groups = ["All", "News", "Sports"]
        state.displayedChannels = grouped.allChannels

        let store = TestStore(initialState: state) {
            LiveTVFeature()
        } withDependencies: {
            $0.channelListClient.fetchPlaylists = { [playlist] }
            $0.channelListClient.fetchGroupedChannels = { _ in GroupedChannels(groups: [], channelsByGroup: [:]) }
        }
        store.exhaustivity = .off

        await store.send(.refreshTapped) {
            $0.playlists = []
            $0.groupedChannels = nil
            $0.groups = []
            $0.selectedGroup = "All"
            $0.displayedChannels = []
            $0.searchQuery = ""
            $0.searchResults = nil
            $0.nowPlaying = [:]
            $0.errorMessage = nil
            $0.isLoading = true
        }
        await store.skipReceivedActions()
    }

    func testRefreshTapped_bypassesOnAppearGuard() async {
        let playlist = makePlaylist()
        var state = LiveTVFeature.State()
        state.playlists = [playlist]

        let loadCalled = LockIsolated(false)
        let store = TestStore(initialState: state) {
            LiveTVFeature()
        } withDependencies: {
            $0.channelListClient.fetchPlaylists = {
                loadCalled.setValue(true)
                return [playlist]
            }
            $0.channelListClient.fetchGroupedChannels = { _ in GroupedChannels(groups: [], channelsByGroup: [:]) }
        }
        store.exhaustivity = .off

        // onAppear should be a no-op since playlists are loaded
        await store.send(.onAppear)
        XCTAssertFalse(loadCalled.value)

        // refreshTapped should reload
        await store.send(.refreshTapped) {
            $0.playlists = []
            $0.groupedChannels = nil
            $0.groups = []
            $0.selectedGroup = "All"
            $0.displayedChannels = []
            $0.searchQuery = ""
            $0.searchResults = nil
            $0.nowPlaying = [:]
            $0.errorMessage = nil
            $0.isLoading = true
        }
        await store.skipReceivedActions()
        XCTAssertTrue(loadCalled.value)
    }

    // MARK: - Channel Switcher Delegate

    func testChannelSwitched_updatesFocusedChannel() async {
        let channel = makeChannel(id: "ch-1", name: "CNN")
        var state = LiveTVFeature.State()
        state.videoPlayer = VideoPlayerFeature.State(channel: channel)
        state.focusedChannelID = "ch-old"

        let newChannel = makeChannel(id: "ch-2", name: "BBC")

        let store = TestStore(initialState: state) {
            LiveTVFeature()
        }

        await store.send(.videoPlayer(.presented(.delegate(.channelSwitched(newChannel))))) {
            $0.focusedChannelID = "ch-2"
        }
    }
}
