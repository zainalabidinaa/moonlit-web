import SwiftUI
import MoonlitCore

struct FolderTile: View {
    let row: CatalogRow
    let onTap: () -> Void
    @State private var isHovering = false

    private var isLandscape: Bool {
        row.tileShape == "landscape"
    }

    private var cardWidth: CGFloat { isLandscape ? 220 : 140 }
    private var cardHeight: CGFloat { isLandscape ? 124 : 210 }

    var body: some View {
        Button(action: onTap) {
            ZStack(alignment: .bottomLeading) {
                Rectangle()
                    .fill(MoonlitTheme.surfaceElevated)
                    .frame(width: cardWidth, height: cardHeight)

                if let coverURL = row.coverImage ?? row.items.first?.poster,
                   let url = URL(string: coverURL) {
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
            .cornerRadius(MoonlitTheme.radiusControl)
            .overlay(
                RoundedRectangle(cornerRadius: MoonlitTheme.radiusControl)
                    .stroke(
                        isHovering && (row.focusGlowEnabled ?? false)
                            ? MoonlitTheme.accent.opacity(0.6)
                            : Color.clear,
                        lineWidth: 2
                    )
            )
            .shadow(
                color: (isHovering && (row.focusGlowEnabled ?? false))
                    ? MoonlitTheme.accent.opacity(0.35)
                    : Color.clear,
                radius: 16, y: 0
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }
}
