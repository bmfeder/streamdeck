import Database
import SwiftUI

struct EPGChannelSidebarView: View {
    let channels: [ChannelRecord]

    var body: some View {
        VStack(spacing: 0) {
            ForEach(channels, id: \.id) { channel in
                HStack(spacing: 8) {
                    channelLogo(channel)
                        .frame(width: 40, height: 40)
                        .clipShape(RoundedRectangle(cornerRadius: 6))

                    Text(channel.name)
                        .font(.system(size: EPGGuideLayout.channelNameFontSize))
                        .lineLimit(1)

                    Spacer()
                }
                .padding(.horizontal, 8)
                .frame(width: EPGGuideLayout.sidebarWidth, height: EPGGuideLayout.rowHeight)
            }
        }
    }

    @ViewBuilder
    private func channelLogo(_ channel: ChannelRecord) -> some View {
        if let logoURLString = channel.logoURL,
           let logoURL = URL(string: logoURLString) {
            AsyncImage(url: logoURL) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                case .failure:
                    placeholderLogo
                case .empty:
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                @unknown default:
                    placeholderLogo
                }
            }
        } else {
            placeholderLogo
        }
    }

    private var placeholderLogo: some View {
        ZStack {
            Color.secondary.opacity(0.2)
            Image(systemName: "tv")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
