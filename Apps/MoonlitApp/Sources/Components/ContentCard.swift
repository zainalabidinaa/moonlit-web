import SwiftUI
import MoonlitCore

struct ContentCard: View {
    let item: MetaPreview
    let row: CatalogRow?
    let index: Int?
    var width: CGFloat? = nil
    var height: CGFloat? = nil
    @State private var primaryFailed = false
    // Observe the poster-badge config so tiles restyle when it changes; `posterRating`
    // also hides the separate IMDb pill once the rating is baked into the poster.
    @AppStorage(PosterService.Key.trend)   private var posterTrend   = true
    @AppStorage(PosterService.Key.genre)   private var posterGenre   = true
    @AppStorage(PosterService.Key.rating)  private var posterRating  = true
    @AppStorage(PosterService.Key.quality) private var posterQuality = false
    @AppStorage(PosterService.Key.age)     private var posterAge     = false
#if os(tvOS)
    @Environment(\.isFocused) var isFocused
#endif

    init(item: MetaPreview, row: CatalogRow? = nil, index: Int? = nil, width: CGFloat? = nil, height: CGFloat? = nil) {
        self.item = item
        self.row = row
        self.index = index
        self.width = width
        self.height = height
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ZStack(alignment: .bottom) {
                let displayURL = primaryFailed ? fallbackImageURL : primaryImageURL
                if let url = displayURL {
                    if url.pathExtension.lowercased() == "gif" {
                        AnimatedRemoteImage(url: url, contentMode: .scaleAspectFill)
                            .frame(width: cardWidth, height: cardHeight)
                            .scaleEffect(groupArtworkScale)
                            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
                    } else {
                        CachedAsyncImage(url: url) { phase in
                            switch phase {
                            case .success(let image):
                                image
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                                    .frame(width: cardWidth, height: cardHeight)
                                    .scaleEffect(groupArtworkScale)
                                    .clipped()
                                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
                            case .failure:
                                placeholderView.onAppear {
                                    if !primaryFailed { primaryFailed = true }
                                }
                            case .empty:
                                MoonlitTheme.surfaceElevated
                                    .frame(width: cardWidth, height: cardHeight)
                                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
                            @unknown default:
                                placeholderView
                            }
                        }
                    }
                } else {
                    placeholderView
                }

            }

            // Fusion-style caption: title on top, dimmed year beneath.
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white)
                    .lineLimit(1)
                if let year = item.releaseInfo, !year.isEmpty {
                    Text(year)
                        .font(.system(size: 11, weight: .regular))
                        .foregroundColor(MoonlitTheme.textTertiary)
                        .lineLimit(1)
                }
            }
            .frame(width: cardWidth, alignment: .leading)

            if let rating = item.imdbRating, resolvedShape != .landscape, !posterRating {
                IMDbRatingBadge(rating: rating)
            }
        }
        .sensoryFeedback(.impact(weight: .light), trigger: item.id)
        .onChange(of: item.id) { _, _ in
            primaryFailed = false
        }
#if os(tvOS)
        .scaleEffect(isFocused ? 1.05 : 1.0)
        .animation(.easeOut(duration: 0.15), value: isFocused)
        .shadow(color: isFocused ? Color.white.opacity(0.3) : .clear, radius: isFocused ? 10 : 0)
#endif
    }

    private var placeholderView: some View {
        VStack(spacing: 4) {
            Text(item.name)
                .font(.system(size: 22, weight: .bold))
                .foregroundColor(MoonlitTheme.textSecondary)
                .lineLimit(2)
                .padding(.horizontal, 4)
                .multilineTextAlignment(.center)
        }
        .frame(width: cardWidth, height: cardHeight)
        .background(MoonlitTheme.surfaceElevated)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
    }

    private var resolvedShape: PosterShape? {
        if let rowShape = row?.tileShape {
            return PosterShape(rawValue: rowShape.lowercased())
        }
        return item.posterShape
    }

    private var usesFittedArtwork: Bool {
        item.id.hasPrefix("folder_")
    }

    private var groupArtworkScale: CGFloat {
        guard usesFittedArtwork else { return 1 }
        let title = "\(row?.title ?? "") \(item.name)".lowercased()
        if title.contains("award") { return 1.08 }
        return 1
    }

    private var primaryImageURL: URL? {
        // Portrait media tiles use the live-configured btttr badge poster so the
        // Poster Badges setting applies to every tile — not just the ones whose
        // item.poster happened to be baked through PosterService at catalog-parse
        // time. Non-imdb ids (folders, tmdb, anime) return nil and fall back to the
        // item's own artwork.
        if resolvedShape != .landscape,
           let configured = PosterService.posterURL(forImdbId: item.id).flatMap(URL.init) {
            return configured
        }
        return item.artworkURL(preferring: resolvedShape == .landscape ? .landscape : .portrait)
    }

    /// Secondary image tried when the primary URL fails to load.
    /// For poster-shape tiles: try banner (which holds heroBackdrop for folder tiles).
    /// For landscape tiles: try poster.
    /// Also falls back to the row-level heroBackdrop or coverImage when available.
    private var fallbackImageURL: URL? {
        let primary = primaryImageURL
        let candidates: [String?]
        if resolvedShape == .landscape {
            candidates = [item.poster, row?.heroBackdrop, row?.coverImage, item.banner]
        } else {
            candidates = [item.banner, row?.heroBackdrop, row?.coverImage, item.poster]
        }
        return candidates
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .compactMap(URL.init)
            .first { $0 != primary }
    }

    private var cardWidth: CGFloat {
        if let width = width { return width }
        switch resolvedShape {
        case .landscape: return 230
        case .square:    return 140
        case .poster, nil: return 120
        }
    }

    private var cardHeight: CGFloat {
        if let height = height { return height }
        switch resolvedShape {
        case .landscape: return 130
        case .square:    return 140
        case .poster, nil: return 180
        }
    }

    /// Poster tiles use a generous ~16%-of-width corner (matches Omni's poster
    /// styling); other shapes keep the shared card radius.
    private var cornerRadius: CGFloat {
        switch resolvedShape {
        case .poster, nil: return cardWidth * 0.16
        default: return MoonlitTheme.radiusCard
        }
    }
}

// MARK: - IMDb Rating Badge

private let imdbYellow = Color(red: 0.961, green: 0.773, blue: 0.094) // #F5C518

struct IMDbRatingBadge: View {
    let rating: String

    // Strip "/10" suffix if present so we just show e.g. "7.3"
    private var displayRating: String {
        rating.replacingOccurrences(of: "/10", with: "").trimmingCharacters(in: .whitespaces)
    }

    var body: some View {
        HStack(spacing: 5) {
            // "IMDb" label
            Text("IMDb")
                .font(.system(size: 8, weight: .black))
                .foregroundColor(imdbYellow)

            // Hairline divider
            Rectangle()
                .fill(Color.white.opacity(0.2))
                .frame(width: 1, height: 9)

            // Star + rating number
            HStack(spacing: 2) {
                Image(systemName: "star.fill")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundColor(imdbYellow)
                Text(displayRating)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.white)
            }
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(Color.white.opacity(0.08))
        .overlay(
            RoundedRectangle(cornerRadius: 999)
                .strokeBorder(Color.white.opacity(0.15), lineWidth: 0.75)
        )
        .clipShape(Capsule())
    }
}

