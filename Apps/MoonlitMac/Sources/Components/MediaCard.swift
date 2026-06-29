import SwiftUI
import MoonlitCore

struct MediaCard: View {
    let item: MetaPreview
    var row: CatalogRow?
    var width: CGFloat?
    var height: CGFloat?

    @State private var primaryFailed = false
    @State private var isHovering = false
    @State private var haloColor: Color?

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

    // MARK: - Folder / service tile (Harbor-style: clean backdrop + overlay chrome)

    private var folderTile: some View {
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
            .onHover { hovering in
                isHovering = hovering
                if hovering { resolveHaloIfNeeded() }
            }

            Text(item.name)
                .font(.system(size: 12, weight: .regular))
                .foregroundColor(.white)
                .lineLimit(1)
                .frame(width: cardWidth, alignment: .leading)
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
        (item.poster ?? item.banner ?? item.backdrop).flatMap(URL.init)
    }

    // MARK: - Standard media tile (poster + caption)

    private var mediaTile: some View {
        VStack(alignment: .leading, spacing: 7) {
            ZStack(alignment: .topTrailing) {
                artwork(contentMode: .fill)
                    .frame(width: cardWidth, height: cardHeight)
                    .modifier(TileChrome(cornerRadius: cornerRadius, isHovering: isHovering, haloColor: haloColor))
            }
            .frame(width: cardWidth, height: cardHeight)
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

            if let rating = item.imdbRating, resolvedShape != .landscape {
                ratingBadge(rating)
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
        return (item.poster ?? item.banner).flatMap(URL.init)
    }

    // MARK: - Geometry & sources

    private var isFolderTile: Bool { item.id.hasPrefix("folder_") }

    private var cornerRadius: CGFloat {
        isFolderTile || resolvedShape == .landscape ? 16 : 14
    }

    private var resolvedShape: PosterShape? {
        if let rowShape = row?.tileShape {
            return PosterShape(rawValue: rowShape.lowercased())
        }
        return item.posterShape
    }

    private var primaryImageURL: URL? {
        if resolvedShape == .landscape {
            return (item.banner ?? item.poster).flatMap(URL.init)
        }
        return (item.poster ?? item.banner).flatMap(URL.init)
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

    private func ratingBadge(_ rating: String) -> some View {
        HStack(spacing: 4) {
            Text("IMDb")
                .font(.system(size: 8, weight: .black))
                .foregroundColor(Color(red: 0.961, green: 0.773, blue: 0.094))
            Rectangle()
                .fill(Color.white.opacity(0.22))
                .frame(width: 1, height: 10)
            Image(systemName: "star.fill")
                .font(.system(size: 8, weight: .bold))
                .foregroundColor(.yellow)
            Text(rating.replacingOccurrences(of: "/10", with: ""))
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(.white)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .background(.black.opacity(0.45), in: Capsule())
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.16), lineWidth: 0.75))
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
                color: glowColor.opacity(isHovering ? glowOpacity : 0.22),
                radius: isHovering ? 22 : 8,
                y: isHovering ? 10 : 6
            )
    }

    private var glowColor: Color { isHovering ? (haloColor ?? .black) : .black }
    private var glowOpacity: Double { haloColor == nil ? 0.40 : 0.55 }
}
