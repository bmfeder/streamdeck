import ComposableArchitecture
import SwiftUI

@Reducer
public struct FavoritesFeature {
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

public struct FavoritesView: View {
    let store: StoreOf<FavoritesFeature>

    public init(store: StoreOf<FavoritesFeature>) {
        self.store = store
    }

    public var body: some View {
        NavigationStack {
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
            .navigationTitle(Tab.favorites.title)
            .onAppear { store.send(.onAppear) }
        }
    }
}
