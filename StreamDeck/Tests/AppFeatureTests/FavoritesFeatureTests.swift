import ComposableArchitecture
import XCTest
import Database
@testable import AppFeature

@MainActor
final class FavoritesFeatureTests: XCTestCase {

    // MARK: - Helpers

    private func makeChannel(
        id: String,
        name: String = "Channel",
        isFavorite: Bool = true
    ) -> ChannelRecord {
        ChannelRecord(
            id: id,
            playlistID: "pl-1",
            name: name,
            streamURL: "http://example.com/\(id).ts",
            isFavorite: isFavorite
        )
    }

    // MARK: - Initial State

    func testInitialState_isEmpty() {
        let state = FavoritesFeature.State()
        XCTAssertTrue(state.channels.isEmpty)
        XCTAssertFalse(state.isLoading)
        XCTAssertNil(state.focusedChannelID)
    }

    // MARK: - On Appear

    func testOnAppear_loadsFavorites() async {
        let favorites = [
            makeChannel(id: "ch-1", name: "CNN"),
            makeChannel(id: "ch-2", name: "ESPN"),
        ]

        let store = TestStore(initialState: FavoritesFeature.State()) {
            FavoritesFeature()
        } withDependencies: {
            $0.channelListClient.fetchFavorites = { favorites }
        }

        await store.send(.onAppear) {
            $0.isLoading = true
        }

        await store.receive(\.channelsLoaded.success) {
            $0.isLoading = false
            $0.channels = favorites
        }
    }

    func testOnAppear_noFavorites_emptyList() async {
        let store = TestStore(initialState: FavoritesFeature.State()) {
            FavoritesFeature()
        } withDependencies: {
            $0.channelListClient.fetchFavorites = { [] }
        }

        await store.send(.onAppear) {
            $0.isLoading = true
        }

        await store.receive(\.channelsLoaded.success) {
            $0.isLoading = false
            $0.channels = []
        }
    }

    // MARK: - Channel Tap

    func testChannelTapped_delegatesPlayChannel() async {
        let channel = makeChannel(id: "ch-1", name: "CNN")

        let store = TestStore(initialState: FavoritesFeature.State()) {
            FavoritesFeature()
        }

        await store.send(.channelTapped(channel)) {
            $0.focusedChannelID = "ch-1"
            $0.videoPlayer = VideoPlayerFeature.State(channel: channel)
        }

        await store.receive(\.delegate.playChannel)
    }

    // MARK: - Unfavorite

    func testToggleFavoriteTapped_removesFromList() async {
        var state = FavoritesFeature.State()
        state.channels = [
            makeChannel(id: "ch-1", name: "CNN"),
            makeChannel(id: "ch-2", name: "ESPN"),
        ]

        let store = TestStore(initialState: state) {
            FavoritesFeature()
        } withDependencies: {
            $0.channelListClient.toggleFavorite = { _ in }
        }

        await store.send(.toggleFavoriteTapped("ch-1"))

        await store.receive(\.favoriteToggled.success) {
            $0.channels = [ChannelRecord(
                id: "ch-2",
                playlistID: "pl-1",
                name: "ESPN",
                streamURL: "http://example.com/ch-2.ts",
                isFavorite: true
            )]
        }
    }

    func testToggleFavoriteTapped_failure_noStateChange() async {
        var state = FavoritesFeature.State()
        state.channels = [makeChannel(id: "ch-1", name: "CNN")]

        let store = TestStore(initialState: state) {
            FavoritesFeature()
        } withDependencies: {
            $0.channelListClient.toggleFavorite = { _ in throw NSError(domain: "", code: 0) }
        }

        await store.send(.toggleFavoriteTapped("ch-1"))
        await store.receive(\.favoriteToggled.failure)
    }

    // MARK: - Reload

    func testOnAppear_alwaysReloads() async {
        var state = FavoritesFeature.State()
        state.channels = [makeChannel(id: "ch-1", name: "CNN")]

        let store = TestStore(initialState: state) {
            FavoritesFeature()
        } withDependencies: {
            $0.channelListClient.fetchFavorites = { [] }
        }

        await store.send(.onAppear) {
            $0.isLoading = true
        }

        await store.receive(\.channelsLoaded.success) {
            $0.isLoading = false
            $0.channels = []
        }
    }

    func testChannelsLoaded_failure_stopsLoading() async {
        var state = FavoritesFeature.State()
        state.isLoading = true

        let store = TestStore(initialState: state) {
            FavoritesFeature()
        }

        await store.send(.channelsLoaded(.failure(NSError(domain: "", code: 0)))) {
            $0.isLoading = false
        }
    }
}
