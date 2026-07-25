import SwiftUI
import MoonlitCore

///  "Information" key-value grid: Status, Seasons, First/Last Aired,
/// Networks, Studio, Country, Original Language, Genres, Rating. Rows only show
/// when the underlying data is present — most fields don't apply to movies.
struct InformationGrid: View {
    let detail: MetaDetail

    private var totalEpisodes: Int {
        (detail.seasons ?? []).reduce(0) { $0 + ($1.episodes?.count ?? 0) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Information")
                .font(.headline)
                .foregroundColor(.white)
                .padding(.horizontal, 16)

            LazyVGrid(columns: [GridItem(.flexible(), alignment: .leading), GridItem(.flexible(), alignment: .leading)], alignment: .leading, spacing: 14) {
                if let status = detail.status {
                    row("Status", status)
                }
                if let seasons = detail.seasons, !seasons.isEmpty {
                    row("Seasons", "\(seasons.count) · \(totalEpisodes) episodes")
                }
                if let firstAirDate = detail.firstAirDate {
                    row("First Aired", firstAirDate)
                }
                if let lastAirDate = detail.lastAirDate {
                    row("Last Aired", lastAirDate)
                }
                if let networks = detail.networks, !networks.isEmpty {
                    row("Networks", networks.joined(separator: ", "))
                }
                if let studios = detail.studios, !studios.isEmpty {
                    row("Studio", studios.prefix(3).joined(separator: ", "))
                }
                if let countries = detail.countries, !countries.isEmpty {
                    row("Country", countries.joined(separator: ", "))
                }
                if let language = detail.originalLanguage {
                    row("Original Language", language)
                }
                if let genres = detail.genres, !genres.isEmpty {
                    row("Genres", genres.joined(separator: ", "))
                }
                if let rating = detail.imdbRating {
                    row("Rating", detail.voteCount.map { "\(rating) · \($0.formatted()) votes" } ?? rating)
                }
            }
            .padding(.horizontal, 16)
        }
    }

    private func row(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label.uppercased())
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(MoonlitTheme.textTertiary)
            Text(value)
                .font(.caption)
                .foregroundColor(.white)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
