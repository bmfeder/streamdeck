import ComposableArchitecture
import Database
import Foundation

@Reducer
public struct VideoPlayerFeature {

    @ObservableState
    public struct State: Equatable, Sendable {
        public var item: PlayableItem
        public var isLiveChannel: Bool
        public var status: PlaybackStatus = .idle
        public var activeEngine: PlayerEngine?
        public var streamRoute: StreamRoute?
        public var playerCommand: PlayerCommand = .none
        public var retryCount: Int = 0
        public var hasTriedFallbackEngine: Bool = false
        public var isOverlayVisible: Bool = true

        // Watch progress
        public var resumePositionMs: Int?
        public var currentPositionMs: Int = 0
        public var currentDurationMs: Int?

        // Channel switcher
        public var isSwitcherVisible: Bool = false
        public var switcherChannels: [ChannelRecord] = []
        public var switcherNowPlaying: [String: String] = [:]

        // Sleep timer
        public var sleepTimerEndDate: Date?
        public var sleepTimerMinutesRemaining: Int?
        public var isSleepTimerPickerVisible: Bool = false

        // Channel number entry
        public var numberEntryDigits: String = ""
        public var isNumberEntryVisible: Bool = false
        public var numberEntryResult: NumberEntryResult?

        // Buffering feedback
        public var bufferingElapsedSeconds: Int = 0

        public static let maxRetriesPerEngine: Int = 3

        public init(channel: ChannelRecord) {
            self.item = PlayableItem(channel: channel)
            self.isLiveChannel = true
        }

        public init(vodItem: VodItemRecord) {
            self.item = PlayableItem(vodItem: vodItem)
            self.isLiveChannel = false
        }

        public init(item: PlayableItem, isLiveChannel: Bool = false) {
            self.item = item
            self.isLiveChannel = isLiveChannel
        }
    }

    public enum NumberEntryResult: Equatable, Sendable {
        case searching
        case found(ChannelRecord)
        case notFound
    }

    public enum Action: Sendable {
        case onAppear
        case onDisappear
        case dismissTapped
        case streamRouted(StreamRoute)
        case playerStatusChanged(PlaybackStatus)
        case playerEncounteredError(PlayerError)
        case retryTapped
        case tryAlternateEngineTapped
        case toggleOverlayTapped
        case overlayAutoHideExpired
        case retryTimerFired(attempt: Int, engine: PlayerEngine)
        // Watch progress
        case progressLoaded(WatchProgressRecord?)
        case timeUpdated(positionMs: Int, durationMs: Int?)
        case saveProgress
        // Channel switcher
        case showSwitcher
        case hideSwitcher
        case switcherChannelsLoaded(Result<[ChannelRecord], Error>)
        case switcherEPGLoaded(Result<[String: String], Error>)
        case switcherChannelSelected(ChannelRecord)
        case switcherAutoHideExpired
        // Sleep timer
        case sleepTimerButtonTapped
        case sleepTimerSelected(minutes: Int?)
        case sleepTimerTick
        case sleepTimerFired
        // Channel number entry
        case numberDigitPressed(String)
        case numberEntryAutoHideExpired
        case numberEntryLookupResult(ChannelRecord?)
        case numberEntryConfirmed
        case numberEntryCancelled
        // Buffering feedback
        case bufferingTimerTick
        case delegate(Delegate)

        @CasePathable
        public enum Delegate: Sendable, Equatable {
            case dismissed
            case channelSwitched(ChannelRecord)
        }
    }

    @Dependency(\.streamRouterClient) var streamRouterClient
    @Dependency(\.watchProgressClient) var watchProgressClient
    @Dependency(\.channelListClient) var channelListClient
    @Dependency(\.epgClient) var epgClient
    @Dependency(\.continuousClock) var clock
    @Dependency(\.dismiss) var dismiss

    public init() {}

    private enum CancelID {
        case overlayTimer
        case retryTimer
        case progressTimer
        case switcherTimer
        case sleepTimer
        case sleepTimerTick
        case numberEntryTimer
        case bufferingTimer
    }

