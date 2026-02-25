import ComposableArchitecture
import SwiftUI

@Reducer
public struct EmbyFeature {
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

public struct EmbyView: View {
    let store: StoreOf<EmbyFeature>

    public init(store: StoreOf<EmbyFeature>) {
        self.store = store
    }

    public var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Image(systemName: Tab.emby.systemImage)
                    .font(.system(size: 64))
                    .foregroundStyle(.secondary)
                Text(Tab.emby.title)
                    .font(.title)
                Text(Tab.emby.emptyStateMessage)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding()
            .navigationTitle(Tab.emby.title)
            .onAppear { store.send(.onAppear) }
        }
    }
}
