import SwiftUI
import MoonlitCore

///  "Information" key-value grid: crew (Directors, Creators, Writers,
/// Producers, Cinematography, Music, Editors) followed by Status, Seasons,
/// First/Last Aired, Networks, Studio, Country, Original Language, Genres, Rating.
/// Rows only show when the underlying data is present — most fields don't apply
/// to movies.
struct MacInformationGrid: View {
    let detail: MetaDetail

    private var totalEpisodes: Int {
        (detail.seasons ?? []).reduce(0) { $0 + ($1.episodes?.count ?? 0) }
    }

    /// Crew categories rendered as label + comma-joined names, in their own
    /// grid above the factual info grid. Only non-empty categories appear.
    private var crew: [(title: String, people: [Person])] {
        [
            ("Directors", detail.director ?? []),
            ("Creators", detail.creators ?? []),
            ("Writers", detail.writer ?? []),
            ("Producers", detail.producers ?? []),
            ("Cinematography", detail.cinematographers ?? []),
            ("Music", detail.composers ?? []),
            ("Editors", detail.editors ?? []),
        ].filter { !$0.people.isEmpty }
    }

    private var gridColumns: [GridItem] {
        [GridItem(.flexible(), alignment: .leading), GridItem(.flexible(), alignment: .leading), GridItem(.flexible(), alignment: .leading)]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            if !crew.isEmpty {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Crew")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundColor(.white)

                    LazyVGrid(columns: gridColumns, alignment: .leading, spacing: 16) {
                        ForEach(crew, id: \.title) { category in
                            row(category.title, category.people.map(\.name).joined(separator: ", "))
                        }
                    }
                }
            }

            VStack(alignment: .leading, spacing: 16) {
                Text("Information")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(.white)

                LazyVGrid(columns: gridColumns, alignment: .leading, spacing: 16) {
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
            }
        }
    }

    private func row(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label.uppercased())
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(MoonlitTheme.textTertiary)
            Text(value)
                .font(.subheadline)
                .foregroundColor(.white)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
