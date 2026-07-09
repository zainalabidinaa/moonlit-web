import SwiftUI
import MoonlitCore

struct ContinueWatchingCard: View {
    let item: ContinueWatchingItem
    var isLoading: Bool = false
    var width: CGFloat = 240
    var height: CGFloat = 135

    @State private var isHovering = false

    private var imageURL: URL? {
        (item.thumbnail ?? item.poster).flatMap(URL.init)
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
                    colors: [.clear, .black.opacity(0.55)],
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
                        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                    MacLottieLoadingView(size: 24)
                        .frame(width: width, height: height, alignment: .center)
                }
            }
            .frame(width: width, height: height)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(Color.white.opacity(isHovering ? 0.18 : 0.06), lineWidth: 1)
            )
            .scaleEffect(isHovering ? 1.025 : 1.0)
            .animation(.spring(response: 0.28, dampingFraction: 0.78), value: isHovering)
            .onHover { isHovering = $0 }

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
