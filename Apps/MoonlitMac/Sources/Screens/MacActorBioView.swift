import SwiftUI
import MoonlitCore

struct MacActorBioView: View {
    let name: String
    let tmdbPersonId: Int?
    var characterName: String? = nil
    var showName: String? = nil
    var onBack: () -> Void = {}

    @StateObject private var viewModel = ActorBioViewModel()
    @State private var mediaFilter: CreditMediaFilter = .all
    @State private var departmentFilter: String? = nil
    @State private var bioExpanded = false

    var body: some View {
        ZStack(alignment: .top) {
            MacFusionAmbientBackground(
                ambientColor: .clear,
                ambientColor2: .clear,
                isEnabled: true
            )
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if viewModel.isLoading {
                        HStack {
                            Spacer()
                            ProgressView().tint(MoonlitTheme.accent)
                            Spacer()
                        }
                        .frame(minHeight: 200)
                    } else if let person = viewModel.person {
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
            .ignoresSafeArea(.container, edges: .top)
            .task {
                await viewModel.load(personId: tmdbPersonId, name: name)
            }
            .task(id: viewModel.person?.id) {
                guard let knownFor = viewModel.person?.credits.knownFor else { return }
                await viewModel.fetchKnownForBackdrops(knownFor)
            }

            HStack {
                Button { onBack() } label: {
                    Label("Back", systemImage: "chevron.left")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .macDarkGlassCapsule(interactive: true)
                }
                .buttonStyle(.plain)
                Spacer()
            }
            .padding(.horizontal, 28)
            .padding(.top, 48)
        }
        .background(MoonlitTheme.background)
    }

    // MARK: - Bio Header (Harbor-style: large photo left, name/bio right)

    private func bioHeader(_ person: PersonDetails) -> some View {
        HStack(alignment: .top, spacing: 36) {
            Group {
                if let path = person.profileImages.first,
                   let url = TMDBPersonService.shared.imageURL(path: path, size: "w500") {
                    CachedAsyncImage(url: url) { img in
                        img.resizable().scaledToFill()
                    } placeholder: {
                        Color.white.opacity(0.05)
                            .overlay(Image(systemName: "person.fill").foregroundColor(.white.opacity(0.2)))
                    }
                } else {
                    Color.white.opacity(0.05)
                        .overlay(Image(systemName: "person.fill").foregroundColor(.white.opacity(0.2)))
                }
            }
            .frame(width: 320, height: 420)
            .clipShape(RoundedRectangle(cornerRadius: MoonlitTheme.radiusCard))

            VStack(alignment: .leading, spacing: 12) {
                Text((person.knownForDepartment ?? "Acting").uppercased())
                    .font(.system(size: 13, weight: .semibold))
                    .tracking(4)
                    .foregroundColor(.white.opacity(0.45))

                Text(person.name)
                    .font(.system(size: 52, weight: .semibold, design: .serif))
                    .foregroundColor(.white)

                HStack(spacing: 16) {
                    if let birthday = person.birthday {
                        let ageSuffix = age(from: birthday).map { " · \($0)" } ?? ""
                        Text(formatDate(birthday) + ageSuffix)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.white.opacity(0.6))
                    }
                    if let place = person.placeOfBirth {
                        Text(place)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.white.opacity(0.6))
                    }
                }

                if let character = characterName {
                    Text("as \(character)")
                        .font(.subheadline)
                        .foregroundColor(MoonlitTheme.textSecondary)
                }

                if !person.biography.isEmpty {
                    Text(person.biography)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(MoonlitTheme.textSecondary)
                        .lineLimit(bioExpanded ? nil : 8)
                        .animation(.easeInOut(duration: 0.2), value: bioExpanded)
                        .padding(.top, 6)

                    if person.biography.count > 400 {
                        Button { bioExpanded.toggle() } label: {
                            Text(bioExpanded ? "Show Less" : "Show More")
                                .font(.caption.bold())
                                .foregroundColor(.white)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 28)
        .padding(.top, 20)
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
            if let place = person.placeOfBirth {
                infoRow(label: "Place of Birth", value: place)
            }
            if let first = person.alsoKnownAs.first {
                infoRow(label: "Also Known As", value: first)
            }
        }
        .background(MoonlitTheme.surface, in: RoundedRectangle(cornerRadius: MoonlitTheme.radiusCard))
        .padding(.horizontal, 28)
    }

    private func infoRow(label: String, value: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundColor(MoonlitTheme.textTertiary)
                .frame(width: 100, alignment: .leading)
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
                                CachedAsyncImage(url: url) { img in
                                    img.resizable().scaledToFill()
                                } placeholder: {
                                    Color.white.opacity(0.05)
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
            .padding(.horizontal, 28)
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
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()

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
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 28)
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
        .macDarkGlassCapsule(interactive: true)
    }

    private func creditsGroupedList(_ credits: [PersonCredit]) -> some View {
        let grouped: [(String, [PersonCredit])] = {
            var dict: [String: [PersonCredit]] = [:]
            for c in credits { dict[c.year ?? "Unknown", default: []].append(c) }
            return dict.sorted { $0.key > $1.key }
        }()

        return LazyVStack(alignment: .leading, spacing: 20) {
            ForEach(grouped, id: \.0) { year, yearCredits in
                HStack(alignment: .top, spacing: 14) {
                    Text(year)
                        .font(.title2.weight(.heavy))
                        .foregroundColor(.white.opacity(0.35))
                        .frame(width: 64, alignment: .leading)

                    VStack(spacing: 10) {
                        ForEach(yearCredits) { credit in
                            MacCreditCardRow(credit: credit, department: departmentFilter ?? credit.departmentLabel)
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 28)
    }

    // MARK: - Helpers

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.headline.weight(.bold))
            .foregroundColor(.white)
            .padding(.horizontal, 28)
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
