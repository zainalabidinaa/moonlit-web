import SwiftUI
import MoonlitCore

/// Award-winner "corner" for the detail hero: glyph + laurel flanks for wins,
/// bare glyph for nomination-only titles, plus a wins/nominations caption.
/// Prefers the Wikidata-backed `AwardSummary` when it has loaded; falls back to
/// the instant, collection-curated `AwardIndex` glyph in the meantime.
struct AwardBadgeView: View {
    let summary: AwardSummary?
    let fallbackAsset: String?

    private var asset: String? {
        summary?.primaryBodyWithAsset?.assetName ?? fallbackAsset
    }

    private var tint: Color {
        summary?.primaryBodyWithAsset?.tintColor ?? Color(red: 0.831, green: 0.686, blue: 0.216)
    }

    private var isWinner: Bool { summary?.isWinner ?? (fallbackAsset != nil) }
    private var caption: String? { summary?.badgeText }

    var body: some View {
        if let asset {
            VStack(spacing: 4) {
                HStack(spacing: -2) {
                    if isWinner {
                        Image(systemName: "laurel.leading")
                            .font(.system(size: 34))
                            .foregroundColor(tint)
                    }
                    Image(asset)
                        .resizable()
                        .scaledToFit()
                        .frame(height: 40)
                    if isWinner {
                        Image(systemName: "laurel.trailing")
                            .font(.system(size: 34))
                            .foregroundColor(tint)
                    }
                }
                if let caption {
                    Text(caption)
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(.white.opacity(0.85))
                        .lineLimit(1)
                        .shadow(color: .black.opacity(0.5), radius: 3)
                }
            }
            .shadow(color: .black.opacity(0.5), radius: 6, y: 2)
        }
    }
}

/// Compact winner-only glyph for hero carousels — no caption, smaller.
struct CompactAwardBadgeView: View {
    let asset: String?

    var body: some View {
        if let asset {
            Image(asset)
                .resizable()
                .scaledToFit()
                .frame(height: 36)
                .shadow(color: .black.opacity(0.5), radius: 5, y: 2)
        }
    }
}
