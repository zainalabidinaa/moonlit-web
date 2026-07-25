import SwiftUI
import MoonlitCore

struct MediaCard: View, Equatable {
    let item: MetaPreview
    var row: CatalogRow?
    var width: CGFloat?
    var height: CGFloat?
    /// Explicit corner radius override (used by poster tiles driven by the
    /// user's "Poster card style" setting). `nil` falls back to the shape default.
    var cornerRadius: CGFloat?

    @State private var primaryFailed = false
    @State private var isHovering = false
    @State private var haloColor: Color?

    // Only the value inputs drive rendering; @State (hover/failure/halo) is preserved by
    // view identity. Comparing these lets `.equatable()` skip body rebuilds when a sibling
    // row updates. `CatalogRow` isn't Equatable, so we key on its stable `id`.
    static func == (lhs: MediaCard, rhs: MediaCard) -> Bool {
        lhs.item == rhs.item
            && lhs.row?.id == rhs.row?.id
            && lhs.width == rhs.width
            && lhs.height == rhs.height
            && lhs.cornerRadius == rhs.cornerRadius
    }

    var body: some View {
        Group {
            if isFolderTile {
                folderTile
            } else {
                mediaTile
            }
        }
        .onChange(of: item.id) { _, _ in
            primaryFailed = false
            haloColor = nil
        }
    }

    // MARK: - Folder / service tile

    @ViewBuilder
    private var folderTile: some View {
        if isFilmCollectionsTile {
            filmCollectionTile
        } else {
            standardFolderTile
        }
    }

    /// "Film Collections" row only — landscape tile with the title placed
    /// underneath like standard media tiles.
    private var filmCollectionTile: some View {
        VStack(alignment: .leading, spacing: 4) {
            ZStack(alignment: .bottomLeading) {
                folderBackground

                LinearGradient(
                    colors: [.black.opacity(0.85), .black.opacity(0.25), .clear],
                    startPoint: .bottom,
                    endPoint: .center
                )
            }
            .frame(width: cardWidth, height: cardHeight)
            .modifier(TileChrome(cornerRadius: resolvedCornerRadius, isHovering: isHovering, haloColor: haloColor))
            .scaleEffect(isHovering ? 1.04 : 1.0)
            .animation(.spring(response: 0.30, dampingFraction: 0.78), value: isHovering)

            Text(item.name)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(MoonlitTheme.textPrimary)
                .lineLimit(1)
                .frame(width: cardWidth, alignment: .leading)
        }
        .onHover { hovering in
            isHovering = hovering
            if hovering { resolveHaloIfNeeded() }
        }
    }

    /// Every other folder/collection row — art with the title as a caption underneath.
    private var standardFolderTile: some View {
        VStack(alignment: .leading, spacing: 4) {
            ZStack(alignment: .bottomLeading) {
                folderBackground

                LinearGradient(
                    colors: [.black.opacity(0.80), .black.opacity(0.20), .clear],
                    startPoint: .bottom,
                    endPoint: .center
                )
            }
            .frame(width: cardWidth, height: cardHeight)
            .modifier(TileChrome(cornerRadius: resolvedCornerRadius, isHovering: isHovering, haloColor: haloColor))
            .scaleEffect(isHovering ? 1.04 : 1.0)
            .animation(.spring(response: 0.30, dampingFraction: 0.78), value: isHovering)

            Text(item.name)
                .font(.system(size: 12, weight: .regular))
                .foregroundColor(.white)
                .lineLimit(1)
                .frame(width: cardWidth, alignment: .leading)
        }
        .onHover { hovering in
            isHovering = hovering
            if hovering { resolveHaloIfNeeded() }
        }
    }

