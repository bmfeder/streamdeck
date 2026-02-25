import ComposableArchitecture
import SwiftUI

@Reducer
public struct TVShowsFeature {
    @ObservableState
    public struct State: Equatable, Sendable {
        public init() {}
    }

    public enum Action: Sendable {
        case onAppear
    }

    public init() {}

    public var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .onAppear:
                return .none
            }
        }
    }
}

public struct TVShowsView: View {
    let store: StoreOf<TVShowsFeature>

    public init(store: StoreOf<TVShowsFeature>) {
        self.store = store
    }

    public var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Image(systemName: Tab.tvShows.systemImage)
                    .font(.system(size: 64))
                    .foregroundStyle(.secondary)
                Text(Tab.tvShows.title)
                    .font(.title)
                Text(Tab.tvShows.emptyStateMessage)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding()
            .navigationTitle(Tab.tvShows.title)
            .onAppear { store.send(.onAppear) }
        }
    }
}
