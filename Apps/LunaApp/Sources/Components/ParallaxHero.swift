import SwiftUI
import LunaCore

struct ParallaxHero: View {
    let items: [MetaPreview]
    @Binding var currentIndex: Int
    let metrics: ResponsiveMetrics
    let onWatchNow: (MetaPreview) -> Void
    let onToggleLibrary: (MetaPreview) -> Void

    @State private var autoTimer: Timer?
    @StateObject private var libraryRepo = LibraryRepository.shared
    private let autoAdvanceSeconds: TimeInterval = 6
    private static let heroHeight: CGFloat = 500

    private var isCurrentInLibrary: Bool {
        guard let item = items[safe: currentIndex] else { return false }
        return libraryRepo.libraryItems.contains { $0.mediaId == item.id }
    }

    var body: some View {
        GeometryReader { geometry in
            let height = Self.heroHeight + geometry.safeAreaInsets.top
            ZStack(alignment: .bottomLeading) {
                TabView(selection: $currentIndex) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        Group {
                            if let url = URL(string: item.banner ?? item.poster ?? "") {
                                CachedAsyncImage(url: url) { phase in
                                    switch phase {
                                    case .success(let image):
                                        image.resizable().aspectRatio(contentMode: .fill)
                                    default:
                                        LunaTheme.surfaceContainer
                                    }
                                }
                            } else {
                                LunaTheme.surfaceContainer
                            }
                        }
                        .scaleEffect(1.14)
                        .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .id(items.map(\.id).joined())
                .frame(height: height)

                VStack(spacing: 0) {
                    Spacer()
                    LinearGradient(
                        stops: [
                            .init(color: .clear, location: 0.0),
                            .init(color: .clear, location: 0.40),
                            .init(color: LunaTheme.background.opacity(0.5), location: 0.65),
                            .init(color: LunaTheme.background, location: 1.0),
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: height * 0.6)
                }

                VStack(alignment: .leading, spacing: 6) {
                    if let category = items[safe: currentIndex]?.genres?.first {
                        Text(category.uppercased())
                            .font(.system(size: 11, weight: .bold))
                            .tracking(2)
                            .foregroundColor(LunaTheme.accent)
                    }

                    // Show title logo image when available, fall back to text title
                    if let logoURL = items[safe: currentIndex]?.logo.flatMap(URL.init) {
                        CachedAsyncImage(url: logoURL) { phase in
                            switch phase {
                            case .success(let image):
                                image
                                    .resizable()
                                    .scaledToFit()
                                    .frame(maxWidth: 260, maxHeight: 100, alignment: .leading)
                                    .shadow(color: .black.opacity(0.5), radius: 6, x: 0, y: 2)
                            default:
                                Text(items[safe: currentIndex]?.name ?? "")
                                    .font(.system(size: 40, weight: .black))
                                    .foregroundColor(.white)
                                    .lineLimit(2)
                                    .minimumScaleFactor(0.7)
                            }
                        }
                    } else {
                        Text(items[safe: currentIndex]?.name ?? "")
                            .font(.system(size: 40, weight: .black))
                            .foregroundColor(.white)
                            .lineLimit(2)
                            .minimumScaleFactor(0.7)
                    }

                    metaRow

                    buttonRow

                    // Page indicator dots — centered below content
                    HStack(spacing: 5) {
                        ForEach(0..<items.count, id: \.self) { index in
                            Capsule()
                                .fill(index == currentIndex ? Color.white : Color.white.opacity(0.3))
                                .frame(
                                    width: index == currentIndex ? 20 : 6,
                                    height: 3
                                )
                                .animation(.easeInOut(duration: 0.25), value: currentIndex)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, 14)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, metrics.horizontalPadding)
                .padding(.bottom, 20)
            }
            .clipped()
        }
        .frame(height: Self.heroHeight)
        .onAppear { startAutoAdvance() }
        .onDisappear { stopAutoAdvance() }
    }

    private var metaRow: some View {
        HStack(spacing: 8) {
            if let rating = items[safe: currentIndex]?.imdbRating {
                HStack(spacing: 3) {
                    Image(systemName: "star.fill")
                        .font(.caption)
                        .foregroundColor(.yellow)
                    Text(rating)
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.6))
                }
            }
            if let year = items[safe: currentIndex]?.releaseInfo {
                Text("• \(year)")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.6))
            }
            if let genres = items[safe: currentIndex]?.genres {
                Text(genres.prefix(2).joined(separator: ", "))
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.6))
                    .lineLimit(1)
            }
        }
    }

    private var buttonRow: some View {
        HStack(spacing: 12) {
            Button {
                if let item = items[safe: currentIndex] {
                    onWatchNow(item)
                }
            } label: {
                Text("Watch Now")
                    .font(.subheadline.weight(.bold))
                    .foregroundColor(.black)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 11)
                    .background(Capsule().fill(.white))
            }

            Button {
                if let item = items[safe: currentIndex] {
                    onToggleLibrary(item)
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: isCurrentInLibrary ? "bookmark.fill" : "bookmark")
                    Text(isCurrentInLibrary ? "In My List" : "My List")
                }
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
            }
            .glassCapsule(interactive: true, clear: true)
        }
    }

    private func startAutoAdvance() {
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
