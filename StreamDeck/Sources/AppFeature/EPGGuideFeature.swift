import ComposableArchitecture
import Database
import Repositories
import SwiftUI

@Reducer
public struct EPGGuideFeature {

    @ObservableState
    public struct State: Equatable, Sendable {
        public var playlists: [PlaylistRecord] = []
        public var selectedPlaylistID: String?
        public var channels: [ChannelRecord] = []
        public var programsByChannel: [String: [EpgProgramRecord]] = [:]

        public var windowStart: Int = 0
        public var windowEnd: Int = 0
        public var currentTime: Int = 0

        public var isLoading: Bool = false
        public var errorMessage: String?
        public var focusedProgramID: String?

        @Presents public var videoPlayer: VideoPlayerFeature.State?

        public var hasData: Bool { !channels.isEmpty && !programsByChannel.isEmpty }

        public init() {}
    }

    public enum Action: Sendable {
        case onAppear
        case playlistsLoaded(Result<[PlaylistRecord], Error>)
        case playlistSelected(String)
        case channelsLoaded(Result<[ChannelRecord], Error>)
        case programsLoaded(Result<[String: [EpgProgramRecord]], Error>)
        case currentTimeTick
        case scrolledNearEdge(TimeDirection)
        case additionalProgramsLoaded(Result<[String: [EpgProgramRecord]], Error>)
        case programTapped(EpgProgramRecord, ChannelRecord)
        case refreshTapped
        case retryTapped
        case videoPlayer(PresentationAction<VideoPlayerFeature.Action>)
        case delegate(Delegate)

        @CasePathable
        public enum Delegate: Sendable, Equatable {
            case playChannel(ChannelRecord)
        }
    }

    public enum TimeDirection: Sendable, Equatable {
        case earlier
        case later
    }

    @Dependency(\.channelListClient) var channelListClient
    @Dependency(\.epgClient) var epgClient
    @Dependency(\.date.now) var now

    public init() {}

    public var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .videoPlayer(.presented(.delegate(.dismissed))):
                state.videoPlayer = nil
                return .none

            case .videoPlayer:
                return .none

            case .onAppear:
                guard state.playlists.isEmpty else { return .none }
                return loadPlaylists(&state)

            case .refreshTapped:
                state.playlists = []
                state.channels = []
                state.programsByChannel = [:]
                state.windowStart = 0
                state.windowEnd = 0
                state.errorMessage = nil
                return loadPlaylists(&state)

            case let .playlistsLoaded(.success(playlists)):
                state.playlists = playlists
                if let first = playlists.first {
                    state.selectedPlaylistID = first.id
                    var effects: [Effect<Action>] = [loadChannels(playlistID: first.id)]
                    if first.epgURL != nil {
                        effects.append(syncEPG(playlistID: first.id))
                    }
                    return .merge(effects)
                }
                state.isLoading = false
                return .none

            case let .playlistsLoaded(.failure(error)):
                state.isLoading = false
                state.errorMessage = "Failed to load playlists: \(error.localizedDescription)"
                return .none

            case let .playlistSelected(playlistID):
                guard playlistID != state.selectedPlaylistID else { return .none }
                state.selectedPlaylistID = playlistID
                state.isLoading = true
                state.programsByChannel = [:]
                return loadChannels(playlistID: playlistID)

            case let .channelsLoaded(.success(channels)):
                state.channels = channels
                let nowEpoch = Int(now.timeIntervalSince1970)
                state.currentTime = nowEpoch
                state.windowStart = EPGGuideLayout.snapToHour(nowEpoch - 2 * 3600)
                state.windowEnd = EPGGuideLayout.snapToHour(nowEpoch + 4 * 3600) + 3600
                return fetchPrograms(
                    channels: channels,
                    from: state.windowStart,
                    to: state.windowEnd
                )

            case let .channelsLoaded(.failure(error)):
                state.isLoading = false
                state.errorMessage = "Failed to load channels: \(error.localizedDescription)"
                return .none

            case let .programsLoaded(.success(programs)):
                state.isLoading = false
                state.programsByChannel = programs
                state.errorMessage = nil
                return .none

            case let .programsLoaded(.failure(error)):
                state.isLoading = false
                state.errorMessage = "Failed to load guide data: \(error.localizedDescription)"
                return .none

