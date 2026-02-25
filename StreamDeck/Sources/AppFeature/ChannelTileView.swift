import SwiftUI
import Database

#if os(tvOS)
private let tileWidth: CGFloat = 260
private let tileHeight: CGFloat = 156
private let tileCornerRadius: CGFloat = 16
private let nameFontSize: CGFloat = 29
private let badgeFontSize: CGFloat = 22
private let nowPlayingFontSize: CGFloat = 24
#else
private let tileWidth: CGFloat = 130
private let tileHeight: CGFloat = 78
private let tileCornerRadius: CGFloat = 8
private let nameFontSize: CGFloat = 12
private let badgeFontSize: CGFloat = 10
private let nowPlayingFontSize: CGFloat = 10
#endif

/// A single channel tile for the grid.
/// Shows logo (async), name, and optional channel number badge.
/// Scales up on focus with shadow for tvOS 10-foot UI.
public struct ChannelTileView: View {
    let channel: ChannelRecord
    let isFocused: Bool
    let nowPlaying: String?

    public init(channel: ChannelRecord, isFocused: Bool = false, nowPlaying: String? = nil) {
        self.channel = channel
        self.isFocused = isFocused
        self.nowPlaying = nowPlaying
    }

    public var body: some View {
        VStack(spacing: 8) {
            ZStack(alignment: .topTrailing) {
                logoView
                    .frame(width: tileWidth, height: tileHeight)
                    .clipShape(RoundedRectangle(cornerRadius: tileCornerRadius))

                if let num = channel.channelNum {
                    Text("\(num)")
                        .font(.system(size: badgeFontSize, weight: .bold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.ultraThinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                        .padding(4)
                }
            }

            Text(channel.name)
                .font(.system(size: nameFontSize))
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(width: tileWidth)

            nowPlayingLabel
        }
        .scaleEffect(isFocused ? 1.08 : 1.0)
        .animation(.easeInOut(duration: 0.15), value: isFocused)
        .shadow(radius: isFocused ? 8 : 0)
    }

    @ViewBuilder
    private var nowPlayingLabel: some View {
        if let nowPlaying {
            Text(nowPlaying)
                .font(.system(size: nowPlayingFontSize))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(width: tileWidth)
        } else if channel.epgID != nil || channel.tvgID != nil {
            Text("No program info")
                .font(.system(size: nowPlayingFontSize))
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .frame(width: tileWidth)
        }
    }

    @ViewBuilder
    private var logoView: some View {
        if let logoURLString = channel.logoURL,
           let logoURL = URL(string: logoURLString) {
            AsyncImage(url: logoURL) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                case .failure:
                    placeholderView
                case .empty:
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                @unknown default:
                    placeholderView
                }
            }
        } else {
            placeholderView
        }
    }

    private var placeholderView: some View {
        ZStack {
            Color.secondary.opacity(0.2)
            Image(systemName: "tv")
                .font(.title2)
                .foregroundStyle(.secondary)
        }
    }
}