    public var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .onAppear:
                guard state.status == .idle else { return .none }
                guard let url = URL(string: state.item.streamURL),
                      let scheme = url.scheme?.lowercased(),
                      scheme == "http" || scheme == "https" || scheme == "rtsp" || scheme == "rtmp" || scheme == "mms" else {
                    state.status = .error(.streamUnavailable)
                    return .none
                }
                state.status = .routing
                let client = streamRouterClient
                let progressClient = watchProgressClient
                let contentID = state.item.contentID
                return .merge(
                    .run { send in
                        let route = await client.route(url)
                        await send(.streamRouted(route))
                    },
                    .run { send in
                        let progress = try? await progressClient.getProgress(contentID)
                        await send(.progressLoaded(progress))
                    }
                )

            case .onDisappear:
                let saveEffect = saveProgressEffect(state: state)
                state.playerCommand = .stop
                return .merge(
                    saveEffect,
                    .cancel(id: CancelID.overlayTimer),
                    .cancel(id: CancelID.retryTimer),
                    .cancel(id: CancelID.progressTimer),
                    .cancel(id: CancelID.switcherTimer),
                    .cancel(id: CancelID.sleepTimer),
                    .cancel(id: CancelID.sleepTimerTick),
                    .cancel(id: CancelID.numberEntryTimer),
                    .cancel(id: CancelID.bufferingTimer)
                )

            case .dismissTapped:
                let saveEffect = saveProgressEffect(state: state)
                state.playerCommand = .stop
                return .merge(
                    saveEffect,
                    .run { send in
                        await send(.delegate(.dismissed))
                    }
                )

            case let .streamRouted(route):
                state.streamRoute = route
                state.activeEngine = route.recommendedEngine
                state.status = .loading
                state.bufferingElapsedSeconds = 0
                state.playerCommand = .play(url: route.url, engine: route.recommendedEngine)
                return .merge(
                    startOverlayTimer(),
                    startBufferingTimer()
                )

            case let .playerStatusChanged(status):
                state.status = status
                if status == .playing {
                    state.retryCount = 0
                    state.bufferingElapsedSeconds = 0
                    return .merge(
                        startProgressTimer(),
                        .cancel(id: CancelID.bufferingTimer)
                    )
                }
                return .none

            case .playerEncounteredError:
                let attempt = state.retryCount + 1
                let engine = state.activeEngine ?? .avPlayer
                let retryClock = clock

                if attempt <= State.maxRetriesPerEngine {
                    state.retryCount = attempt
                    state.status = .retrying(attempt: attempt, engine: engine)
                    state.playerCommand = .stop
                    let delay = retryDelay(attempt: attempt)
                    return .run { send in
                        try await retryClock.sleep(for: delay)
                        await send(.retryTimerFired(attempt: attempt, engine: engine))
                    }
                    .cancellable(id: CancelID.retryTimer, cancelInFlight: true)
                } else if !state.hasTriedFallbackEngine {
                    // Switch to alternate engine
                    let fallback = alternateEngine(for: engine)
                    state.hasTriedFallbackEngine = true
                    state.activeEngine = fallback
                    state.retryCount = 1
                    state.status = .retrying(attempt: 1, engine: fallback)
                    state.playerCommand = .stop
                    let delay = retryDelay(attempt: 1)
                    return .run { send in
                        try await retryClock.sleep(for: delay)
                        await send(.retryTimerFired(attempt: 1, engine: fallback))
                    }
                    .cancellable(id: CancelID.retryTimer, cancelInFlight: true)
                } else {
                    state.status = .failed
                    state.playerCommand = .stop
                    return .none
                }

            case let .retryTimerFired(_, engine):
                guard let url = state.streamRoute?.url else {
                    state.status = .failed
                    return .none
                }
                state.status = .loading
                state.playerCommand = .play(url: url, engine: engine)
                return .none

            case .retryTapped:
                state.retryCount = 0
                state.hasTriedFallbackEngine = false
                let engine = state.streamRoute?.recommendedEngine ?? .avPlayer
                state.activeEngine = engine
                guard let url = state.streamRoute?.url else {
                    state.status = .failed
                    return .none
                }
                state.status = .loading
                state.playerCommand = .play(url: url, engine: engine)
                return .cancel(id: CancelID.retryTimer)

