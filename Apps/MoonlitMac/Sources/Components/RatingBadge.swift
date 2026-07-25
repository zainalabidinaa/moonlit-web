import SwiftUI
import MoonlitCore

/// Shared gold IMDb rating badge — used by the detail hero, media cards, and
/// episode rows so all three read as the same element instead of three
/// slightly different yellow/gold treatments.
struct RatingBadge: View {
    let rating: String
    var compact: Bool = false

    private var displayRating: String {
        rating.replacingOccurrences(of: "/10", with: "")
    }

    var body: some View {
        HStack(spacing: compact ? 3 : 4) {
            Text("IMDb")
                .font(.system(size: compact ? 8 : 10, weight: .black))
                .foregroundColor(MoonlitTheme.ratingGold)
            Image(systemName: "star.fill")
                .font(.system(size: compact ? 8 : 10, weight: .bold))
                .foregroundColor(MoonlitTheme.ratingGold)
            Text(displayRating)
                .font(.system(size: compact ? 10 : 13, weight: .semibold))
                .foregroundColor(.white)
        }
        .padding(.horizontal, compact ? 7 : 10)
        .padding(.vertical, compact ? 4 : 6)
        .background(.black.opacity(0.45), in: Capsule())
        .overlay(Capsule().strokeBorder(MoonlitTheme.ratingGold.opacity(0.28), lineWidth: 0.75))
    }
}
