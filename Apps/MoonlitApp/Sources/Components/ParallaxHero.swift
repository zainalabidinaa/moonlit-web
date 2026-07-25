import SwiftUI
import MoonlitCore

struct ParallaxHero: View {
    let items: [MetaPreview]
    @Binding var currentIndex: Int
    let metrics: ResponsiveMetrics
    let onWatchNow: (MetaPreview) -> Void
    let onToggleLibrary: (MetaPreview) -> Void

    @State private var autoTimer: Timer?
    @StateObject private var libraryRepo = LibraryRepository.shared
    @StateObject private var artwork = HeroArtworkProvider.shared
    @StateObject private var awardsMeta = AwardsMetadataService.shared
    @StateObject private var awardIndex = AwardIndex.shared
    private let autoAdvanceSeconds: TimeInterval = 60
    static let heroHeight: CGFloat = 620

    private var isCurrentInLibrary: Bool {
        guard let item = items[safe: currentIndex] else { return false }
        return libraryRepo.libraryItems.contains { $0.mediaId == item.id }
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .bottom) {
                TabView(selection: $currentIndex) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        heroImage(for: item, width: geometry.size.width)
                            .contentShape(Rectangle())
                            .onTapGesture { onWatchNow(item) }
                            .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .id(items.map(\.id).joined())
                .frame(width: geometry.size.width, height: Self.heroHeight)
                // Alpha dissolve: the image stays sharp lower down, then fades to
                // transparent so the ambient background shows through.
                .mask(
                    LinearGradient(
                        stops: [
                            .init(color: .black, location: 0.0),
                            .init(color: .black, location: 0.62),
                            .init(color: .black.opacity(0.45), location: 0.84),
                            .init(color: .clear, location: 1.0),
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

                VStack(alignment: .center, spacing: 8) {
                    // Show title logo image when available, fall back to text title
                    if let logoURL = items[safe: currentIndex]?.logo.flatMap(URL.init) {
                        CachedAsyncImage(url: logoURL) { phase in
                            switch phase {
                            case .success(let image):
                                image
                                    .resizable()
                                    .scaledToFit()
                                    .frame(maxWidth: 260, maxHeight: 100)
                                    .shadow(color: .black.opacity(0.5), radius: 6, x: 0, y: 2)
                            default:
                                Text(items[safe: currentIndex]?.name ?? "")
                                    .font(.system(size: 40, weight: .black))
                                    .foregroundColor(.white)
                                    .lineLimit(2)
                                    .multilineTextAlignment(.center)
                                    .minimumScaleFactor(0.7)
                            }
                        }
                    } else {
                        Text(items[safe: currentIndex]?.name ?? "")
                            .font(.system(size: 40, weight: .black))
                            .foregroundColor(.white)
                            .lineLimit(2)
                            .multilineTextAlignment(.center)
                            .minimumScaleFactor(0.7)
                    }

                    metaRow

                    if let description = items[safe: currentIndex]?.description, !description.isEmpty {
                        Text(description)
                            .font(.system(size: 13))
                            .foregroundColor(.white.opacity(0.75))
                            .lineLimit(2)
                            .multilineTextAlignment(.center)
                            .shadow(color: .black.opacity(0.4), radius: 3)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.horizontal, metrics.horizontalPadding)
                .padding(.bottom, 52)
                // The hero copy is non-interactive so a tap anywhere on the hero
                // reaches the image's tap gesture (opens detail); the bookmark
                // button sits in its own overlay above this.
                .allowsHitTesting(false)
            }
            .overlay(alignment: .bottom) {
                pageIndicator
                    .padding(.bottom, 18)
            }
            .overlay(alignment: .bottomTrailing) {
                bookmarkButton
                    .padding(.trailing, 16)
                    .padding(.bottom, 120)
            }
            .overlay(alignment: .topTrailing) {
                if let item = items[safe: currentIndex] {
                    let summary = awardsMeta.summary(forId: item.id)
                    CompactAwardBadgeView(
                        asset: summary?.isWinner == true
                            ? summary?.primaryBodyWithAsset?.assetName
                            : awardIndex.assetName(forId: item.id)
                    )
                    .padding(.trailing, 16)
                    .padding(.top, 50)
                    .allowsHitTesting(false)
                }
            }
        }
        .frame(height: Self.heroHeight)
        .onAppear {
            artwork.prefetch(items: items)
            awardsMeta.prefetch(ids: items.map(\.id))
            startAutoAdvance()
        }
        .onChange(of: items.map(\.id)) { _, _ in
            artwork.prefetch(items: items)
            awardsMeta.prefetch(ids: items.map(\.id))
        }
        .onDisappear { stopAutoAdvance() }
    }

    /// Centered indicator with a sliding window so large carousels stay compact.
    private var pageIndicator: some View {
        let maxVisible = 7
        let count = items.count
        let start: Int
        if count <= maxVisible {
            start = 0
        } else {
            start = min(max(currentIndex - maxVisible / 2, 0), count - maxVisible)
        }
        let end = min(start + maxVisible, count)

        return HStack(spacing: 6) {
            ForEach(start..<end, id: \.self) { index in
                Capsule()
                    .fill(index == currentIndex ? Color.white : Color.white.opacity(0.45))
                    .frame(
                        width: index == currentIndex ? 24 : 8,
                        height: 5
                    )
            }
        }
        .animation(.easeInOut(duration: 0.25), value: currentIndex)
    }

    /// Fixed-size, center-cropped hero art. Textless TMDB poster when resolved
    /// (the title logo is overlaid separately), addon poster as fallback; the
    /// explicit frame keeps layout stable while images load.
    private func heroImage(for item: MetaPreview, width: CGFloat) -> some View {
        let candidates = artwork.heroArtCandidates(for: item)
        // The placeholder is always the base layer; once the textless poster
        // resolves it fades in on top (LadderedCachedImage animates the success
        // phase), so there's no hard cut — and the addon/btttr poster never shows.
        return ZStack {
            MoonlitTheme.surfaceContainer
            if !candidates.isEmpty {
                LadderedCachedImage(urls: candidates) { phase in
                    if case .success(let image) = phase {
                        image
                            .resizable()
                            .scaledToFill()
                            .transition(.opacity)
                    } else {
                        Color.clear
                    }
                }
            }
        }
        .frame(width: width, height: Self.heroHeight)
        .clipped()
    }

    private var metaRow: some View {
        HStack(spacing: 8) {
            if let rating = items[safe: currentIndex]?.imdbRating {
                IMDbRatingBadge(rating: rating)
            }
            if let year = items[safe: currentIndex]?.releaseInfo {
                Text(year)
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.6))
            }
            if let genre = items[safe: currentIndex]?.genres?.first {
                Text(genre)
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.6))
            }
        }
    }

    /// Small bookmark toggle on the right of the hero, replacing the old
    /// Watch Now + My List button pair. Watch Now is now the hero tap itself.
    private var bookmarkButton: some View {
        Button {
            if let item = items[safe: currentIndex] {
                onToggleLibrary(item)
            }
        } label: {
            Image(systemName: isCurrentInLibrary ? "bookmark.fill" : "bookmark")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.white)
                .frame(width: 40, height: 40)
        }
        .glassCircle(clear: true)
    }

    private func startAutoAdvance() {
        // Under UI automation a repeating timer keeps the run loop busy and blocks
        // XCUITest idle sync, so leave the hero static.
        guard !UITestMode.disableContinuousAnimations else { return }
        autoTimer = Timer.scheduledTimer(withTimeInterval: autoAdvanceSeconds, repeats: true) { _ in
            withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                currentIndex = (currentIndex + 1) % max(items.count, 1)
            }
        }
    }

    private func stopAutoAdvance() {
        autoTimer?.invalidate()
        autoTimer = nil
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        guard index >= 0, index < count else { return nil }
        return self[index]
    }
}
