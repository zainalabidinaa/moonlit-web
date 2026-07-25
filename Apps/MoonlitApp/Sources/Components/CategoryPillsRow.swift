import SwiftUI
import MoonlitCore

/// category-style category pills under the hero: "Featured", "Movies",
/// "Shows". Picking Movies or Shows reveals a secondary genre pill row: "All
/// Movies/Shows" stays on Home with the row list filtered to that media kind,
/// while tapping a specific genre (e.g. "Action") opens that genre's own
/// dedicated, curated screen —  — via `onSelectGenre`.
struct CategoryPillsRow: View {
    let genres: [String]
    @Binding var state: HomeCategoryState
    var onSelectGenre: (String) -> Void = { _ in }

    private static let primaryCategories: [HomeCategoryFilter] = [.featured, .movies, .shows]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Self.primaryCategories, id: \.self) { category in
                        pill(title: category.rawValue, isSelected: state.category == category) {
                            if state.category != category {
                                state = HomeCategoryState(category: category)
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
            }

            if state.category != .featured, !genres.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        pill(title: "All \(state.category.rawValue)", isSelected: state.genre == nil) {
                            state.genre = nil
                        }
                        ForEach(genres, id: \.self) { genre in
                            pill(title: genre, isSelected: false) {
                                onSelectGenre(genre)
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                }
            }
        }
    }

    private func pill(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.18)) { action() }
        } label: {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(isSelected ? .black : .white)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(
                    Capsule().fill(isSelected ? Color.white : Color.clear)
                )
                .overlay(
                    Capsule().stroke(Color.white.opacity(isSelected ? 0 : 0.4), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }
}
