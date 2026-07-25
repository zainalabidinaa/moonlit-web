import SwiftUI
import MoonlitCore

/// Cinematic subscription paywall.
///
/// Layered back-to-front: the shared `FusionAmbientBackground` wash (tinted from
/// the artwork of whatever the user just tried to play), a slow counter-scrolling
/// marquee of poster tiles drawn from the user's *own* library, a scrim that
/// dissolves the marquee into the content, then the offer itself.
///
/// The marquee deliberately uses the user's library rather than any catalog: a
/// purchase screen wallpapered in titles the app doesn't own reads as "pay us and
/// get these movies", which is the exact framing that draws rights-holder
/// complaints. When the library is empty the marquee is dropped entirely and the
/// ambient wash carries the screen on its own.
struct PaywallScreen: View {
    /// Artwork colors from the title that triggered the paywall, so the screen
    /// glows the color of the thing the user just tried to watch.
    var ambientColor: Color = Color(hex: "FF8A35")
    var ambientColor2: Color = Color(hex: "B85A1E")
    /// Poster URLs from the user's library. Empty is a supported state.
    var posterURLs: [URL] = []
    var onClose: () -> Void = {}

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selectedTier: Tier = .premium
    @State private var selectedPeriod: Period = .monthly

    enum Tier: String { case premium, premiumPlus }
    enum Period: String, CaseIterable {
        case monthly, yearly
        var label: String { self == .monthly ? "Monthly" : "Yearly · save 20%" }
    }

