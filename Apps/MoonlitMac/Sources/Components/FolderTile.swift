import SwiftUI
import MoonlitCore

struct FolderTile: View {
    let row: CatalogRow
    let onTap: () -> Void
    @State private var isHovering = false

    private var isLandscape: Bool {
        row.tileShape == "landscape"
    }

    private var cardWidth: CGFloat { isLandscape ? 220 : 160 }
    private var cardHeight: CGFloat { isLandscape ? 124 : 240 }

    // the reference folder tiles use the larger rounded-2xl corner (16).
    private var cornerRadius: CGFloat { 16 }

    private var artworkURL: URL? {
        (row.coverImage ?? row.items.first?.poster).flatMap(URL.init)
    }

    var body: some View {
        Button(action: onTap) {
            ZStack(alignment: .bottomLeading) {
                Rectangle()
                    .fill(MoonlitTheme.surfaceElevated)
                    .frame(width: cardWidth, height: cardHeight)

                if let url = artworkURL {
                    CachedAsyncImage(url: url) { img in
                        img.resizable().aspectRatio(contentMode: .fill)
                            .frame(width: cardWidth, height: cardHeight)
                            .clipped()
                    } placeholder: {
                        EmptyView()
                    }
                }

                LinearGradient(
                    colors: [.clear, .black.opacity(0.7)],
                    startPoint: .top,
                    endPoint: .bottom
                )

                Text(row.title)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.white)
                    .lineLimit(2)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(width: cardWidth, height: cardHeight)
            .cornerRadius(cornerRadius)
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(
                        isHovering && (row.focusGlowEnabled ?? false)
                            ? MoonlitTheme.accent.opacity(0.6)
                            : Color.clear,
                        lineWidth: 2
                    )
            )
            .macTileGlow(
                isHovering: isHovering,
                artworkURL: artworkURL,
                cornerRadius: cornerRadius
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }
}
