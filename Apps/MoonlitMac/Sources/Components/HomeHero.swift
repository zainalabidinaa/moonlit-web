import SwiftUI
import MoonlitCore

struct HomeHero: View {
    let items: [MetaPreview]
    @Binding var currentIndex: Int
    let onWatchNow: (MetaPreview) -> Void
    let onToggleLibrary: (MetaPreview) -> Void
    var ambientColor: Color = .clear
    var ambientColor2: Color = .clear

    @State private var autoTimer: Timer?
    @Environment(\.controlActiveState) private var controlActiveState
    @StateObject private var libraryRepo = LibraryRepository.shared
    @StateObject private var artwork = MacHeroArtworkProvider.shared
    @StateObject private var awardsMeta = AwardsMetadataService.shared
    @StateObject private var awardIndex = AwardIndex.shared

    private let heroHeight: CGFloat = 560

    private var currentItem: MetaPreview? {
        guard items.indices.contains(currentIndex) else { return nil }
        return items[currentIndex]
    }

    private var isCurrentInLibrary: Bool {
        guard let currentItem else { return false }
        return libraryRepo.libraryItems.contains { $0.mediaId == currentItem.id }
    }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
                RadialGradient(
                    stops: [
                        .init(color: ambientColor.opacity(0.65), location: 0.0),
                        .init(color: ambientColor.opacity(0.30), location: 0.40),
                        .init(color: .clear, location: 1.0),
                    ],
                    center: .top,
                    startRadius: 0,
                    endRadius: heroHeight * 0.90
                )

                RadialGradient(
                    colors: [ambientColor2.opacity(0.40), .clear],
                    center: UnitPoint(x: 0.75, y: 0.10),
                    startRadius: 20,
                    endRadius: heroHeight * 0.55
                )

                if let currentItem {
                    heroImage(for: currentItem)
                        .id(currentItem.id)
                        .transition(.opacity)
                        .animation(.easeInOut(duration: 0.35), value: currentItem.id)
                }

