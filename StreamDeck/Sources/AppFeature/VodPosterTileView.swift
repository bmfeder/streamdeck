import SwiftUI
import Database

#if os(tvOS)
private let posterWidth: CGFloat = 220
private let posterHeight: CGFloat = 330
private let posterCornerRadius: CGFloat = 12
private let titleFontSize: CGFloat = 28
private let subtitleFontSize: CGFloat = 22
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
    let progress: Double?

    public init(item: VodItemRecord, isFocused: Bool = false, progress: Double? = nil) {
        self.item = item
        self.isFocused = isFocused
        self.progress = progress
    }

    public var body: some View {
        VStack(spacing: 8) {
            ZStack(alignment: .bottom) {
                posterImage
                    .frame(width: posterWidth, height: posterHeight)
                    .clipShape(RoundedRectangle(cornerRadius: posterCornerRadius))
                    .overlay(
                        RoundedRectangle(cornerRadius: posterCornerRadius)
                            .strokeBorder(Color.accentColor, lineWidth: isFocused ? 3 : 0)
                    )

                if let progress, progress > 0 {
                    progressBar(fraction: progress)
                }
            }

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

    private func progressBar(fraction: Double) -> some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(Color.black.opacity(0.5))
                Rectangle()
                    .fill(Color.accentColor)
                    .frame(width: geo.size.width * min(max(fraction, 0), 1))
            }
        }
        .frame(width: posterWidth, height: 6)
        .clipShape(RoundedRectangle(cornerRadius: 2))
        .padding(.bottom, 2)
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
                .font(.title)
                .foregroundStyle(.secondary)
        }
    }
}
