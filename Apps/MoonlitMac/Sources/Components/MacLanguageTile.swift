import SwiftUI
import MoonlitCore

struct MacLanguageTile: View {
    let iso: String
    let name: String
    let endonym: String
    let hue: Double
    let onTap: () -> Void

    @State private var backdrops: [URL] = []
    @State private var isHovering = false

    private let tileWidth: CGFloat = 210
    private let tileHeight: CGFloat = 168

    private static let skewRad: CGFloat = 8 * .pi / 180

    private var from: Color { OklchPalette.oklchToColor(L: 0.42, C: 0.13, h: hue) }
    private var to: Color { OklchPalette.oklchToColor(L: 0.17, C: 0.07, h: hue) }
    private var ink: Color { OklchPalette.oklchToColor(L: 0.96, C: 0.02, h: hue) }

    // Harbor uses a 150° gradient (from ≈ top-left → to ≈ bottom-right).
    private let gradStart = UnitPoint(x: 0.15, y: 0.0)
    private let gradEnd = UnitPoint(x: 0.85, y: 1.0)

    var body: some View {
        Button(action: onTap) {
            ZStack(alignment: .bottomLeading) {
                LinearGradient(
                    colors: [from, to],
                    startPoint: gradStart,
                    endPoint: gradEnd
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
                        .init(color: from, location: 0.0),
                        .init(color: from.opacity(0.55), location: 0.60),
                        .init(color: to.opacity(0.90), location: 1.0),
                    ],
                    startPoint: gradStart,
                    endPoint: gradEnd
                )
                .blendMode(.multiply)
                .allowsHitTesting(false)

                LinearGradient(
                    colors: [.clear, to],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .allowsHitTesting(false)

                Text(endonym)
                    .font(.system(size: 34, weight: .medium, design: .serif))
                    .foregroundColor(ink.opacity(0.25))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .padding(.trailing, 16)
                    .padding(.top, 12)
                    .allowsHitTesting(false)

                HStack(alignment: .bottom) {
                    Text(name)
                        .font(.system(size: 26, weight: .medium, design: .serif))
                        .foregroundColor(ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .shadow(color: .black.opacity(0.4), radius: 9, y: 1)
                    Spacer()
                    Text("\u{203A}")
                        .font(.system(size: 20))
                        .foregroundColor(ink.opacity(0.8))
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
            .offset(y: isHovering ? -4 : 0)
            .animation(.easeOut(duration: 0.30), value: isHovering)
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .task {
            guard backdrops.isEmpty else { return }
            let urls = await TMDBTileBackdropFetcher.fetchLanguageBackdrops(language: iso)
            backdrops = urls
        }
    }
}