            case .tryAlternateEngineTapped:
                let current = state.activeEngine ?? .avPlayer
                let alt = alternateEngine(for: current)
                state.activeEngine = alt
                state.retryCount = 0
                state.hasTriedFallbackEngine = true
                guard let url = state.streamRoute?.url else {
                    state.status = .failed
                    return .none
                }
                state.status = .loading
                state.playerCommand = .play(url: url, engine: alt)
                return .cancel(id: CancelID.retryTimer)

            case .toggleOverlayTapped:
                state.isOverlayVisible.toggle()
                if state.isOverlayVisible {
                    return startOverlayTimer()
                }
                return .cancel(id: CancelID.overlayTimer)

            case .overlayAutoHideExpired:
                if state.status == .playing && !state.isSleepTimerPickerVisible {
                    state.isOverlayVisible = false
                }
                return .none

            // MARK: - Watch Progress

            case let .progressLoaded(record):
                if let record, record.positionMs > 10_000 {
                    state.resumePositionMs = record.positionMs
                }
                if let duration = record?.durationMs {
                    state.currentDurationMs = duration
                }
                return .none

            case let .timeUpdated(positionMs, durationMs):
                state.currentPositionMs = positionMs
                if let durationMs {
                    state.currentDurationMs = durationMs
                }
                return .none

            case .saveProgress:
                return saveProgressEffect(state: state)

            // MARK: - Channel Switcher

            case .showSwitcher:
                guard state.isLiveChannel else { return .none }
                state.isSwitcherVisible = true
                state.isOverlayVisible = false
                let client = channelListClient
                return .merge(
                    .cancel(id: CancelID.overlayTimer),
                    .run { send in
                        let favorites = try await client.fetchFavorites()
                        await send(.switcherChannelsLoaded(.success(favorites)))
                    } catch: { error, send in
                        await send(.switcherChannelsLoaded(.failure(error)))
                    },
                    startSwitcherTimer()
                )

            case .hideSwitcher:
                state.isSwitcherVisible = false
                state.switcherChannels = []
                state.switcherNowPlaying = [:]
                return .cancel(id: CancelID.switcherTimer)

            case let .switcherChannelsLoaded(.success(channels)):
                state.switcherChannels = channels
                let epgIDs = channels.compactMap { $0.epgID ?? $0.tvgID }
                guard !epgIDs.isEmpty else { return .none }
                let epg = epgClient
                return .run { send in
                    let programs = try await epg.fetchNowPlayingBatch(epgIDs)
                    let nowPlaying = programs.mapValues { $0.title }
                    await send(.switcherEPGLoaded(.success(nowPlaying)))
                } catch: { error, send in
                    await send(.switcherEPGLoaded(.failure(error)))
                }

            case .switcherChannelsLoaded(.failure):
                return .none

            case let .switcherEPGLoaded(.success(nowPlaying)):
                state.switcherNowPlaying = nowPlaying
                return .none

            case .switcherEPGLoaded(.failure):
                return .none

            case let .switcherChannelSelected(channel):
                guard channel.id != state.item.contentID else {
                    return .send(.hideSwitcher)
                }
                let saveEffect = saveProgressEffect(state: state)
                // Reset playback state for new channel
                state.item = PlayableItem(channel: channel)
                state.status = .idle
                state.activeEngine = nil
                state.streamRoute = nil
                state.playerCommand = .stop
                state.retryCount = 0
                state.hasTriedFallbackEngine = false
                state.resumePositionMs = nil
                state.currentPositionMs = 0
                state.currentDurationMs = nil
                state.isSwitcherVisible = false
                state.switcherChannels = []
                state.switcherNowPlaying = [:]
                return .merge(
                    saveEffect,
                    .cancel(id: CancelID.switcherTimer),
                    .cancel(id: CancelID.retryTimer),
                    .cancel(id: CancelID.progressTimer),
                    .send(.delegate(.channelSwitched(channel))),
                    .send(.onAppear)
                )

