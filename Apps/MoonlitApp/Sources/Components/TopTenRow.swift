import SwiftUI
import MoonlitCore

/// HBO Max-style "Top 10" row: a big outlined rank numeral overlapping each
/// poster, for the first 10 items in the row.
struct TopTenRow: View {
    let row: CatalogRow
    let onTap: (MetaPreview) -> Void
    var onHeaderTap: (() -> Void)? = nil
    var metrics: ResponsiveMetrics? = nil
#if os(tvOS)
    @Environment(\.isFocused) var isFocused
#endif

    private var items: [MetaPreview] { Array(row.items.prefix(10)) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            rowHeader

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 26) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        rankedCard(item: item, rank: index + 1)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.leading, 22)
            }
        }
    }

    private var rowHeader: some View {
        Button(action: { onHeaderTap?() }) {
            HStack {
                Text(row.title)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(.white)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(.white.opacity(0.7))
            }
            .padding(.horizontal, 16)
        }
        .buttonStyle(.plain)
        .disabled(onHeaderTap == nil)
    }

    private func rankedCard(item: MetaPreview, rank: Int) -> some View {
        HStack(spacing: -22) {
            RankOutlineText(text: "\(rank)")
                .frame(width: rank > 9 ? 74 : 46, alignment: .leading)
                .zIndex(1)

            posterArtwork(item)
                .frame(width: 108, height: 158)
                .clipShape(RoundedRectangle(cornerRadius: MoonlitTheme.radiusControl, style: .continuous))
                .shadow(color: .black.opacity(0.4), radius: 8, y: 4)
                .onTapGesture { onTap(item) }
        }
#if os(tvOS)
        .scaleEffect(isFocused ? 1.05 : 1.0)
        .animation(.easeOut(duration: 0.15), value: isFocused)
        .shadow(color: isFocused ? Color.white.opacity(0.3) : .clear, radius: isFocused ? 10 : 0)
#endif
    }

    private func posterArtwork(_ item: MetaPreview) -> some View {
        Group {
            if let url = item.artworkURL(preferring: .portrait) {
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
        }
    }
}

/// Outlined numeral (stroke-only) to sit behind the poster, HBO Max-style.
private struct RankOutlineText: View {
    let text: String

    var body: some View {
        ZStack {
            ForEach(Array(stride(from: 0.0, to: 360.0, by: 45.0)), id: \.self) { angle in
                Text(text)
                    .font(.system(size: 76, weight: .black, design: .rounded))
                    .foregroundColor(.white.opacity(0.5))
                    .offset(
                        x: CGFloat(cos(angle * .pi / 180)) * 1.2,
                        y: CGFloat(sin(angle * .pi / 180)) * 1.2
                    )
            }
            Text(text)
                .font(.system(size: 76, weight: .black, design: .rounded))
                .foregroundColor(.black)
        }
    }
}
