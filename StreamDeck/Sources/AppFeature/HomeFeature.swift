import ComposableArchitecture
import SwiftUI

@Reducer
public struct HomeFeature {
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

public struct HomeView: View {
    let store: StoreOf<HomeFeature>

    public init(store: StoreOf<HomeFeature>) {
        self.store = store
    }

    public var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Image(systemName: Tab.home.systemImage)
                    .font(.system(size: 64))
                    .foregroundStyle(.secondary)
                Text(Tab.home.title)
                    .font(.title)
                Text(Tab.home.emptyStateMessage)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding()
            .navigationTitle(Tab.home.title)
            .onAppear { store.send(.onAppear) }
        }
    }
}
