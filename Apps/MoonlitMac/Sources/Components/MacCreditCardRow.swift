import SwiftUI
import MoonlitCore

/// A single filmography row for the macOS credits timeline: poster thumbnail,
/// title, "Acting • Series • 80 eps" subtitle, score/votes, and character name.
struct MacCreditCardRow: View {
    let credit: PersonCredit
    let department: String

    var body: some View {
        HStack(spacing: 12) {
            Group {
                if let url = TMDBPersonService.shared.imageURL(path: credit.posterPath, size: "w185") {
                    CachedAsyncImage(url: url) { img in
                        img.resizable().aspectRatio(contentMode: .fill)
                    } placeholder: {
                        posterPlaceholder
                    }
                } else {
                    posterPlaceholder
                }
            }
            .frame(width: 90, height: 130)
            .clipShape(RoundedRectangle(cornerRadius: MoonlitTheme.radiusControl))

            VStack(alignment: .leading, spacing: 4) {
                Text(credit.title)
                    .font(.headline)
                    .foregroundColor(.white)
                    .lineLimit(2)

                Text(credit.subtitle(department: department))
                    .font(.caption)
                    .foregroundColor(MoonlitTheme.textSecondary)

                if let score = credit.voteAverage, score > 0 {
                    HStack(spacing: 4) {
                        Image(systemName: "star.fill")
                            .font(.system(size: 9))
                            .foregroundColor(.yellow)
                        Text(String(format: "%.1f", score))
                            .font(.caption2.weight(.semibold))
                            .foregroundColor(.white)
                        if let votes = credit.voteCount, votes > 0 {
                            Text("\(votes) votes")
                                .font(.caption2)
                                .foregroundColor(MoonlitTheme.textTertiary)
                        }
                    }
                }

                if let character = credit.character, !character.isEmpty {
                    Text("as \(character)")
                        .font(.caption)
                        .foregroundColor(MoonlitTheme.textTertiary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(12)
        .macDarkGlassCard(cornerRadius: MoonlitTheme.radiusCard)
    }

    private var posterPlaceholder: some View {
        Color.white.opacity(0.05)
            .overlay(Image(systemName: "film").foregroundColor(.white.opacity(0.15)))
    }
}