            case .switcherAutoHideExpired:
                state.isSwitcherVisible = false
                state.switcherChannels = []
                state.switcherNowPlaying = [:]
                return .none

            // MARK: - Sleep Timer

            case .sleepTimerButtonTapped:
                state.isSleepTimerPickerVisible.toggle()
                if !state.isSleepTimerPickerVisible {
                    return startOverlayTimer()
                }
                return .cancel(id: CancelID.overlayTimer)

            case let .sleepTimerSelected(minutes):
                state.isSleepTimerPickerVisible = false
                guard let minutes else {
                    state.sleepTimerEndDate = nil
                    state.sleepTimerMinutesRemaining = nil
                    return .merge(
                        .cancel(id: CancelID.sleepTimer),
                        .cancel(id: CancelID.sleepTimerTick),
                        startOverlayTimer()
                    )
                }
                state.sleepTimerEndDate = Date().addingTimeInterval(Double(minutes) * 60)
                state.sleepTimerMinutesRemaining = minutes
                return .merge(
                    startSleepTimer(duration: .seconds(minutes * 60)),
                    startSleepTimerTick(),
                    startOverlayTimer()
                )

            case .sleepTimerTick:
                guard let endDate = state.sleepTimerEndDate else { return .none }
                let remaining = Int(ceil(endDate.timeIntervalSinceNow / 60.0))
                state.sleepTimerMinutesRemaining = max(remaining, 0)
                return .none

            case .sleepTimerFired:
                state.sleepTimerEndDate = nil
                state.sleepTimerMinutesRemaining = nil
                let saveEffect = saveProgressEffect(state: state)
                state.playerCommand = .stop
                return .merge(
                    saveEffect,
                    .cancel(id: CancelID.sleepTimerTick),
                    .run { send in
                        await send(.delegate(.dismissed))
                    }
                )

            // MARK: - Channel Number Entry

            case let .numberDigitPressed(digit):
                guard state.isLiveChannel else { return .none }
                if !state.isNumberEntryVisible {
                    state.isNumberEntryVisible = true
                    state.isOverlayVisible = false
                    state.isSwitcherVisible = false
                    state.isSleepTimerPickerVisible = false
                }
                state.numberEntryDigits.append(digit)
                state.numberEntryResult = nil
                return startNumberEntryTimer()

            case .numberEntryAutoHideExpired:
                guard !state.numberEntryDigits.isEmpty,
                      let number = Int(state.numberEntryDigits),
                      let playlistID = state.item.playlistID else {
                    state.isNumberEntryVisible = false
                    state.numberEntryDigits = ""
                    state.numberEntryResult = nil
                    return .none
                }
                state.numberEntryResult = .searching
                let client = channelListClient
                return .run { send in
                    let channel = try await client.fetchByNumber(playlistID, number)
                    await send(.numberEntryLookupResult(channel))
                } catch: { _, send in
                    await send(.numberEntryLookupResult(nil))
                }

            case let .numberEntryLookupResult(channel):
                if let channel {
                    state.numberEntryResult = .found(channel)
                    let delayClock = clock
                    return .run { send in
                        try await delayClock.sleep(for: .milliseconds(500))
                        await send(.numberEntryConfirmed)
                    }
                    .cancellable(id: CancelID.numberEntryTimer, cancelInFlight: true)
                } else {
                    state.numberEntryResult = .notFound
                    let delayClock = clock
                    return .run { send in
                        try await delayClock.sleep(for: .seconds(1))
                        await send(.numberEntryCancelled)
                    }
                    .cancellable(id: CancelID.numberEntryTimer, cancelInFlight: true)
                }

