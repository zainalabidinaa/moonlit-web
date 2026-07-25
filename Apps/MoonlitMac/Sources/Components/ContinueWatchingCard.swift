import SwiftUI
import MoonlitCore

struct ContinueWatchingCard: View {
    let item: ContinueWatchingItem
    var isLoading: Bool = false
    var width: CGFloat = 240
    var height: CGFloat = 135
    var onMarkWatched: (() -> Void)?
    var onShowDetail: (() -> Void)?
    var onRemove: (() -> Void)?

    @State private var isHovering = false

    /// Same green already used for the watched checkmark on the detail
    /// page's episode grid — reused here, not a new color.
    private static let readyGreen = Color(red: 0.25, green: 0.86, blue: 0.52)

    private var imageURL: URL? {
        (item.background ?? item.poster).flatMap(URL.init)
    }

    private var logoURL: URL? {
        item.logo.flatMap(URL.init)
    }

    private var episodeLabel: String? {
        guard let s = item.seasonNumber, let e = item.episodeNumber else { return nil }
        return "S\(s), E\(e)"
    }

    private var minutesRemaining: Int? {
        guard item.durationMs > 0 else { return nil }
        let remainingMs = item.durationMs * (1.0 - item.progressFraction)
        let mins = Int((remainingMs / 60_000).rounded())
        return mins > 0 ? mins : nil
    }

    private var airsAtLabel: String? {
        guard let date = item.upcomingAirsAt else { return nil }
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return "Airs \(formatter.string(from: date))"
    }

    /// Standalone corner badges layered on top of the existing episode/time
    /// info row — that row (`episodeLabel` + `minutesRemaining` above) is
    /// left completely untouched.
    @ViewBuilder
    private var stateBadges: some View {
        if item.isUpNext {
            pill(text: "UP NEXT", tint: Self.readyGreen)
        } else if item.isUpcoming {
            VStack(alignment: .leading, spacing: 5) {
                pill(text: "UPCOMING", tint: MoonlitTheme.accent)
                if let airsAtLabel {
                    pill(text: airsAtLabel, tint: .white.opacity(0.7), filled: false)
                }
            }
        }
    }

    private func pill(text: String, tint: Color, filled: Bool = true) -> some View {
        Text(text)
            .font(.system(size: 9.5, weight: .bold))
            .tracking(0.6)
            .foregroundColor(tint)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(filled ? tint.opacity(0.2) : Color.black.opacity(0.55))
            .cornerRadius(MoonlitTheme.radiusSmall)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            ZStack(alignment: .bottom) {
                Group {
                    if let imageURL {
                        CachedAsyncImage(url: imageURL) { image in
                            image.resizable().aspectRatio(contentMode: .fill)
                        } placeholder: {
                            fallbackView
                        }
                    } else {
                        fallbackView
                    }
                }
                .frame(width: width, height: height)
                .clipped()

                // Centered show/movie logo (): sits over the art,
                // capped to 55% height / 78% width, and dims on hover so the
                // artwork reads. Falls back to nothing when the item has no logo.
                if let logoURL {
                    CachedAsyncImage(url: logoURL) { image in
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                    } placeholder: {
                        Color.clear
                    }
                    .frame(maxWidth: width * 0.78, maxHeight: height * 0.55)
                    .frame(width: width, height: height)
                    .opacity(isHovering ? 0.25 : 0.85)
                    .animation(.easeOut(duration: 0.22), value: isHovering)
                    .allowsHitTesting(false)
                }

                // Frosted blur layer — fades in from bottom
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .frame(height: 50)
                    .mask(
                        LinearGradient(
                            colors: [.clear, .black],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )

                // Dark scrim for text legibility
                LinearGradient(
                    colors: [.clear, .black.opacity(0.82)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 55)

                // Info row
                HStack(spacing: 4) {
                    if let episodeLabel {
                        Text(episodeLabel)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                    Spacer()
                    if let minutesRemaining {
                        Text("\(minutesRemaining) min left")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.white.opacity(0.72))
                    }
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 9)

                if isLoading {
                    Color.black.opacity(0.34)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    MacStrokeSpinner(size: 17)
                        .frame(width: width, height: height, alignment: .center)
                }
            }
            .frame(width: width, height: height)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(alignment: .topLeading) {
                stateBadges.padding(8)
            }
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.white.opacity(isHovering ? 0.18 : 0.06), lineWidth: 1)
            )
            .macTileGlow(isHovering: isHovering, artworkURL: imageURL, cornerRadius: 12)
            .scaleEffect(isHovering ? 1.025 : 1.0)
            .animation(.spring(response: 0.28, dampingFraction: 0.78), value: isHovering)
            .onHover { isHovering = $0 }
            .contextMenu {
                Button {
                    onMarkWatched?()
                } label: {
                    Label("Mark as Watched", systemImage: "checkmark.circle")
                }
                Button {
                    onShowDetail?()
                } label: {
                    Label("Show Detail", systemImage: "info.circle")
                }
                Divider()
                Button(role: .destructive) {
                    onRemove?()
                } label: {
                    Label("Remove from Continue Watching", systemImage: "xmark.circle")
                }
            }

            Text(item.name)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.white)
                .lineLimit(1)
                .frame(width: width, alignment: .leading)
        }
    }

    private var fallbackView: some View {
        ZStack {
            MoonlitTheme.surfaceElevated
            Image(systemName: "play.rectangle.fill")
                .font(.title2)
                .foregroundColor(.white.opacity(0.15))
        }
    }
}
