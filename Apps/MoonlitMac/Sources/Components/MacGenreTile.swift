import SwiftUI
import MoonlitCore

struct MacGenreTile: View {
    let name: String
    let onTap: () -> Void

    @State private var backdrops: [URL] = []
    @State private var isHovering = false

    private let tileWidth: CGFloat = 210
    private let tileHeight: CGFloat = 168

    private static let skewRad: CGFloat = 8 * .pi / 180

    private var palette: (from: Color, to: Color, ink: Color) {
        OklchPalette.genre(name)
    }

    var body: some View {
        Button(action: onTap) {
            ZStack(alignment: .bottomLeading) {
                LinearGradient(
                    colors: [palette.from, palette.to],
                    startPoint: .top,
                    endPoint: .bottom
                )

                if !backdrops.isEmpty {
                    HStack(spacing: 0) {
                        ForEach(Array(backdrops.prefix(3).enumerated()), id: \.offset) { i, url in
                            ZStack {
                                CachedAsyncImage(url: url) { image in
                                    image
                                        .resizable()
                                        .scaledToFill()
                                } placeholder: {
                                    Color.clear
                                }
                                .scaleEffect(1.4)
                                .transformEffect(CGAffineTransform(1, 0, tan(Self.skewRad), 1, 0, 0))
                            }
                            .frame(width: tileWidth / 3, height: tileHeight)
                            .clipped()
                            .transformEffect(CGAffineTransform(1, 0, -tan(Self.skewRad), 1, CGFloat(i - 1) * 6, 0))
                        }
                    }
                }

                LinearGradient(
                    stops: [
                        .init(color: palette.from, location: 0.0),
                        .init(color: palette.from.opacity(0.55), location: 0.65),
                        .init(color: palette.to.opacity(0.85), location: 1.0),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .blendMode(.multiply)
                .allowsHitTesting(false)

                LinearGradient(
                    colors: [.clear, palette.to],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .allowsHitTesting(false)

                HStack(alignment: .bottom) {
                    Text(name)
                        .font(.system(size: 24, weight: .medium, design: .serif))
                        .foregroundColor(palette.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .shadow(color: .black.opacity(0.4), radius: 9, y: 1)
                    Spacer()
                    Text("\u{203A}")
                        .font(.system(size: 20))
                        .foregroundColor(palette.ink.opacity(0.8))
                        .offset(x: isHovering ? 4 : 0)
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 14)
            }
            .frame(width: tileWidth, height: tileHeight)
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.10), lineWidth: 1)
            )
            // The tile's visible color is its palette gradient, not the dimmed
            // backdrops underneath — glow with the palette, not extracted art.
            .macTileGlow(
                isHovering: isHovering,
                artworkURL: nil,
                fallbackColor: palette.from
            )
            .offset(y: isHovering ? -4 : 0)
            .animation(.easeOut(duration: 0.30), value: isHovering)
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .task {
            guard backdrops.isEmpty else { return }
            let urls = await TMDBTileBackdropFetcher.fetchGenreBackdrops(genre: name)
            backdrops = urls
        }
    }
}
