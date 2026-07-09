import SwiftUI
import MoonlitCore

struct MediaCard: View, Equatable {
    let item: MetaPreview
    var row: CatalogRow?
    var width: CGFloat?
    var height: CGFloat?

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
        // Resolve the image-derived glow for every tile up front (not just on
        // hover) so each card carries a soft color halo at rest.
        .task(id: item.id) { resolveHaloIfNeeded() }
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

    /// "Film Collections" row only — landscape tile with count badge
    /// and the title placed underneath like standard media tiles.
    private var filmCollectionTile: some View {
        VStack(alignment: .leading, spacing: 4) {
            ZStack(alignment: .bottomLeading) {
                folderBackground

                LinearGradient(
                    colors: [.black.opacity(0.85), .black.opacity(0.25), .clear],
                    startPoint: .bottom,
                    endPoint: .center
                )

                if let count = item.itemCount {
                    countBadge(count)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        .padding(8)
                }
            }
            .frame(width: cardWidth, height: cardHeight)
            .modifier(TileChrome(cornerRadius: cornerRadius, isHovering: isHovering, haloColor: haloColor))
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

    /// Every other folder/collection row — the original tile: art + count badge
    /// with the title as a caption underneath.
    private var standardFolderTile: some View {
        VStack(alignment: .leading, spacing: 4) {
            ZStack(alignment: .bottomLeading) {
                folderBackground

                LinearGradient(
                    colors: [.black.opacity(0.80), .black.opacity(0.20), .clear],
                    startPoint: .bottom,
                    endPoint: .center
                )

                if let count = item.itemCount {
                    countBadge(count)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        .padding(8)
                }
            }
            .frame(width: cardWidth, height: cardHeight)
            .modifier(TileChrome(cornerRadius: cornerRadius, isHovering: isHovering, haloColor: haloColor))
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

    private func countBadge(_ count: Int) -> some View {
        let kind = item.countKind ?? (item.type == .series ? .shows : .films)
        let icon: String
        let noun: String
        switch kind {
        case .shows: icon = "tv"; noun = "SHOWS"
        case .collections: icon = "square.stack"; noun = "COLLECTIONS"
        case .films: icon = "film"; noun = "FILMS"
        }
        return HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 9, weight: .bold))
            Text(count >= 100 ? "99+" : "\(count) \(noun)")
                .font(.system(size: 9, weight: .bold))
        }
        .foregroundColor(.white)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.black.opacity(0.55), in: Capsule())
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.16), lineWidth: 0.75))
    }

    @ViewBuilder
    private var folderBackground: some View {
        if isHovering,
           let gif = item.focusGif ?? row?.focusGif,
           (item.focusGifEnabled ?? row?.focusGifEnabled) == true,
           let gifURL = URL(string: gif) {
            AnimatedRemoteImage(url: gifURL, contentMode: .resizeAspectFill)
                .frame(width: cardWidth, height: cardHeight)
                .clipped()
        } else if let url = folderArtURL {
            CachedAsyncImage(url: url) { image in
                image.resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: cardWidth, height: cardHeight)
                    .clipped()
                    .background(MoonlitTheme.surfaceElevated)
            } placeholder: {
                placeholder
            }
        } else {
            placeholder
        }
    }

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
                .modifier(TileChrome(cornerRadius: cornerRadius, isHovering: isHovering, haloColor: haloColor))
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
                        .foregroundColor(MoonlitTheme.harborGold)
                    Image(systemName: "star.fill")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(MoonlitTheme.harborGold)
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

    private var cornerRadius: CGFloat {
        isFolderTile || resolvedShape == .landscape ? 16 : 14
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

// MARK: - Shared tile chrome (soft borderless clip + Harbor focus halo)

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
            .shadow(
                color: (haloColor ?? .black).opacity(glowOpacity),
                radius: isHovering ? 24 : 14,
                y: isHovering ? 12 : 7
            )
    }

    /// Once the image color is resolved, every tile carries a soft colored glow
    /// at rest that deepens on hover. Falls back to a subtle black drop shadow
    /// until (or if) the color resolves.
    private var glowOpacity: Double {
        if haloColor == nil { return isHovering ? 0.40 : 0.22 }
        return isHovering ? 0.65 : 0.42
    }
}