    @ViewBuilder
    private var folderBackground: some View {
        // Cover art and focus GIF are stacked and crossfaded (the cover artwork is
        // out and the GIF in over 500ms rather than hard-swapping them).
        ZStack {
            if let url = folderArtURL {
                CachedAsyncImage(url: url) { image in
                    image.resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: cardWidth, height: cardHeight)
                        .clipped()
                        .background(MoonlitTheme.surfaceElevated)
                } placeholder: {
                    placeholder
                }
                .opacity(isShowingFocusGif ? 0 : 1)
            } else {
                placeholder
            }

            if let gifURL = focusGifURL {
                AnimatedRemoteImage(url: gifURL, contentMode: .resizeAspectFill)
                    .frame(width: cardWidth, height: cardHeight)
                    .clipped()
                    .opacity(isShowingFocusGif ? 1 : 0)
            }
        }
        .animation(.easeInOut(duration: 0.5), value: isShowingFocusGif)
    }

    /// The folder's focus GIF, when one is configured and enabled.
    private var focusGifURL: URL? {
        guard let gif = item.focusGif ?? row?.focusGif,
              (item.focusGifEnabled ?? row?.focusGifEnabled) == true
        else { return nil }
        return URL(string: gif)
    }

    private var isShowingFocusGif: Bool { isHovering && focusGifURL != nil }

    private var folderArtURL: URL? {
        // Only the "Film Collections" row uses a clean landscape backdrop behind
        // its on-tile title; every other folder tile keeps its poster cover.
        if isFilmCollectionsTile {
            let candidates = [item.backdrop, item.banner, row?.heroBackdrop, row?.coverImage, item.poster]
            if let s = candidates.compactMap({ $0 }).first(where: { !$0.isEmpty }), let u = URL(string: s) {
                return u
            }
        }
        return item.artworkURL(preferring: .portrait)
    }

    // MARK: - Standard media tile (poster + caption)

    private var mediaTile: some View {
        VStack(alignment: .leading, spacing: 7) {
            artwork(contentMode: .fill)
                .frame(width: cardWidth, height: cardHeight)
                .modifier(TileChrome(cornerRadius: resolvedCornerRadius, isHovering: isHovering, haloColor: haloColor))
                .overlay(alignment: .topTrailing) {
                    LibraryToggleButton(item: item)
                        .padding(7)
                        .opacity(isHovering ? 1 : 0)
                        .allowsHitTesting(isHovering)
                }
                .scaleEffect(isHovering ? 1.04 : 1.0)
                .animation(.spring(response: 0.30, dampingFraction: 0.78), value: isHovering)
                .onHover { hovering in
                    isHovering = hovering
                    if hovering { resolveHaloIfNeeded() }
                }

            Text(item.name)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(MoonlitTheme.textPrimary)
                .lineLimit(2)
                .frame(width: cardWidth, alignment: .leading)

            if let rating = item.imdbRating {
                HStack(spacing: 4) {
                    Text("IMDb")
                        .font(.system(size: 9, weight: .black))
                        .foregroundColor(MoonlitTheme.ratingGold)
                    Image(systemName: "star.fill")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(MoonlitTheme.ratingGold)
                    Text(rating.replacingOccurrences(of: "/10", with: ""))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.white.opacity(0.85))
                }
                .frame(width: cardWidth, alignment: .leading)
            }
        }
    }

    // MARK: - Artwork

    @ViewBuilder
    private func artwork(contentMode: ContentMode) -> some View {
        if let url = primaryFailed ? fallbackImageURL : primaryImageURL {
            CachedAsyncImage(url: url) { image in
                image.resizable()
                    .aspectRatio(contentMode: contentMode)
                    .frame(width: cardWidth, height: cardHeight)
                    .clipped()
                    .background(MoonlitTheme.surfaceElevated)
            } placeholder: {
                placeholder
                    .onAppear {
                        if !primaryFailed, fallbackImageURL != nil {
                            primaryFailed = true
                        }
                    }
            }
        } else {
            placeholder
        }
    }

    private var placeholder: some View {
        ZStack {
            MoonlitTheme.surfaceElevated
            if !isFolderTile {
                VStack(spacing: 8) {
                    Image(systemName: item.type == .series ? "tv.fill" : "film.fill")
                        .font(.system(size: resolvedShape == .landscape ? 28 : 24))
                        .foregroundColor(.white.opacity(0.18))
                    Text(item.name)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.white.opacity(0.45))
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 8)
                }
            }
        }
        .frame(width: cardWidth, height: cardHeight)
    }

    // MARK: - Halo resolution

    private func resolveHaloIfNeeded() {
        guard haloColor == nil, let url = haloSourceURL else { return }
        if let cached = TileHaloColorStore.shared.cached(for: url) {
            haloColor = cached
            return
        }
        Task { @MainActor in
            if let color = await TileHaloColorStore.shared.resolve(for: url) {
                withAnimation(.easeOut(duration: 0.35)) { haloColor = color }
            }
        }
    }

    private var haloSourceURL: URL? {
        // Folder tiles sample their clean backdrop; media tiles sample the poster.
        if isFolderTile { return folderArtURL }
        return item.artworkURL(preferring: .portrait)
    }

    // MARK: - Geometry & sources

    private var isFolderTile: Bool { item.id.hasPrefix("folder_") }

    /// Folder tiles in the "Film Collections" row get the landscape backdrop +
    /// on-tile serif title treatment; no other row does.
    private var isFilmCollectionsTile: Bool {
        isFolderTile && (row?.title.localizedCaseInsensitiveContains("Film Collections") ?? false)
    }

    private var resolvedCornerRadius: CGFloat {
        // Folder tiles always use a neutral larger rounded-2xl (16), regardless of
        // any passed override — so poster-scoped settings never leak onto folders.
        if isFolderTile { return 16 }
        // Poster tiles pass an explicit radius from the "Poster card style" setting.
        if let cornerRadius { return cornerRadius }
        // Landscape / square tiles use a neutral standard 12.
        return 12
    }

    private var resolvedShape: PosterShape? {
        // The Film Collections row is forced landscape regardless of its stored
        // (poster) shape. Other folder tiles honor the row's configured shape.
        if isFilmCollectionsTile { return .landscape }
        guard isFolderTile else { return .poster }
        if let rowShape = row?.tileShape {
            return PosterShape(rawValue: rowShape.lowercased())
        }
        return item.posterShape
    }

    private var primaryImageURL: URL? {
        item.artworkURL(preferring: resolvedShape == .landscape ? .landscape : .portrait)
    }

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
        if let width { return width }
        switch resolvedShape {
        case .landscape: return 240
        case .square: return 150
        case .poster, nil: return 154
        }
    }

    private var cardHeight: CGFloat {
        if let height { return height }
        switch resolvedShape {
        case .landscape: return 135
        case .square: return 150
        case .poster, nil: return 231
        }
    }

}