    private var marqueeHeight: CGFloat { posterURLs.isEmpty ? 0 : 250 }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .top) {
                FusionAmbientBackground(
                    ambientColor: ambientColor,
                    ambientColor2: ambientColor2,
                    isEnabled: true,
                    heroHeight: max(marqueeHeight - 90, 60),
                    screenHeight: geo.size.height
                )

                if !posterURLs.isEmpty {
                    marquee
                        .frame(height: marqueeHeight)
                        .allowsHitTesting(false)
                }

                offerContent
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color(hex: "0B0B0C"))
        .ignoresSafeArea()
        .overlay(alignment: .topTrailing) { closeButton }
    }

    // MARK: - Marquee

    /// Two rows of tiles drifting in opposite directions, rotated off-axis and
    /// over-scaled so the rotation never exposes a corner. Driven by the same
    /// `TimelineView` clock the ambient mesh uses — a repeating `Timer` here would
    /// pin the run loop, which `ParallaxHero` already documents as breaking UI
    /// automation.
    private var marquee: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: reduceMotion)) { timeline in
            let t = reduceMotion ? 0 : timeline.date.timeIntervalSinceReferenceDate

            VStack(spacing: 10) {
                marqueeRow(offset: drift(t, speed: 11, width: tileSpan), items: rowItems(0))
                marqueeRow(offset: -drift(t, speed: 9, width: tileSpan), items: rowItems(1))
            }
            .rotationEffect(.degrees(-9))
            .scaleEffect(1.35)
        }
        .mask(
            LinearGradient(
                stops: [
                    .init(color: .black, location: 0.0),
                    .init(color: .black, location: 0.45),
                    .init(color: .clear, location: 1.0),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .opacity(0.55)
    }

    private func marqueeRow(offset: CGFloat, items: [URL]) -> some View {
        HStack(spacing: 10) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, url in
                CachedAsyncImage(url: url) { phase in
                    ZStack {
                        Color.white.opacity(0.04)
                        if case .success(let image) = phase {
                            image.resizable().aspectRatio(contentMode: .fill)
                        }
                    }
                }
                .frame(width: tileWidth, height: tileWidth * 1.5)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
        }
        .offset(x: offset)
    }

    private let tileWidth: CGFloat = 96
    private var tileSpan: CGFloat { tileWidth + 10 }

    /// Continuous leftward drift that wraps on one tile width, so the strip never
    /// visibly snaps.
    private func drift(_ t: Double, speed: Double, width: CGFloat) -> CGFloat {
        let cycle = Double(width)
        let travelled = (t * speed).truncatingRemainder(dividingBy: cycle)
        return -CGFloat(travelled)
    }

    /// Repeats the library to fill the strip, offsetting the second row so the two
    /// rows never show the same poster in the same column.
    private func rowItems(_ row: Int) -> [URL] {
        guard !posterURLs.isEmpty else { return [] }
        let rotated = Array(posterURLs[(row * 3 % posterURLs.count)...]
            + posterURLs[..<(row * 3 % posterURLs.count)])
        return Array(repeating: rotated, count: 4).flatMap { $0 }
    }

    // MARK: - Offer

    private var offerContent: some View {
        VStack(spacing: 0) {
            Spacer(minLength: marqueeHeight * 0.62)

            VStack(spacing: 8) {
                Text("Unlock premium playback")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(MoonlitTheme.textPrimary)
                    .multilineTextAlignment(.center)
                Text("Play anything in your library, on every device.")
                    .font(.system(size: 15))
                    .foregroundStyle(MoonlitTheme.textSecondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 22)

            HStack(spacing: 10) {
                tierCard(.premium, title: "Premium", blurb: "Unlimited playback", price: "$4.99")
                tierCard(.premiumPlus, title: "Premium+", blurb: "Manage your own addons", price: "$7.99")
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 14)

            periodToggle
                .padding(.horizontal, 20)
                .padding(.bottom, 20)

            Button(action: {}) {
                Text("Continue")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color(hex: "0B0B0C"))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(MoonlitTheme.accent, in: RoundedRectangle(cornerRadius: MoonlitTheme.radiusLarge, style: .continuous))
            }
            .padding(.horizontal, 20)

            Button("Restore purchases") {}
                .font(.system(size: 13))
                .foregroundStyle(MoonlitTheme.textTertiary)
                .padding(.top, 14)

            Text("Auto-renews until cancelled. Manage in Settings.")
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.32))
                .padding(.top, 6)
                .padding(.bottom, 34)
        }
    }

    private func tierCard(_ tier: Tier, title: String, blurb: String, price: String) -> some View {
        let isSelected = selectedTier == tier
        return Button {
            withAnimation(.snappy(duration: 0.22)) { selectedTier = tier }
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(MoonlitTheme.textPrimary)
                Text(blurb)
                    .font(.system(size: 12))
                    .foregroundStyle(MoonlitTheme.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(price)
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(isSelected ? MoonlitTheme.accent : MoonlitTheme.textPrimary)
                    .padding(.top, 6)
            }
            .frame(maxWidth: .infinity, minHeight: 104, alignment: .topLeading)
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: MoonlitTheme.radiusLarge, style: .continuous)
                    .fill(isSelected ? MoonlitTheme.accent.opacity(0.10) : Color.white.opacity(0.04))
            )
            .overlay(
                RoundedRectangle(cornerRadius: MoonlitTheme.radiusLarge, style: .continuous)
                    .strokeBorder(isSelected ? MoonlitTheme.accent : Color.white.opacity(0.10),
                                  lineWidth: isSelected ? 2 : 1)
            )
        }
        .buttonStyle(.plain)
    }

    private var periodToggle: some View {
        HStack(spacing: 4) {
            ForEach(Period.allCases, id: \.self) { period in
                let isSelected = selectedPeriod == period
                Button {
                    withAnimation(.snappy(duration: 0.22)) { selectedPeriod = period }
                } label: {
                    Text(period.label)
                        .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                        .foregroundStyle(isSelected ? Color(hex: "0B0B0C") : MoonlitTheme.textSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .background(
                            RoundedRectangle(cornerRadius: MoonlitTheme.radiusControl, style: .continuous)
                                .fill(isSelected ? MoonlitTheme.accent : .clear)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(
            RoundedRectangle(cornerRadius: MoonlitTheme.radiusCard, style: .continuous)
                .fill(Color.white.opacity(0.05))
        )
    }

    private var closeButton: some View {
        Button(action: onClose) {
            Image(systemName: "xmark")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white.opacity(0.75))
                .frame(width: 32, height: 32)
                .background(Circle().fill(.ultraThinMaterial))
        }
        .padding(.trailing, 18)
        .padding(.top, 60)
    }
}
