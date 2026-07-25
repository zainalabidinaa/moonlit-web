import SwiftUI
import MoonlitCore

struct HeroBannerRow: View {
    let row: CatalogRow
    let onTap: (MetaPreview) -> Void
    var onHeaderTap: (() -> Void)? = nil
    var metrics: ResponsiveMetrics? = nil
#if os(tvOS)
    @Environment(\.isFocused) var isFocused
#endif

    private var leadItem: MetaPreview? { row.items.first }
    private var secondaryItems: ArraySlice<MetaPreview> { row.items.dropFirst().prefix(3) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            rowHeader

            if let leadItem {
                VStack(spacing: 0) {
                    Button { onTap(leadItem) } label: {
                        ZStack(alignment: .topLeading) {
                            HeroBannerArtwork(item: leadItem)
                                .frame(maxWidth: .infinity)
                                .frame(height: heroHeight)
                                .clipped()

                            LinearGradient(
                                colors: [.black.opacity(0.70), .black.opacity(0.18), .clear],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )

                            VStack(alignment: .leading, spacing: 4) {
                                Text(leadItem.name)
                                    .font(.system(size: 24, weight: .black))
                                    .foregroundStyle(.white)
                                    .lineLimit(2)
                                if let release = leadItem.releaseInfo ?? leadItem.released {
                                    Text(release)
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundStyle(.white.opacity(0.72))
                                }
                            }
                            .padding(16)
                        }
                    }
                    .buttonStyle(.plain)
#if os(tvOS)
                    .scaleEffect(isFocused ? 1.05 : 1.0)
                    .animation(.easeOut(duration: 0.15), value: isFocused)
                    .shadow(color: isFocused ? Color.white.opacity(0.3) : .clear, radius: isFocused ? 10 : 0)
#endif

                    HStack(alignment: .top, spacing: 10) {
                        ForEach(Array(secondaryItems.enumerated()), id: \.element.id) { _, item in
                            Button { onTap(item) } label: {
                                VStack(alignment: .leading, spacing: 5) {
                                    HeroBannerArtwork(item: item)
                                        .frame(height: thumbnailHeight)
                                        .frame(maxWidth: .infinity)
                                        .clipShape(RoundedRectangle(cornerRadius: MoonlitTheme.radiusControl, style: .continuous))

                                    Text(item.name)
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundStyle(.white)
                                        .lineLimit(1)

                                    if let release = item.releaseInfo ?? item.released {
                                        Text(release)
                                            .font(.system(size: 9, weight: .medium))
                                            .foregroundStyle(.white.opacity(0.48))
                                            .lineLimit(1)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
#if os(tvOS)
                            .scaleEffect(isFocused ? 1.05 : 1.0)
                            .animation(.easeOut(duration: 0.15), value: isFocused)
                            .shadow(color: isFocused ? Color.white.opacity(0.3) : .clear, radius: isFocused ? 10 : 0)
#endif
                        }
                    }
                    .padding(12)
                    .background(Color(red: 0.20, green: 0.19, blue: 0.15).opacity(0.72))
                }
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
                .padding(.horizontal, 16)
            }
        }
    }

    private var rowHeader: some View {
        Button(action: { onHeaderTap?() }) {
            HStack {
                Text(row.title)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(.white)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundColor(.white.opacity(0.78))
                    .frame(width: 34, height: 34)
                    .background(Color.white.opacity(0.10), in: Circle())
            }
            .padding(.horizontal, 16)
        }
        .buttonStyle(.plain)
        .disabled(onHeaderTap == nil)
    }

    private var heroHeight: CGFloat {
        let width = UIScreen.main.bounds.width - 32
        return min(260, max(210, width * 0.62))
    }

    private var thumbnailHeight: CGFloat {
        let width = (UIScreen.main.bounds.width - 32 - 24 - 20) / 3
        return width * 9 / 16
    }
}

private struct HeroBannerArtwork: View {
    let item: MetaPreview

    var body: some View {
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
    }
}
