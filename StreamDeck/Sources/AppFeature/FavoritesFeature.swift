import ComposableArchitecture
import SwiftUI
import Database

@Reducer
public struct FavoritesFeature {

    @ObservableState
    public struct State: Equatable, Sendable {
        public var channels: [ChannelRecord] = []
        public var isLoading: Bool = false
        public var focusedChannelID: String?

        public init() {}
    }

    public enum Action: Sendable {
        case onAppear
        case channelsLoaded(Result<[ChannelRecord], Error>)
        case channelTapped(ChannelRecord)
        case toggleFavoriteTapped(String)
        case favoriteToggled(Result<String, Error>)
        case delegate(Delegate)

        @CasePathable
        public enum Delegate: Sendable, Equatable {
            case playChannel(ChannelRecord)
        }
    }

    @Dependency(\.channelListClient) var channelListClient

    public init() {}

    public var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .onAppear:
                state.isLoading = true
                let client = channelListClient
                return .run { send in
                    let favorites = try await client.fetchFavorites()
                    await send(.channelsLoaded(.success(favorites)))
                } catch: { error, send in
                    await send(.channelsLoaded(.failure(error)))
                }

            case let .channelsLoaded(.success(channels)):
                state.isLoading = false
                state.channels = channels
                return .none

            case .channelsLoaded(.failure):
                state.isLoading = false
                return .none

            case let .channelTapped(channel):
                state.focusedChannelID = channel.id
                return .send(.delegate(.playChannel(channel)))

            case let .toggleFavoriteTapped(channelID):
                let client = channelListClient
                return .run { send in
                    try await client.toggleFavorite(channelID)
                    await send(.favoriteToggled(.success(channelID)))
                } catch: { error, send in
                    await send(.favoriteToggled(.failure(error)))
                }

            case let .favoriteToggled(.success(channelID)):
                state.channels.removeAll { $0.id == channelID }
                return .none

            case .favoriteToggled(.failure):
                return .none

            case .delegate:
                return .none
            }
        }
    }
}

// MARK: - View

public struct FavoritesView: View {
    let store: StoreOf<FavoritesFeature>
    @FocusState private var focusedChannelID: String?

    public init(store: StoreOf<FavoritesFeature>) {
        self.store = store
    }

    #if os(tvOS)
    private let columns = [GridItem(.adaptive(minimum: 260), spacing: 30)]
    #else
    private let columns = [GridItem(.adaptive(minimum: 130), spacing: 16)]
    #endif

    public var body: some View {
        NavigationStack {
            Group {
                if store.isLoading && store.channels.isEmpty {
                    ProgressView()
                } else if store.channels.isEmpty {
                    emptyView
                } else {
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 20) {
                            ForEach(store.channels, id: \.id) { channel in
                                Button {
                                    store.send(.channelTapped(channel))
                                } label: {
                                    ChannelTileView(
                                        channel: channel,
                                        isFocused: focusedChannelID == channel.id
                                    )
                                }
                                .buttonStyle(.plain)
                                .focused($focusedChannelID, equals: channel.id)
                                .contextMenu {
                                    Button {
                                        store.send(.toggleFavoriteTapped(channel.id))
                                    } label: {
                                        Label("Remove from Favorites", systemImage: "star.slash")
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 20)
                    }
                }
            }
            .navigationTitle(Tab.favorites.title)
            .onAppear { store.send(.onAppear) }
        }
    }

    private var emptyView: some View {
        VStack(spacing: 24) {
            Image(systemName: Tab.favorites.systemImage)
                .font(.system(size: 64))
                .foregroundStyle(.secondary)
            Text(Tab.favorites.title)
                .font(.title)
            Text(Tab.favorites.emptyStateMessage)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
    }
}
