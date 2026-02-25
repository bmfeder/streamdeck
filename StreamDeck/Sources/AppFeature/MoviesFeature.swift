import ComposableArchitecture
import SwiftUI

@Reducer
public struct MoviesFeature {
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

public struct MoviesView: View {
    let store: StoreOf<MoviesFeature>

    public init(store: StoreOf<MoviesFeature>) {
        self.store = store
    }

    public var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Image(systemName: Tab.movies.systemImage)
                    .font(.system(size: 64))
                    .foregroundStyle(.secondary)
                Text(Tab.movies.title)
                    .font(.title)
                Text(Tab.movies.emptyStateMessage)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding()
            .navigationTitle(Tab.movies.title)
            .onAppear { store.send(.onAppear) }
        }
    }
}
