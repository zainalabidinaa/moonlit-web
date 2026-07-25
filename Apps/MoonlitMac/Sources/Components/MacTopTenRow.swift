import SwiftUI
import MoonlitCore

/// HBO Max-style "Top 10" row: a big outlined rank numeral overlapping each
/// poster, for the first 10 items in the row.
struct MacTopTenRow: View {
    let row: CatalogRow
    let onTap: (MetaPreview) -> Void
    var onHeaderTap: (() -> Void)?

    private var items: [MetaPreview] { Array(row.items.prefix(10)) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            rowHeader(title: row.title, onHeaderTap: onHeaderTap)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 32) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        rankedCard(item: item, rank: index + 1)
                    }
                }
                .padding(.horizontal, 32)
                .padding(.leading, 26)
            }
            .scrollClipDisabled()
        }
    }

    private func rankedCard(item: MetaPreview, rank: Int) -> some View {
        HStack(spacing: -26) {
            MacRankOutlineText(text: "\(rank)")
                .frame(width: rank > 9 ? 84 : 52, alignment: .leading)
                .zIndex(1)

            posterArtwork(item)
                .frame(width: 124, height: 180)
                .clipShape(RoundedRectangle(cornerRadius: MoonlitTheme.radiusControl, style: .continuous))
                .macAutomaticTileGlow(
                    artworkURL: item.artworkURL(preferring: .portrait),
                    cornerRadius: MoonlitTheme.radiusControl
                )
                .onTapGesture { onTap(item) }
        }
    }

    private func posterArtwork(_ item: MetaPreview) -> some View {
        Group {
            if let url = item.artworkURL(preferring: .portrait) {
                CachedAsyncImage(url: url) { image in
                    image.resizable().aspectRatio(contentMode: .fill)
                } placeholder: {
                    MoonlitTheme.surfaceElevated
                }
            } else {
                MoonlitTheme.surfaceElevated
            }
        }
    }

    private func rowHeader(title: String, onHeaderTap: (() -> Void)?) -> some View {
        Button(action: { onHeaderTap?() }) {
            HStack(spacing: 10) {
                Text(title)
                    .font(.system(size: 21, weight: .bold))
                    .foregroundColor(.white)
                Spacer()
                if onHeaderTap != nil {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.white.opacity(0.78))
                        .frame(width: 32, height: 32)
                        .background(Color.white.opacity(0.10), in: Circle())
                }
            }
            .padding(.horizontal, 32)
        }
        .buttonStyle(.plain)
        .disabled(onHeaderTap == nil)
    }
}

/// Outlined numeral to sit behind the poster, HBO Max-style.
private struct MacRankOutlineText: View {
    let text: String

    var body: some View {
        ZStack {
            ForEach(Array(stride(from: 0.0, to: 360.0, by: 45.0)), id: \.self) { angle in
                Text(text)
                    .font(.system(size: 88, weight: .black, design: .rounded))
                    .foregroundColor(.white.opacity(0.5))
                    .offset(
                        x: CGFloat(cos(angle * .pi / 180)) * 1.4,
                        y: CGFloat(sin(angle * .pi / 180)) * 1.4
                    )
            }
            Text(text)
                .font(.system(size: 88, weight: .black, design: .rounded))
                .foregroundColor(.black)
        }
    }
}
