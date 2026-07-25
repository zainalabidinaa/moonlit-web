import SwiftUI
import MoonlitCore

struct ActorBioScreen: View {
    let name: String
    let tmdbPersonId: Int?
    let characterName: String?
    let showName: String

    @StateObject private var viewModel = ActorBioViewModel()
    @State private var mediaFilter: CreditMediaFilter = .all
    @State private var departmentFilter: String? = nil
    @State private var bioExpanded = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if viewModel.isLoading {
                    LottieLoadingView(size: 44)
                        .frame(maxWidth: .infinity, minHeight: 200)
                } else if let person = viewModel.person {
                    photoStrip(person)

                    bioHeader(person)

                    if person.birthday != nil || person.placeOfBirth != nil
                        || !person.alsoKnownAs.isEmpty || person.knownForDepartment != nil {
                        sectionHeader("Personal Info")
                        infoTable(person)
                    }

                    if !viewModel.knownForItems.isEmpty {
                        sectionHeader("Known For")
                        knownForRow
                    }

                    let credits = person.credits.filtered(media: mediaFilter, department: departmentFilter)
                    if !credits.isEmpty {
                        sectionHeader("Credits")
                        creditFilterMenus(person)
                        creditsGroupedList(credits)
                    }
                } else if let error = viewModel.error {
                    errorView(error)
                }

                Spacer().frame(height: 40)
            }
        }
        .background(MoonlitTheme.background)
        .navigationTitle(name)
#if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
#endif
        .task {
            await viewModel.load(personId: tmdbPersonId, name: name)
        }
        .task(id: viewModel.person?.id) {
            guard let knownFor = viewModel.person?.credits.knownFor else { return }
            await viewModel.fetchKnownForBackdrops(knownFor)
        }
    }

    // MARK: - Photo Strip

    private func photoStrip(_ person: PersonDetails) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(person.profileImages.prefix(6), id: \.self) { path in
                    Group {
                        if let url = TMDBPersonService.shared.imageURL(path: path, size: "w300") {
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
                        }
                    }
                    .frame(width: 110, height: 150)
                    .clipShape(RoundedRectangle(cornerRadius: MoonlitTheme.radiusCard))
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
        }
    }

    // MARK: - Bio Header

    private func bioHeader(_ person: PersonDetails) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(person.name)
                .font(.title3.weight(.bold))
                .foregroundColor(.white)
            if let character = characterName {
                Text("as \(character)")
                    .font(.subheadline)
                    .foregroundColor(MoonlitTheme.textSecondary)
            }
            if !person.biography.isEmpty {
                Text(person.biography)
                    .font(.caption)
                    .foregroundColor(MoonlitTheme.textSecondary)
                    .lineLimit(bioExpanded ? nil : 4)
                    .animation(.easeInOut(duration: 0.2), value: bioExpanded)
                    .padding(.top, 4)

                if person.biography.count > 200 {
                    Button { bioExpanded.toggle() } label: {
                        Text(bioExpanded ? "Show Less" : "Show More")
                            .font(.caption.bold())
                            .foregroundColor(.white)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
    }

    // MARK: - Info Table

    private func infoTable(_ person: PersonDetails) -> some View {
        VStack(spacing: 0) {
            if let department = person.knownForDepartment {
                infoRow(label: "Area of Work", value: department)
            }
            if let birthday = person.birthday {
                let ageSuffix = age(from: birthday).map { " (age \($0))" } ?? ""
                infoRow(label: "Born", value: formatDate(birthday) + ageSuffix)
            }
            if let place = person.placeOfBirth { infoRow(label: "Place of Birth", value: place) }
            if let first = person.alsoKnownAs.first { infoRow(label: "Also Known As", value: first) }
        }
        .glassCard(cornerRadius: MoonlitTheme.radiusCard)
        .padding(.horizontal, 16)
    }

    private func infoRow(label: String, value: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundColor(MoonlitTheme.textTertiary)
                .frame(width: 90, alignment: .leading)
            Text(value)
                .font(.caption)
                .foregroundColor(.white)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private func age(from dateString: String) -> Int? {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        guard let dob = df.date(from: dateString) else { return nil }
        return Calendar.current.dateComponents([.year], from: dob, to: Date()).year
    }

    // MARK: - Known For

    private var knownForRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(viewModel.knownForItems, id: \.id) { credit in
                    VStack(alignment: .leading, spacing: 6) {
                        let imgURL = TMDBPersonService.shared.imageURL(
                            path: credit.posterPath ?? credit.backdropPath, size: "w300"
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
                        .frame(width: 110, height: 165)
                        .clipShape(RoundedRectangle(cornerRadius: MoonlitTheme.radiusControl))

                        Text(credit.title)
                            .font(.caption.weight(.semibold))
                            .foregroundColor(.white)
                            .lineLimit(2)
                            .frame(width: 110, alignment: .leading)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
        }
    }

    // MARK: - Credits

    private func creditFilterMenus(_ person: PersonDetails) -> some View {
        HStack(spacing: 8) {
            Menu {
                Picker("Media", selection: $mediaFilter) {
                    ForEach(CreditMediaFilter.allCases, id: \.self) { filter in
                        Text(filter.rawValue).tag(filter)
                    }
                }
            } label: {
                filterChip(mediaFilter.rawValue)
            }

            Menu {
                Picker("Department", selection: $departmentFilter) {
                    Text("All Departments").tag(String?.none)
                    ForEach(person.credits.departments, id: \.self) { department in
                        Text(department).tag(String?.some(department))
                    }
                }
            } label: {
                filterChip(departmentFilter ?? "All Departments")
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 6)
    }

    private func filterChip(_ title: String) -> some View {
        HStack(spacing: 4) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundColor(.white)
                .lineLimit(1)
            Image(systemName: "chevron.up.chevron.down")
                .font(.system(size: 8, weight: .semibold))
                .foregroundColor(.white.opacity(0.7))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .glassCapsule(interactive: true)
    }

    private func creditsGroupedList(_ credits: [PersonCredit]) -> some View {
        let grouped: [(String, [PersonCredit])] = {
            var dict: [String: [PersonCredit]] = [:]
            for c in credits { dict[c.year ?? "Unknown", default: []].append(c) }
            return dict.sorted { $0.key > $1.key }
        }()

        return LazyVStack(alignment: .leading, spacing: 20) {
            ForEach(grouped, id: \.0) { year, yearCredits in
                HStack(alignment: .top, spacing: 12) {
                    Text(year)
                        .font(.title3.weight(.heavy))
                        .foregroundColor(.white.opacity(0.35))
                        .frame(width: 52, alignment: .leading)

                    VStack(spacing: 10) {
                        ForEach(yearCredits) { credit in
                            CreditCardRow(credit: credit, department: departmentFilter ?? credit.departmentLabel)
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 16)
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
                .foregroundColor(MoonlitTheme.textSecondary)
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