// MARK: - Shared tile chrome (soft borderless clip + focus halo)

private struct TileChrome: ViewModifier {
    let cornerRadius: CGFloat
    let isHovering: Bool
    let haloColor: Color?

    func body(content: Content) -> some View {
        content
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Color.white.opacity(isHovering ? 0.14 : 0.05), lineWidth: 0.75)
            )
            .macTileGlow(isHovering: isHovering, color: haloColor ?? .clear, cornerRadius: cornerRadius)
    }
}

// MARK: - Poster card style (user-tunable size + corner radius)

/// Central definition of the user-tunable poster tile geometry, mirroring
/// a neutral "Poster card style" panel. Posters scale from a 2:3 base; the
/// caller reads the two `@AppStorage` keys and feeds the results into `MediaCard`.
enum PosterStyle {
    /// UserDefaults keys (also referenced by the settings UI via `@AppStorage`).
    static let scaleKey = "moonlit.posterScale"
    static let radiusKey = "moonlit.posterRadius"

    static let defaultScale: Double = 1.0
    static let defaultRadius: Double = 12

    /// Standard poster width at scale 1 (matches the prior hardcoded 154×231).
    static let baseWidth: CGFloat = 154

    static func width(scale: Double) -> CGFloat { (baseWidth * scale).rounded() }
    static func height(scale: Double) -> CGFloat { (width(scale: scale) * 1.5).rounded() }
}

/// A poster `MediaCard` whose size and corner radius follow the user's
/// "Poster card style" setting. Reading `@AppStorage` here (rather than inside
/// the `.equatable()` `MediaCard`) is what lets tiles update live: this wrapper
/// re-renders on change and feeds fresh values into `MediaCard`'s `==`.
struct PosterCard: View {
    let item: MetaPreview
    var row: CatalogRow?

    @AppStorage(PosterStyle.scaleKey) private var scale: Double = PosterStyle.defaultScale
    @AppStorage(PosterStyle.radiusKey) private var radius: Double = PosterStyle.defaultRadius

    /// Rows mix media and folder tiles. Folders keep their own layout, so
    /// don't hand them poster values at all rather than relying on `MediaCard` to
    /// discard them.
    private var isFolderTile: Bool { item.id.hasPrefix("folder_") }

    var body: some View {
        MediaCard(
            item: item,
            row: row,
            width: isFolderTile ? nil : PosterStyle.width(scale: scale),
            height: isFolderTile ? nil : PosterStyle.height(scale: scale),
            cornerRadius: isFolderTile ? nil : radius
        )
        .equatable()
    }
}
