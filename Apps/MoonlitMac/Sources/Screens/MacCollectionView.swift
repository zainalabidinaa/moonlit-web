import SwiftUI
import MoonlitCore

/// Franchise browse — "Part of {Collection}" on a movie's detail page opens
/// this. TMDB's `belongs_to_collection` + `/collection/{id}` are free, no
/// extra key beyond what Moonlit already configures for TMDB.
struct MacCollectionView: View {
    let collectionId: Int
    let fallbackName: String
    let onClose: () -> Void

    @State private var detail: TMDBCollectionDetail?
    @State private var isLoading = true

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                if isLoading {
                    HStack {
                        Spacer()
                        MacStrokeSpinner(size: 28)
                        Spacer()
                    }
                    .padding(.top, 60)
                } else if let detail {
                    if let overview = detail.overview, !overview.isEmpty {
                        Text(overview)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(MoonlitTheme.textSecondary)
                            .lineSpacing(4)
                    }
                    grid(detail.parts)
                } else {
                    Text("Couldn't load this collection.")
                        .foregroundColor(MoonlitTheme.textTertiary)
                        .padding(.top, 40)
                }
            }
            .padding(28)
        }
        .frame(minWidth: 640, minHeight: 560)
        .background(MoonlitTheme.background)
        .task {
            detail = await TMDBCollectionService.shared.collection(id: collectionId)
            isLoading = false
        }
    }

    private var header: some View {
        HStack {
            Text(detail?.name ?? fallbackName)
                .font(.system(size: 24, weight: .medium, design: .serif))
                .foregroundColor(.white)
            Spacer()
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white.opacity(0.85))
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(Color.white.opacity(0.08)))
            }
            .buttonStyle(.plain)
        }
    }

    private func grid(_ parts: [MetaPreview]) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 140, maximum: 170), spacing: 14)], spacing: 18) {
            ForEach(parts) { item in
                VStack(alignment: .leading, spacing: 6) {
                    Group {
                        if let url = item.artworkURL(preferring: .portrait) {
                            CachedAsyncImage(url: url) { img in
                                img.resizable().scaledToFill()
                            } placeholder: {
                                MoonlitTheme.surfaceElevated
                            }
                        } else {
                            MoonlitTheme.surfaceElevated
                        }
                    }
                    .aspectRatio(2 / 3, contentMode: .fill)
                    .clipShape(RoundedRectangle(cornerRadius: MoonlitTheme.radiusControl, style: .continuous))
                    .macAutomaticTileGlow(
                        artworkURL: item.artworkURL(preferring: .portrait),
                        cornerRadius: MoonlitTheme.radiusControl
                    )

                    Text(item.name)
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundColor(.white)
                        .lineLimit(1)
                    if let year = item.releaseInfo {
                        Text(year)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(MoonlitTheme.textTertiary)
                    }
                }
            }
        }
    }
}
