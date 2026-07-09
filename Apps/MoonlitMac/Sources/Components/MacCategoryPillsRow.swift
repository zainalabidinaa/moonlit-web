import SwiftUI
import MoonlitCore

/// HBO Max/Harbor-style category pills under the hero. On the Home tab this shows
/// the primary "Featured / Movies / Shows" selector plus a secondary genre rail
/// once Movies or Shows is picked. On the dedicated Movies/Series tabs the primary
/// row is redundant with the top nav, so it's hidden and only the labeled genre
/// rail is shown ("Browse Movies" / "Browse Series").
struct MacCategoryPillsRow: View {
    let genres: [String]
    @Binding var state: HomeCategoryState
    var hidePrimaryCategories: Bool = false
    var browseTitle: String? = nil
    var onSelectGenre: (String) -> Void = { _ in }

    private static let primaryCategories: [HomeCategoryFilter] = [.featured, .movies, .shows]

    private var showsGenreRail: Bool {
        (hidePrimaryCategories || state.category != .featured) && !genres.isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if !hidePrimaryCategories {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(Self.primaryCategories, id: \.self) { category in
                            pill(title: category.rawValue, isSelected: state.category == category) {
                                if state.category != category {
                                    state = HomeCategoryState(category: category)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 32)
                }
            }

            if showsGenreRail {
                VStack(alignment: .leading, spacing: 11) {
                    if let browseTitle {
                        Text(browseTitle)
                            .font(.system(size: 20, weight: .bold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 32)
                    }

                    genreRail
                }
            }
        }
    }

    private var genreRail: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                pill(title: "All", isSelected: state.genre == nil) {
                    state.genre = nil
                }
                ForEach(genres, id: \.self) { genre in
                    pill(title: genre, isSelected: false) {
                        onSelectGenre(genre)
                    }
                }
            }
            .padding(.horizontal, 32)
        }
        .mask(
            LinearGradient(
                stops: [
                    .init(color: .black, location: 0.0),
                    .init(color: .black, location: 0.9),
                    .init(color: .clear, location: 1.0),
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
        )
    }

    private func pill(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.18)) { action() }
        } label: {
            Text(title)
                .font(.system(size: 13.5, weight: .semibold))
                .foregroundColor(isSelected ? Color(red: 0.14, green: 0.11, blue: 0.02) : .white.opacity(0.9))
                .padding(.horizontal, 15)
                .padding(.vertical, 8)
                .background(
                    Capsule().fill(isSelected ? MoonlitTheme.harborGold : Color.white.opacity(0.08))
                )
        }
        .buttonStyle(.plain)
    }
}