            case .numberEntryConfirmed:
                guard case let .found(channel) = state.numberEntryResult else {
                    return .send(.numberEntryCancelled)
                }
                // Clear number entry state
                state.isNumberEntryVisible = false
                state.numberEntryDigits = ""
                state.numberEntryResult = nil
                // If same channel, just close
                guard channel.id != state.item.contentID else { return .none }
                // Switch channel (same pattern as switcherChannelSelected)
                let saveEffect = saveProgressEffect(state: state)
                state.item = PlayableItem(channel: channel)
                state.status = .idle
                state.activeEngine = nil
                state.streamRoute = nil
                state.playerCommand = .stop
                state.retryCount = 0
                state.hasTriedFallbackEngine = false
                state.resumePositionMs = nil
                state.currentPositionMs = 0
                state.currentDurationMs = nil
                return .merge(
                    saveEffect,
                    .cancel(id: CancelID.retryTimer),
                    .cancel(id: CancelID.progressTimer),
                    .send(.delegate(.channelSwitched(channel))),
                    .send(.onAppear)
                )

            case .numberEntryCancelled:
                state.isNumberEntryVisible = false
                state.numberEntryDigits = ""
                state.numberEntryResult = nil
                return .cancel(id: CancelID.numberEntryTimer)

            // MARK: - Buffering Feedback

            case .bufferingTimerTick:
                if state.status == .loading {
                    state.bufferingElapsedSeconds += 1
                }
                return .none

            case .delegate:
                return .none
            }
        }
    }

    // MARK: - Helpers

    private func retryDelay(attempt: Int) -> Duration {
        switch attempt {
        case 1: return .seconds(1)
        case 2: return .seconds(3)
        default: return .seconds(7)
        }
    }

    private func alternateEngine(for engine: PlayerEngine) -> PlayerEngine {
        switch engine {
        case .avPlayer: return .vlcKit
        case .vlcKit: return .avPlayer
        }
    }

    private func startOverlayTimer() -> Effect<Action> {
        let overlayClock = clock
        return .run { send in
            try await overlayClock.sleep(for: .seconds(5))
            await send(.overlayAutoHideExpired)
        }
        .cancellable(id: CancelID.overlayTimer, cancelInFlight: true)
    }

    private func startProgressTimer() -> Effect<Action> {
        let progressClock = clock
        return .run { send in
            for await _ in progressClock.timer(interval: .seconds(30)) {
                await send(.saveProgress)
            }
        }
        .cancellable(id: CancelID.progressTimer, cancelInFlight: true)
    }

    private func startSwitcherTimer() -> Effect<Action> {
        let switcherClock = clock
        return .run { send in
            try await switcherClock.sleep(for: .seconds(5))
            await send(.switcherAutoHideExpired)
        }
        .cancellable(id: CancelID.switcherTimer, cancelInFlight: true)
    }

    private func startSleepTimer(duration: Duration) -> Effect<Action> {
        let sleepClock = clock
        return .run { send in
            try await sleepClock.sleep(for: duration)
            await send(.sleepTimerFired)
        }
        .cancellable(id: CancelID.sleepTimer, cancelInFlight: true)
    }

    private func startSleepTimerTick() -> Effect<Action> {
        let tickClock = clock
        return .run { send in
            for await _ in tickClock.timer(interval: .seconds(60)) {
                await send(.sleepTimerTick)
            }
        }
        .cancellable(id: CancelID.sleepTimerTick, cancelInFlight: true)
    }

    private func startBufferingTimer() -> Effect<Action> {
        let bufClock = clock
        return .run { send in
            for await _ in bufClock.timer(interval: .seconds(1)) {
                await send(.bufferingTimerTick)
            }
        }
        .cancellable(id: CancelID.bufferingTimer, cancelInFlight: true)
    }

    private func startNumberEntryTimer() -> Effect<Action> {
        let entryClock = clock
        return .run { send in
            try await entryClock.sleep(for: .seconds(2))
            await send(.numberEntryAutoHideExpired)
        }
        .cancellable(id: CancelID.numberEntryTimer, cancelInFlight: true)
    }

    private func saveProgressEffect(state: State) -> Effect<Action> {
        guard state.currentPositionMs > 0 else { return .none }
        let client = watchProgressClient
        let contentID = state.item.contentID
        let playlistID = state.item.playlistID
        let position = state.currentPositionMs
        let duration = state.currentDurationMs
        return .run { _ in
            try? await client.saveProgress(contentID, playlistID, position, duration)
        }
    }
}
