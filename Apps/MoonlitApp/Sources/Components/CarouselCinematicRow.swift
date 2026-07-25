import SwiftUI
import MoonlitCore

struct CarouselCinematicRow: View {
    let row: CatalogRow
    let onTap: (MetaPreview) -> Void
    var metrics: ResponsiveMetrics? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(row.title)
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(.white)
                .padding(.horizontal)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 12) {
                    ForEach(Array(row.items.enumerated()), id: \.element.id) { index, item in
                        CinematicTile(
                            item: item,
                            width: index == 0 ? leadWidth : tileWidth,
                            height: tileHeight
                        )
                        .onTapGesture { onTap(item) }
                    }
                }
                .padding(.horizontal)
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.viewAligned)
        }
    }

    private var screenWidth: CGFloat { UIScreen.main.bounds.width }
    private var leadWidth: CGFloat { screenWidth * 0.60 }
    private var tileWidth: CGFloat { screenWidth * 0.42 }
    private var tileHeight: CGFloat { leadWidth * 9 / 16 }
}

private struct CinematicTile: View {
    let item: MetaPreview
    let width: CGFloat
    let height: CGFloat
#if os(tvOS)
    @Environment(\.isFocused) var isFocused
#endif

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            if let url = item.artworkURL(preferring: .landscape) {
                CachedAsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().aspectRatio(contentMode: .fill)
                    default:
                        MoonlitTheme.surfaceElevated
                    }
                }
            } else {
                MoonlitTheme.surfaceElevated
            }

            LinearGradient(
                colors: [.clear, .black.opacity(0.68)],
                startPoint: .center,
                endPoint: .bottom
            )

            Text(item.name)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .padding(10)
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: MoonlitTheme.radiusCard, style: .continuous))
#if os(tvOS)
        .scaleEffect(isFocused ? 1.05 : 1.0)
        .animation(.easeOut(duration: 0.15), value: isFocused)
        .shadow(color: isFocused ? Color.white.opacity(0.3) : .clear, radius: isFocused ? 10 : 0)
#endif
    }
}
