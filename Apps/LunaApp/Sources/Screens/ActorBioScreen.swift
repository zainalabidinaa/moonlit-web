import SwiftUI
import LunaCore

struct ActorBioScreen: View {
    let name: String
    let tmdbPersonId: Int?
    let characterName: String?
    let showName: String

    @StateObject private var viewModel = ActorBioViewModel()
    @State private var creditsFilter: CreditFilter = .all

    enum CreditFilter: String, CaseIterable {
        case all = "All"
        case acting = "Acting"
        case directing = "Directing"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if viewModel.isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity, minHeight: 200)
                        .tint(.white)
                } else if let person = viewModel.person {
                    bioHeader(person)

                    if person.birthday != nil || person.placeOfBirth != nil || !person.alsoKnownAs.isEmpty {
                        infoTable(person).padding(.top, 16)
                    }

                    if !viewModel.knownForItems.isEmpty {
                        sectionHeader("Known For")
                        knownForRow
                    }

                    let credits = filteredCredits(person)
                    if !credits.isEmpty {
                        sectionHeader("Credits")
                        creditFilterChips
                        creditsGroupedList(credits)
                    }
                } else if let error = viewModel.error {
                    errorView(error)
                }

                Spacer().frame(height: 40)
            }
        }
        .background(LunaTheme.background)
        .navigationTitle(name)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await viewModel.load(personId: tmdbPersonId, name: name)
        }
        .task(id: viewModel.person?.id) {
            guard let knownFor = viewModel.person?.credits.knownFor else { return }
            await viewModel.fetchKnownForBackdrops(knownFor)
        }
    }

    // MARK: - Bio Header

    private func bioHeader(_ person: PersonDetails) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Group {
                if let url = TMDBPersonService.shared.imageURL(path: person.profilePath, size: "w185") {
                    CachedAsyncImage(url: url) { phase in
                        if case .success(let img) = phase {
                            img.resizable().scaledToFill()
                        } else {
                            Color.white.opacity(0.05)
                                .overlay(Image(systemName: "person.fill").foregroundColor(.white.opacity(0.2)))
                        }
                    }
                } else {
                    Color.white.opacity(0.05)
                        .overlay(Image(systemName: "person.fill").foregroundColor(.white.opacity(0.2)))
                }
            }
            .frame(width: 90, height: 120)
            .clipShape(RoundedRectangle(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 4) {
                Text(person.name)
                    .font(.title3.weight(.bold))
                    .foregroundColor(.white)
                if let character = characterName {
                    Text("as \(character)")
                        .font(.subheadline)
                        .foregroundColor(LunaTheme.textSecondary)
                }
                Spacer().frame(height: 4)
                if !person.biography.isEmpty {
                    Text(person.biography)
                        .font(.caption)
                        .foregroundColor(LunaTheme.textSecondary)
                        .lineLimit(6)
                }
            }
        }
        .padding(16)
    }

    // MARK: - Info Table

    private func infoTable(_ person: PersonDetails) -> some View {
        VStack(spacing: 0) {
            if let birthday = person.birthday { infoRow(label: "Born", value: formatDate(birthday)) }
            if let place = person.placeOfBirth { infoRow(label: "Birthplace", value: place) }
            if let first = person.alsoKnownAs.first { infoRow(label: "Also Known As", value: first) }
            if let imdbId = person.imdbId { infoRow(label: "IMDb", value: "imdb.com/name/\(imdbId)", isLink: true) }
        }
        .glassCard(cornerRadius: 12)
        .padding(.horizontal, 16)
    }

    private func infoRow(label: String, value: String, isLink: Bool = false) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundColor(LunaTheme.textTertiary)
                .frame(width: 90, alignment: .leading)
            Text(value)
                .font(.caption)
                .foregroundColor(isLink ? LunaTheme.accent : .white)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    // MARK: - Known For

    private var knownForRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(viewModel.knownForItems, id: \.id) { credit in
                    VStack(alignment: .leading, spacing: 4) {
                        let imgURL = TMDBPersonService.shared.imageURL(
                            path: credit.backdropPath ?? credit.posterPath, size: "w300"
                        )
                        Group {
                            if let url = imgURL {
                                CachedAsyncImage(url: url) { phase in
                                    if case .success(let img) = phase {
                                        img.resizable().scaledToFill()
                                    } else {
                                        Color.white.opacity(0.05)
                                    }
                                }
                            } else {
                                Color.white.opacity(0.05)
                            }
                        }
                        .frame(width: 180, height: 100)
                        .clipShape(RoundedRectangle(cornerRadius: 8))

                        Text(credit.title)
                            .font(.caption.weight(.semibold))
                            .foregroundColor(.white)
                            .lineLimit(1)
                            .frame(width: 180, alignment: .leading)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
        }
    }

    // MARK: - Credits

    private var creditFilterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(CreditFilter.allCases, id: \.self) { filter in
                    Button { creditsFilter = filter } label: {
                        Text(filter.rawValue)
                            .font(.caption.weight(.semibold))
                            .foregroundColor(creditsFilter == filter ? .white : LunaTheme.textSecondary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(creditsFilter == filter ? LunaTheme.accent : Color.white.opacity(0.08))
                            .cornerRadius(20)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 6)
        }
    }

    private func filteredCredits(_ person: PersonDetails) -> [PersonCredit] {
        switch creditsFilter {
        case .all: return person.credits.allCombined
        case .acting: return person.credits.cast.sorted { ($0.releaseDate ?? "") > ($1.releaseDate ?? "") }
        case .directing: return person.credits.crew
            .filter { $0.job?.lowercased().contains("direct") == true }
            .sorted { ($0.releaseDate ?? "") > ($1.releaseDate ?? "") }
        }
    }

    private func creditsGroupedList(_ credits: [PersonCredit]) -> some View {
        let grouped: [(String, [PersonCredit])] = {
            var dict: [String: [PersonCredit]] = [:]
            for c in credits { dict[c.year ?? "Unknown", default: []].append(c) }
            return dict.sorted { $0.key > $1.key }
        }()

        return LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
            ForEach(grouped, id: \.0) { year, yearCredits in
                Section {
                    ForEach(yearCredits) { credit in
                        creditRow(credit)
                        if credit.id != yearCredits.last?.id {
                            Divider().background(Color.white.opacity(0.06)).padding(.leading, 62)
                        }
                    }
                } header: {
                    Text(year)
                        .font(.caption.weight(.bold))
                        .foregroundColor(LunaTheme.textTertiary)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(LunaTheme.background)
                }
            }
        }
        .padding(.horizontal, 16)
    }

    private func creditRow(_ credit: PersonCredit) -> some View {
        HStack(spacing: 10) {
            Group {
                if let url = TMDBPersonService.shared.imageURL(path: credit.posterPath, size: "w92") {
                    CachedAsyncImage(url: url) { phase in
                        if case .success(let img) = phase {
                            img.resizable().scaledToFill()
                        } else {
                            Color.white.opacity(0.05)
                                .overlay(Image(systemName: "film").foregroundColor(.white.opacity(0.15)))
                        }
                    }
                } else {
                    Color.white.opacity(0.05)
                        .overlay(Image(systemName: "film").foregroundColor(.white.opacity(0.15)))
                }
            }
            .frame(width: 38, height: 54)
            .clipShape(RoundedRectangle(cornerRadius: 5))

            VStack(alignment: .leading, spacing: 2) {
                Text(credit.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                HStack(spacing: 4) {
                    Text(credit.creditType)
                        .font(.caption)
                        .foregroundColor(LunaTheme.textTertiary)
                    if let eps = credit.episodeCount, credit.mediaType == "tv" {
                        Text("· \(eps) ep")
                            .font(.caption)
                            .foregroundColor(LunaTheme.textTertiary)
                    }
                }
                if let character = credit.character, !character.isEmpty {
                    Text("as \(character)")
                        .font(.system(size: 11))
                        .foregroundColor(LunaTheme.textTertiary)
                        .lineLimit(1)
                }
            }

            Spacer()

            if let score = credit.voteAverage, score > 0 {
                VStack(spacing: 0) {
                    Text(String(format: "%.1f", score))
                        .font(.caption.weight(.bold))
                        .foregroundColor(.white)
                    Text("★")
                        .font(.system(size: 8))
                        .foregroundColor(.yellow)
                }
            }
        }
        .padding(.vertical, 8)
    }

    // MARK: - Helpers

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.headline.weight(.bold))
            .foregroundColor(.white)
            .padding(.horizontal, 16)
            .padding(.top, 24)
            .padding(.bottom, 8)
    }

    private func errorView(_ error: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle")
                .font(.largeTitle)
                .foregroundColor(.orange)
            Text(error)
                .font(.subheadline)
                .foregroundColor(LunaTheme.textSecondary)
        }
        .frame(maxWidth: .infinity, minHeight: 200)
    }

    private func formatDate(_ dateString: String) -> String {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        guard let date = df.date(from: dateString) else { return dateString }
        df.dateStyle = .long
        df.dateFormat = nil
        return df.string(from: date)
    }
}

// MARK: - ViewModel

@MainActor
private class ActorBioViewModel: ObservableObject {
    @Published var person: PersonDetails?
    @Published var knownForItems: [PersonCredit] = []
    @Published var isLoading = false
    @Published var error: String?

    func load(personId: Int?, name: String) async {
        isLoading = true
        error = nil
        do {
            let id: Int
            if let personId {
                id = personId
            } else if let found = try await TMDBPersonService.shared.personId(forName: name) {
                id = found
            } else {
                error = "Could not find '\(name)' on TMDB"
                isLoading = false
                return
            }
            person = try await TMDBPersonService.shared.personDetails(id: id)
        } catch TMDBPersonError.noAPIKey {
            error = "TMDB API key not configured. Add it in Settings → Metadata."
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }

    func fetchKnownForBackdrops(_ credits: [PersonCredit]) async {
        var items = credits
        await withTaskGroup(of: (Int, String?).self) { group in
            for (idx, credit) in items.enumerated() {
                group.addTask {
                    let backdrop = await TMDBPersonService.shared.backdrop(for: credit)
                    return (idx, backdrop)
                }
            }
            for await (idx, backdrop) in group {
                items[idx].backdropPath = backdrop
            }
        }
        knownForItems = items
    }
}
