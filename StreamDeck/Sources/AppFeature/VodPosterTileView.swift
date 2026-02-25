import SwiftUI
import Database

#if os(tvOS)
private let posterWidth: CGFloat = 180
private let posterHeight: CGFloat = 270
private let posterCornerRadius: CGFloat = 12
private let titleFontSize: CGFloat = 26
private let subtitleFontSize: CGFloat = 20
#else
private let posterWidth: CGFloat = 120
private let posterHeight: CGFloat = 180
private let posterCornerRadius: CGFloat = 8
private let titleFontSize: CGFloat = 12
private let subtitleFontSize: CGFloat = 10
#endif

/// A poster tile for VOD content (movies and TV series).
/// Shows poster image, title, year, and optional rating.
/// Scales up on focus with shadow for tvOS 10-foot UI.
public struct VodPosterTileView: View {
    let item: VodItemRecord
    let isFocused: Bool

    public init(item: VodItemRecord, isFocused: Bool = false) {
        self.item = item
        self.isFocused = isFocused
    }

    public var body: some View {
        VStack(spacing: 8) {
            posterImage
                .frame(width: posterWidth, height: posterHeight)
                .clipShape(RoundedRectangle(cornerRadius: posterCornerRadius))

            Text(item.title)
                .font(.system(size: titleFontSize))
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(width: posterWidth)

            subtitleLabel
        }
        .scaleEffect(isFocused ? 1.08 : 1.0)
        .animation(.easeInOut(duration: 0.15), value: isFocused)
        .shadow(radius: isFocused ? 8 : 0)
    }

    @ViewBuilder
    private var subtitleLabel: some View {
        HStack(spacing: 4) {
            if let year = item.year {
                Text(String(year))
            }
            if let rating = item.rating {
                if item.year != nil {
                    Text("·")
                }
                Image(systemName: "star.fill")
                    .font(.system(size: subtitleFontSize - 2))
                    .foregroundStyle(.yellow)
                Text(String(format: "%.1f", rating))
            }
        }
        .font(.system(size: subtitleFontSize))
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .frame(width: posterWidth)
    }

    @ViewBuilder
    private var posterImage: some View {
        if let posterURLString = item.posterURL,
           let posterURL = URL(string: posterURLString) {
            AsyncImage(url: posterURL) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
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
            Image(systemName: item.type == "series" ? "tv" : "film")
                .font(.title2)
                .foregroundStyle(.secondary)
        }
    }
}
