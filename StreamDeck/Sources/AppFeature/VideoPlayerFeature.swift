import ComposableArchitecture
import Database
import Foundation

@Reducer
public struct VideoPlayerFeature {

    @ObservableState
    public struct State: Equatable, Sendable {
        public var item: PlayableItem
        public var status: PlaybackStatus = .idle
        public var activeEngine: PlayerEngine?
        public var streamRoute: StreamRoute?
        public var playerCommand: PlayerCommand = .none
        public var retryCount: Int = 0
        public var hasTriedFallbackEngine: Bool = false
        public var isOverlayVisible: Bool = true

        public static let maxRetriesPerEngine: Int = 3

        public init(channel: ChannelRecord) {
            self.item = PlayableItem(channel: channel)
        }

        public init(vodItem: VodItemRecord) {
            self.item = PlayableItem(vodItem: vodItem)
        }

        public init(item: PlayableItem) {
            self.item = item
        }
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
        case delegate(Delegate)

        @CasePathable
        public enum Delegate: Sendable, Equatable {
            case dismissed
        }
    }

    @Dependency(\.streamRouterClient) var streamRouterClient
    @Dependency(\.continuousClock) var clock
    @Dependency(\.dismiss) var dismiss

    public init() {}

    private enum CancelID {
        case overlayTimer
        case retryTimer
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
                return .run { send in
                    let route = await client.route(url)
                    await send(.streamRouted(route))
                }

            case .onDisappear:
                state.playerCommand = .stop
                return .cancel(id: CancelID.overlayTimer)
                    .merge(with: .cancel(id: CancelID.retryTimer))

            case .dismissTapped:
                state.playerCommand = .stop
                return .run { send in
                    await send(.delegate(.dismissed))
                }

            case let .streamRouted(route):
                state.streamRoute = route
                state.activeEngine = route.recommendedEngine
                state.status = .loading
                state.playerCommand = .play(url: route.url, engine: route.recommendedEngine)
                return startOverlayTimer()

            case let .playerStatusChanged(status):
                state.status = status
                if status == .playing {
                    state.retryCount = 0
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
                if state.status == .playing {
                    state.isOverlayVisible = false
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
}
