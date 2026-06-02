import SwiftUI
import LunaCore

struct ContentCard: View {
    let item: MetaPreview
    let row: CatalogRow?
    let index: Int?
    @State private var imageFailed = false

    init(item: MetaPreview, row: CatalogRow? = nil, index: Int? = nil) {
        self.item = item
        self.row = row
        self.index = index
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 8)
                    .fill(LunaTheme.surfaceElevated)
                    .frame(width: cardWidth, height: cardHeight)

                if let posterURL = item.poster, let url = URL(string: posterURL), !imageFailed {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: cardWidth, height: cardHeight)
                                .clipped()
                                .cornerRadius(8)
                        case .failure:
                            placeholderView
                        case .empty:
                            ProgressView().tint(LunaTheme.accent)
                        @unknown default:
                            placeholderView
                        }
                    }
                } else {
                    placeholderView
                }

                if let glowEnabled = row?.focusGlowEnabled, glowEnabled {
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(LunaTheme.accent.opacity(0.3), lineWidth: 2)
                        .frame(width: cardWidth, height: cardHeight)
                }

                ForEach(item.derivedBadges(index: index)) { badge in
                    BadgeView(badge: badge)
                        .padding(4)
                }
            }

            Text(item.name)
                .font(.caption)
                .foregroundColor(.white)
                .lineLimit(2)
                .frame(width: cardWidth)

            if let rating = item.imdbRating {
                Text(rating)
                    .font(.caption2)
                    .foregroundColor(LunaTheme.textSecondary)
            }
        }
    }

    private var placeholderView: some View {
        VStack(spacing: 4) {
            Image(systemName: item.type == .movie ? "film" : "tv")
                .font(.title2)
                .foregroundColor(LunaTheme.textTertiary)
            Text(item.name)
                .font(.caption2)
                .foregroundColor(LunaTheme.textSecondary)
                .lineLimit(2)
                .padding(.horizontal, 4)
                .multilineTextAlignment(.center)
        }
        .frame(width: cardWidth, height: cardHeight)
    }

    private var resolvedShape: PosterShape? {
        if let rowShape = row?.tileShape {
            return PosterShape(rawValue: rowShape)
        }
        return item.posterShape
    }

    private var cardWidth: CGFloat {
        switch resolvedShape {
        case .landscape: return 200
        case .square:    return 140
        case .poster:    return 120
        }
    }

    private var cardHeight: CGFloat {
        switch resolvedShape {
        case .landscape: return 112
        case .square:    return 140
        case .poster:    return 180
        }
    }
}

struct BadgeView: View {
    let badge: ContentBadge

    var body: some View {
        Text(badge.text)
            .font(.system(size: 10, weight: .bold))
            .foregroundColor(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(badgeColor.opacity(0.85))
            .cornerRadius(4)
    }

    private var badgeColor: Color {
        switch badge.style {
        case .accent: return LunaTheme.accent
        case .warning: return .orange
        case .info: return .blue
        }
    }
}