            case .currentTimeTick:
                state.currentTime = Int(now.timeIntervalSince1970)
                return .none

            case let .scrolledNearEdge(direction):
                switch direction {
                case .earlier:
                    let newStart = state.windowStart - 3 * 3600
                    let oldStart = state.windowStart
                    state.windowStart = newStart
                    return fetchAdditionalPrograms(
                        channels: state.channels,
                        from: newStart,
                        to: oldStart
                    )
                case .later:
                    let oldEnd = state.windowEnd
                    let newEnd = state.windowEnd + 3 * 3600
                    state.windowEnd = newEnd
                    return fetchAdditionalPrograms(
                        channels: state.channels,
                        from: oldEnd,
                        to: newEnd
                    )
                }

            case let .additionalProgramsLoaded(.success(additional)):
                for (channelID, programs) in additional {
                    var existing = state.programsByChannel[channelID] ?? []
                    existing.append(contentsOf: programs)
                    existing.sort { $0.startTime < $1.startTime }
                    // Deduplicate by ID
                    var seen = Set<String>()
                    existing = existing.filter { seen.insert($0.id).inserted }
                    state.programsByChannel[channelID] = existing
                }
                return .none

            case .additionalProgramsLoaded(.failure):
                return .none

            case let .programTapped(_, channel):
                state.focusedProgramID = nil
                state.videoPlayer = VideoPlayerFeature.State(channel: channel)
                return .send(.delegate(.playChannel(channel)))

            case .retryTapped:
                state.errorMessage = nil
                state.isLoading = true
                if let playlistID = state.selectedPlaylistID {
                    return loadChannels(playlistID: playlistID)
                }
                let client = channelListClient
                return .run { send in
                    let playlists = try await client.fetchPlaylists()
                    await send(.playlistsLoaded(.success(playlists)))
                } catch: { error, send in
                    await send(.playlistsLoaded(.failure(error)))
                }

            case .delegate:
                return .none
            }
        }
        .ifLet(\.$videoPlayer, action: \.videoPlayer) {
            VideoPlayerFeature()
        }
    }

    // MARK: - Helpers

    private func loadPlaylists(_ state: inout State) -> Effect<Action> {
        state.isLoading = true
        let client = channelListClient
        return .run { send in
            let playlists = try await client.fetchPlaylists()
            await send(.playlistsLoaded(.success(playlists)))
        } catch: { error, send in
            await send(.playlistsLoaded(.failure(error)))
        }
    }

    private func loadChannels(playlistID: String) -> Effect<Action> {
        let client = channelListClient
        return .run { send in
            let grouped = try await client.fetchGroupedChannels(playlistID)
            await send(.channelsLoaded(.success(grouped.allChannels)))
        } catch: { error, send in
            await send(.channelsLoaded(.failure(error)))
        }
    }

    private func fetchPrograms(
        channels: [ChannelRecord],
        from: Int,
        to: Int
    ) -> Effect<Action> {
        let epgIDs = channels.compactMap { $0.epgID ?? $0.tvgID }
        guard !epgIDs.isEmpty else {
            return .send(.programsLoaded(.success([:])))
        }
        let client = epgClient
        return .run { send in
            let programs = try await client.fetchProgramsBatch(epgIDs, from, to)
            await send(.programsLoaded(.success(programs)))
        } catch: { error, send in
            await send(.programsLoaded(.failure(error)))
        }
    }

    private func fetchAdditionalPrograms(
        channels: [ChannelRecord],
        from: Int,
        to: Int
    ) -> Effect<Action> {
        let epgIDs = channels.compactMap { $0.epgID ?? $0.tvgID }
        guard !epgIDs.isEmpty else { return .none }
        let client = epgClient
        return .run { send in
            let programs = try await client.fetchProgramsBatch(epgIDs, from, to)
            await send(.additionalProgramsLoaded(.success(programs)))
        } catch: { error, send in
            await send(.additionalProgramsLoaded(.failure(error)))
        }
    }

    private func syncEPG(playlistID: String) -> Effect<Action> {
        let client = epgClient
        return .run { _ in
            _ = try? await client.syncEPG(playlistID)
        }
    }
}
