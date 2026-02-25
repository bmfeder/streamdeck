import ComposableArchitecture
import SwiftUI

@Reducer
public struct LiveTVFeature {
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

public struct LiveTVView: View {
    let store: StoreOf<LiveTVFeature>

    public init(store: StoreOf<LiveTVFeature>) {
        self.store = store
    }

    public var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Image(systemName: Tab.liveTV.systemImage)
                    .font(.system(size: 64))
                    .foregroundStyle(.secondary)
                Text(Tab.liveTV.title)
                    .font(.title)
                Text(Tab.liveTV.emptyStateMessage)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding()
            .navigationTitle(Tab.liveTV.title)
            .onAppear { store.send(.onAppear) }
        }
    }
}
