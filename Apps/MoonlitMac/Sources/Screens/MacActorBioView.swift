import SwiftUI
import MoonlitCore

struct MacActorBioView: View {
    let name: String
    let tmdbPersonId: Int?
    var characterName: String? = nil
    var showName: String? = nil
    var onBack: () -> Void = {}

    @StateObject private var viewModel = ActorBioViewModel()
    @StateObject private var awardsService = PersonAwardsMetadataService.shared
    @State private var mediaFilter: CreditMediaFilter = .all
    @State private var departmentFilter: String? = nil
    @State private var bioExpanded = false
    @State private var openAwardBody: AwardBody?
    @State private var hoveredKnownForID: Int?

    var body: some View {
        ZStack(alignment: .top) {
            actorBackground
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if viewModel.isLoading {
                        HStack {
                            Spacer()
                            MacStrokeSpinner(size: 28, color: MoonlitTheme.accent)
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
            .task(id: viewModel.person?.imdbId) {
                guard let imdbId = viewModel.person?.imdbId else { return }
                await awardsService.fetch(imdbId: imdbId)
            }

            HStack {
                Button("Back", systemImage: "chevron.left", action: onBack)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .macDarkGlassCapsule(interactive: true)
                    .buttonStyle(.plain)
                    .keyboardShortcut(.cancelAction)
                Spacer()
            }
            .padding(.horizontal, 28)
            .padding(.top, 22)
        }
        .background(MoonlitTheme.background)
    }

    // MARK: - Bio Header (: large photo left, name/bio right)

    private var actorBackdropURL: URL? {
        guard let path = viewModel.knownForItems.first(where: { $0.backdropPath != nil })?.backdropPath else {
            return nil
        }
        return TMDBPersonService.shared.imageURL(path: path, size: "w1280")
    }

    /// a neutral person page background recipe, translated directly from
    /// `views/person.tsx`: a known-for backdrop fills the top 70% of the
    /// viewport, scaled 1.1x, blurred by 80px, saturated to 1.3, shown at
    /// 45% opacity, then faded through canvas at 40% / 70% / 100%.
    private var actorBackground: some View {
        GeometryReader { geometry in
            ZStack(alignment: .top) {
                MoonlitTheme.background

                if let actorBackdropURL {
                    CachedAsyncImage(url: actorBackdropURL, maxDimension: 700) { image in
                        image
                            .resizable()
                            .scaledToFill()
                    } placeholder: {
                        Color.clear
                    }
                    .frame(width: geometry.size.width, height: geometry.size.height * 0.7)
                    .clipped()
                    .scaleEffect(1.1)
                    .blur(radius: 80)
                    .saturation(1.3)
                    .opacity(0.45)
                    .mask(
                        LinearGradient(
                            stops: [
                                .init(color: .black.opacity(0.60), location: 0),
                                .init(color: .black.opacity(0.30), location: 0.55),
                                .init(color: .clear, location: 1),
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )

                    LinearGradient(
                        stops: [
                            .init(color: MoonlitTheme.background.opacity(0.40), location: 0),
                            .init(color: MoonlitTheme.background.opacity(0.70), location: 0.48),
                            .init(color: MoonlitTheme.background, location: 1),
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: geometry.size.height * 0.7)
                }
            }
        }
        .ignoresSafeArea()
    }

    private func bioHeader(_ person: PersonDetails) -> some View {
        HStack(alignment: .center, spacing: 52) {
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
            .frame(width: 288, height: 432)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .shadow(color: .black.opacity(0.58), radius: 30, y: 18)

            VStack(alignment: .leading, spacing: 12) {
                Text((person.knownForDepartment ?? "Acting").uppercased())
                    .font(.system(size: 12, weight: .semibold))
                    .tracking(5)
                    .foregroundColor(.white.opacity(0.45))

                Text(person.name)
                    .font(.system(size: 78, weight: .medium, design: .serif))
                    .foregroundColor(.white)
                    .tracking(-2)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)

                HStack(spacing: 16) {
                    if let birthday = person.birthday {
                        let ageSuffix = age(from: birthday).map { " · \($0)" } ?? ""
                        Text("Born \(formatDate(birthday))" + ageSuffix)
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(.white.opacity(0.6))
                    }
                    if let place = person.placeOfBirth {
                        Text(place)
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(.white.opacity(0.6))
                    }
                }

                if let imdbId = person.imdbId,
                   let summary = awardsService.summary(forImdbId: imdbId),
                   !summary.bodiesRepresented.isEmpty {
                    laurelStrip(summary)
                        .padding(.top, 2)
                }

                if let character = characterName {
                    Text("as \(character)")
                        .font(.subheadline)
                        .foregroundColor(MoonlitTheme.textSecondary)
                }

                if !person.biography.isEmpty {
                    Text(person.biography)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(MoonlitTheme.textSecondary)
                        .lineSpacing(4)
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
        .padding(.horizontal, 48)
        .padding(.top, 96)
        .padding(.bottom, 22)
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
        .background(Color.black.opacity(0.28), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Color.white.opacity(0.08)))
        .padding(.horizontal, 48)
    }

    private func infoRow(label: String, value: String) -> some View {
        HStack(alignment: .top, spacing: 22) {
            Text(label)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(MoonlitTheme.textTertiary)
                .frame(width: 120, alignment: .leading)
            Text(value)
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
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
            HStack(spacing: 16) {
                ForEach(viewModel.knownForItems, id: \.id) { credit in
                    VStack(alignment: .leading, spacing: 6) {
                        let imgURL = knownForArtworkURL(credit)
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
                        .frame(width: 190, height: 285)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .shadow(color: .black.opacity(0.38), radius: 18, y: 10)

                        Text(credit.title)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(.white)
                            .lineLimit(2)
                            .frame(width: 190, alignment: .leading)
                        Text(credit.year ?? "")
                            .font(.system(size: 13))
                            .foregroundColor(.white.opacity(0.5))
                    }
                    .offset(y: hoveredKnownForID == credit.id ? -8 : 0)
                    .macTileGlow(
                        isHovering: hoveredKnownForID == credit.id,
                        artworkURL: knownForArtworkURL(credit),
                        cornerRadius: 14
                    )
                    .animation(.spring(response: 0.3, dampingFraction: 0.82), value: hoveredKnownForID)
                    .onHover { hovering in
                        hoveredKnownForID = hovering ? credit.id : nil
                    }
                }
            }
            .padding(.horizontal, 48)
            .padding(.vertical, 10)
        }
    }

    private func knownForArtworkURL(_ credit: PersonCredit) -> URL? {
        TMDBPersonService.shared.imageURL(
            path: credit.posterPath ?? credit.backdropPath,
            size: "w300"
        )
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
        .padding(.horizontal, 48)
        .padding(.bottom, 12)
    }

    private func filterChip(_ title: String) -> some View {
        HStack(spacing: 4) {
            Text(title)
                .font(.system(size: 13.5, weight: .semibold))
                .foregroundColor(.white)
                .lineLimit(1)
            Image(systemName: "chevron.up.chevron.down")
                .font(.system(size: 8, weight: .semibold))
                .foregroundColor(.white.opacity(0.7))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .macDarkGlassCapsule(interactive: true)
    }

    // MARK: - Awards (laurel chips + win-history popover)

    private func laurelStrip(_ summary: AwardSummary) -> some View {
        HStack(spacing: 10) {
            ForEach(summary.bodiesRepresented, id: \.self) { body in
                laurelChip(body, summary: summary)
            }
        }
    }

    private func laurelChip(_ body: AwardBody, summary: AwardSummary) -> some View {
        let wins = summary.wins(for: body)
        let noms = summary.nominations(for: body)
        let isOpen = openAwardBody == body

        return Button {
            openAwardBody = isOpen ? nil : body
        } label: {
            HStack(spacing: 8) {
                HStack(spacing: -5) {
                    Image(systemName: "laurel.leading")
                        .font(.system(size: 24))
                    if let asset = body.assetName {
                        Image(asset)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 18, height: 18)
                    }
                    Image(systemName: "laurel.trailing")
                        .font(.system(size: 24))
                }
                .foregroundColor(body.tintColor)

                VStack(alignment: .leading, spacing: 1) {
                    Text(laurelHeadline(wins: wins.count, noms: noms.count))
                        .font(.system(size: 12.5, weight: .bold))
                        .foregroundColor(.white)
                    Text(shortBodyName(body).uppercased())
                        .font(.system(size: 8.5, weight: .semibold))
                        .tracking(1.4)
                        .foregroundColor(.white.opacity(0.45))
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Color.white.opacity(isOpen ? 0.08 : 0.04), in: Capsule())
            .overlay(Capsule().strokeBorder(isOpen ? body.tintColor.opacity(0.5) : Color.white.opacity(0.08), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .popover(isPresented: Binding(
            get: { openAwardBody == body },
            set: { if !$0 { openAwardBody = nil } }
        ), arrowEdge: .bottom) {
            awardHistoryPopover(body, wins: wins, noms: noms)
        }
    }

    private func laurelHeadline(wins: Int, noms: Int) -> String {
        if wins > 0 { return "\(wins) win\(wins == 1 ? "" : "s")" }
        return "\(noms) nom\(noms == 1 ? "" : "s")"
    }

    private func shortBodyName(_ body: AwardBody) -> String {
        switch body {
        case .oscar: return "Oscar"
        case .emmy: return "Emmy"
        case .goldenGlobe: return "Golden Globe"
        case .sag: return "SAG"
        case .bafta: return "BAFTA"
        case .criticsChoice: return "Critics' Choice"
        case .cannes: return "Cannes"
        case .venice: return "Venice"
        case .berlin: return "Berlin"
        }
    }

    private func awardHistoryPopover(_ body: AwardBody, wins: [AwardEntry], noms: [AwardEntry]) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(body.hubTitle)
                .font(.system(size: 13.5, weight: .bold))
                .foregroundColor(.white)
            Text(summaryLine(wins: wins.count, noms: noms.count))
                .font(.system(size: 10.5, weight: .medium))
                .foregroundColor(.white.opacity(0.5))
                .padding(.bottom, 8)

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array((wins + noms).enumerated()), id: \.offset) { index, entry in
                        awardHistoryRow(entry, won: index < wins.count)
                        if index < wins.count + noms.count - 1 {
                            Divider().overlay(Color.white.opacity(0.08))
                        }
                    }
                }
            }
            .frame(maxHeight: 340)
        }
        .padding(18)
        .frame(width: 390)
        .background(Color(red: 0.09, green: 0.09, blue: 0.1))
    }

    private func awardHistoryRow(_ entry: AwardEntry, won: Bool) -> some View {
        HStack(alignment: .center, spacing: 12) {
            awardWorkPoster(entry)
            if let year = entry.year {
                Text(String(year))
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundColor(.white.opacity(0.4))
                    .monospacedDigit()
            }
            Text(won ? "WON" : "NOM")
                .font(.system(size: 8, weight: .heavy))
                .tracking(0.6)
                .foregroundColor(won ? MoonlitTheme.ratingGold : .white.opacity(0.55))
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(
                    (won ? MoonlitTheme.ratingGold.opacity(0.18) : Color.white.opacity(0.07)),
                    in: RoundedRectangle(cornerRadius: 4)
                )
            VStack(alignment: .leading, spacing: 1) {
                if let work = entry.workTitle {
                    Text(work)
                        .font(.system(size: 13.5, weight: .semibold))
                        .foregroundColor(.white)
                        .lineLimit(1)
                }
                Text(entry.category)
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.5))
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private func awardWorkPoster(_ entry: AwardEntry) -> some View {
        let credits = viewModel.person?.credits.allCombined ?? []
        let titles = credits.map(\.title)
        let matchedCredit = entry.workTitle
            .flatMap { ActorAwardWorkMatcher.matchIndex(for: $0, in: titles) }
            .map { credits[$0] }
        Group {
            if let url = TMDBPersonService.shared.imageURL(path: matchedCredit?.posterPath, size: "w185") {
                CachedAsyncImage(url: url) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    Color.white.opacity(0.06)
                }
            } else {
                Color.white.opacity(0.06)
                    .overlay(Image(systemName: "film").foregroundColor(.white.opacity(0.28)))
            }
        }
        .frame(width: 42, height: 60)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }

    private func summaryLine(wins: Int, noms: Int) -> String {
        var parts: [String] = []
        if wins > 0 { parts.append("\(wins) win\(wins == 1 ? "" : "s")") }
        if noms > 0 { parts.append("\(noms) nomination\(noms == 1 ? "" : "s")") }
        return parts.joined(separator: " · ")
    }

    // MARK: - Credits timeline (year rail + compact cards)

    private func creditsGroupedList(_ credits: [PersonCredit]) -> some View {
        let grouped: [(String, [PersonCredit])] = {
            var dict: [String: [PersonCredit]] = [:]
            for c in credits { dict[c.year ?? "Unknown", default: []].append(c) }
            return dict.sorted { $0.key > $1.key }
        }()

        return LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(grouped, id: \.0) { year, yearCredits in
                HStack(alignment: .top, spacing: 16) {
                    Text(year)
                        .font(.system(size: 20, weight: .regular, design: .serif))
                        .foregroundColor(.white.opacity(0.45))
                        .monospacedDigit()
                        .frame(width: 62, alignment: .trailing)
                        .padding(.top, 12)

                    // Quiet rail: a dot per year group on a continuous hairline.
                    VStack(spacing: 0) {
                        Circle()
                            .fill(Color.white.opacity(0.4))
                            .frame(width: 7, height: 7)
                            .padding(.top, 17)
                        Rectangle()
                            .fill(Color.white.opacity(0.07))
                            .frame(width: 1)
                            .frame(maxHeight: .infinity)
                    }
                    .frame(width: 7)

                    VStack(spacing: 8) {
                        ForEach(yearCredits) { credit in
                            timelineRow(credit)
                        }
                    }
                    .padding(.bottom, 22)
                }
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 48)
    }

    private func timelineRow(_ credit: PersonCredit) -> some View {
        HStack(spacing: 12) {
            Group {
                if let url = TMDBPersonService.shared.imageURL(path: credit.posterPath, size: "w185") {
                    CachedAsyncImage(url: url) { img in
                        img.resizable().aspectRatio(contentMode: .fill)
                    } placeholder: {
                        Color.white.opacity(0.05)
                    }
                } else {
                    Color.white.opacity(0.05)
                }
            }
            .frame(width: 54, height: 81)
            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(credit.title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                Text(timelineSubtitle(credit))
                    .font(.system(size: 13.5))
                    .foregroundColor(.white.opacity(0.45))
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            if let score = credit.voteAverage, score > 0 {
                HStack(spacing: 3) {
                    Image(systemName: "star.fill").font(.system(size: 8.5))
                    Text(String(format: "%.1f", score))
                }
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(MoonlitTheme.ratingGold)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .background(Color.black.opacity(0.26), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.white.opacity(0.05)))
    }

    private func timelineSubtitle(_ credit: PersonCredit) -> String {
        var parts: [String] = []
        if let role = credit.character ?? credit.job, !role.isEmpty {
            parts.append(role)
        }
        parts.append(credit.mediaType == "tv" ? "Series" : "Movie")
        if let eps = credit.episodeCount, eps > 0 {
            parts.append("\(eps) ep\(eps == 1 ? "" : "s")")
        }
        return parts.joined(separator: " · ")
    }

    // MARK: - Helpers

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 24, weight: .semibold, design: .serif))
            .foregroundColor(.white)
            .padding(.horizontal, 48)
            .padding(.top, 38)
            .padding(.bottom, 16)
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

enum ActorAwardWorkMatcher {
    static func matchIndex(for workTitle: String, in titles: [String]) -> Int? {
        let target = normalized(workTitle)
        return titles.firstIndex { normalized($0) == target }
    }

    private static func normalized(_ value: String) -> String {
        String(value.lowercased().filter { $0.isLetter || $0.isNumber })
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