                Color.clear
                    .frame(maxWidth: .infinity, maxHeight: heroHeight)
                .mask(
                    LinearGradient(
                        stops: [
                            .init(color: .black.opacity(0.92), location: 0.0),
                            .init(color: .black.opacity(0.88), location: 0.50),
                            .init(color: .black.opacity(0.35), location: 0.78),
                            .init(color: .clear, location: 1.0)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

                VStack(alignment: .leading, spacing: 8) {
                    if let genre = currentItem?.genres?.first {
                        Text(genre.uppercased())
                            .font(.system(size: 12, weight: .bold))
                            .tracking(2)
                            .foregroundColor(MoonlitTheme.accent)
                    }

                    if let logo = currentItem?.logo.flatMap(URL.init) {
                        CachedAsyncImage(url: logo) { image in
                            image.resizable()
                                .scaledToFit()
                                .frame(maxWidth: 330, maxHeight: 120, alignment: .leading)
                                .shadow(color: .black.opacity(0.55), radius: 8, x: 0, y: 3)
                        } placeholder: {
                            heroTitle
                        }
                        .id(currentItem?.id)
                    } else {
                        heroTitle
                    }

                    metaRow

                    if let description = currentItem?.description, !description.isEmpty {
                        Text(description)
                            .font(.system(size: 14))
                            .foregroundColor(.white.opacity(0.75))
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: 480, alignment: .leading)
                            .shadow(color: .black.opacity(0.4), radius: 3)
                            .padding(.bottom, 4)
                    }

                    HStack(spacing: 12) {
                        Button {
                            if let currentItem { onWatchNow(currentItem) }
                        } label: {
                            Label("Watch Now", systemImage: "play.fill")
                                .font(.system(size: 15, weight: .bold))
                                .foregroundStyle(.black)
                                .padding(.horizontal, 20)
                                .padding(.vertical, 12)
                                .background(.white, in: Capsule())
                        }
                        .buttonStyle(.plain)

                        Button {
                            if let currentItem { onToggleLibrary(currentItem) }
                        } label: {
                            Label(isCurrentInLibrary ? "In My List" : "My List", systemImage: isCurrentInLibrary ? "bookmark.fill" : "bookmark")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 11)
                                .macDarkGlassCapsule(interactive: true)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 42)
                .padding(.bottom, 58)
            }
            .overlay(alignment: .bottom) {
                pageIndicator
                    .padding(.bottom, 22)
            }
            .overlay(alignment: .topTrailing) {
                if let currentItem {
                    let summary = awardsMeta.summary(forId: currentItem.id)
                    MacCompactAwardBadgeView(
                        asset: summary?.isWinner == true
                            ? summary?.primaryBodyWithAsset?.assetName
                            : awardIndex.assetName(forId: currentItem.id)
                    )
                    .padding(.trailing, 28)
                    .padding(.top, 24)
                    .allowsHitTesting(false)
                }
            }
        .frame(height: heroHeight)
        .overlay(alignment: .center) {
            HStack {
                heroStepButton(systemName: "chevron.left") {
                    stepHero(-1)
                }
                .opacity(0.55)
                Spacer()
                heroStepButton(systemName: "chevron.right") {
                    stepHero(1)
                }
                .opacity(0.55)
            }
            .padding(.horizontal, 22)
            .opacity(items.count > 1 ? 1 : 0)
            .allowsHitTesting(items.count > 1)
        }
        .onAppear {
            artwork.prefetch(items: items)
            awardsMeta.prefetch(ids: items.map(\.id))
            startAutoAdvance()
        }
        .onChange(of: items.map(\.id)) { _, _ in
            artwork.prefetch(items: items)
            awardsMeta.prefetch(ids: items.map(\.id))
        }
        .onChange(of: controlActiveState) { _, newState in
            // Don't spend the 60s advance (animation + ambient-color extraction) on a
            // backgrounded window; resume when it becomes active again.
            if newState == .inactive {
                autoTimer?.invalidate()
                autoTimer = nil
            } else if autoTimer == nil {
                startAutoAdvance()
            }
        }
        .onDisappear {
            autoTimer?.invalidate()
            autoTimer = nil
        }
    }

    private var heroTitle: some View {
        Text(currentItem?.name ?? "")
            .font(.system(size: 46, weight: .black))
            .foregroundColor(.white)
            .lineLimit(2)
            .shadow(color: .black.opacity(0.55), radius: 8, x: 0, y: 3)
    }

    private var metaRow: some View {
        HStack(spacing: 9) {
            if let rating = currentItem?.imdbRating {
                Label(rating, systemImage: "star.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.white.opacity(0.72))
            }
            if let year = currentItem?.releaseInfo {
                Text(year)
                    .font(.caption.weight(.medium))
                    .foregroundColor(.white.opacity(0.62))
            }
            if let genres = currentItem?.genres {
                Text(genres.prefix(2).joined(separator: ", "))
                    .font(.caption.weight(.medium))
                    .foregroundColor(.white.opacity(0.62))
                    .lineLimit(1)
            }
        }
    }

    private var pageIndicator: some View {
        let maxVisible = 9
        let count = items.count
        let start = count <= maxVisible ? 0 : min(max(currentIndex - maxVisible / 2, 0), count - maxVisible)
        let end = min(start + maxVisible, count)

        return HStack(spacing: 7) {
            ForEach(start..<end, id: \.self) { index in
                Capsule()
                    .fill(index == currentIndex ? Color.white : Color.white.opacity(0.42))
                    .frame(width: index == currentIndex ? 28 : 8, height: 5)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: currentIndex)
    }

    private func heroImage(for item: MetaPreview) -> some View {
        Group {
            if let url = artwork.heroArtURL(for: item) {
                CachedAsyncImage(url: url, maxDimension: 3000) { image in
                    image.resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(maxWidth: .infinity, maxHeight: heroHeight, alignment: .top)
                } placeholder: {
                    MoonlitTheme.surfaceElevated
                }
            } else {
                MoonlitTheme.surfaceElevated
            }
        }
        .frame(maxWidth: .infinity, maxHeight: heroHeight)
        .clipped()
        .mask(
            LinearGradient(
                stops: [
                    .init(color: .black.opacity(0.92), location: 0.0),
                    .init(color: .black.opacity(0.85), location: 0.50),
                    .init(color: .black.opacity(0.35), location: 0.78),
                    .init(color: .clear, location: 1.0)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }

    private func heroStepButton(systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 40, height: 40)
                .macDarkGlassCapsule(interactive: true)
        }
        .buttonStyle(.plain)
    }

    private func startAutoAdvance() {
        autoTimer?.invalidate()
        guard items.count > 1, controlActiveState != .inactive else { return }
        autoTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { _ in
            Task { @MainActor in
                withAnimation(.spring(response: 0.5, dampingFraction: 0.82)) {
                    currentIndex = (currentIndex + 1) % max(items.count, 1)
                }
                let nextIdx = (currentIndex + 1) % max(items.count, 1)
                if let logoURL = items[nextIdx].logo.flatMap(URL.init) {
                    Task.detached(priority: .background) {
                        _ = await MoonlitImageCache.image(for: logoURL)
                    }
                }
            }
        }
    }

    private func stepHero(_ delta: Int) {
        guard !items.isEmpty else { return }
        withAnimation(.spring(response: 0.42, dampingFraction: 0.82)) {
            currentIndex = ((currentIndex + delta) % items.count + items.count) % items.count
        }
    }
}
