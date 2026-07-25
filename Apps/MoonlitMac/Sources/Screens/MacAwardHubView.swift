import SwiftUI
import MoonlitCore

/// Cinematic awards hub (): a mosaic hero with laurel + serif title,
/// a Gallery / Full-list toggle, the winning films grid, and people rails for
/// the actors, directors and writers behind the winners.
struct MacAwardHubView: View {
    let award: AwardBody
    let row: CatalogRow
    let onBack: () -> Void
    let onSelectMedia: (MetaPreview) -> Void

    @StateObject private var catalogRepo = CatalogRepository.shared
    @StateObject private var collectionRepo = CollectionRepository.shared
    @StateObject private var addonRepo = AddonRepository.shared
    @StateObject private var profileManager = ProfileManager.shared

    @State private var mode: Mode = .gallery
    @State private var searchText = ""
    @State private var people: AwardPeople = .empty
    @State private var isLoadingPeople = true
    @State private var isLoadingInitial = false
    @State private var showAllWinners = false

    private enum Mode { case gallery, list }
    private let previewCount = 18

    private var displayRow: CatalogRow {
        catalogRepo.allFolderRows[CatalogRepository.normalizedFolderId(row.id)] ?? row
    }

    private var winners: [MetaPreview] { displayRow.items }

    private var filteredWinners: [MetaPreview] {
        guard !searchText.isEmpty else { return winners }
        return winners.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    private var gridWinners: [MetaPreview] {
        mode == .gallery && !showAllWinners ? Array(winners.prefix(previewCount)) : filteredWinners
    }

    private var tint: Color { award.tintColor }

    var body: some View {
        ZStack(alignment: .top) {
            MacFusionAmbientBackground(ambientColor: tint, ambientColor2: tint, isEnabled: true, intensity: 0.5)
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    hero
                        .zIndex(1)
                    description
                    modeToggle
                        .padding(.horizontal, 28)
                        .padding(.top, 22)

                    if mode == .list {
                        listSearch
                    }

                    if !(isLoadingInitial && winners.isEmpty) {
                        filmGrid
                        if mode == .gallery {
                            peopleRails
                        }
                    }

                    Spacer().frame(height: 56)
                }
            }
            .ignoresSafeArea(.container, edges: .top)
            .task(id: row.id) {
                await loadInitialIfNeeded()
                await loadPeople()
            }

            if isLoadingInitial && winners.isEmpty {
                MacLoadingView(size: 44)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(MoonlitTheme.background)
    }

    // MARK: - Hero

    private var heroImages: [URL] {
        var seen = Set<String>()
        var urls: [URL] = []
        for item in winners {
            let s = item.artworkString(preferring: .landscape) ?? item.backdrop ?? item.banner
            if let s, !s.isEmpty, !seen.contains(s), let u = URL(string: s) {
                seen.insert(s); urls.append(u)
            }
            if urls.count >= 10 { break }
        }
        return urls
    }

    private var hero: some View {
        ZStack(alignment: .bottomLeading) {
            // Mosaic of winner backdrops, faded out toward the left where the
            // title sits (mirrors the reference award hero).
            let images = heroImages
            if images.count >= 3 {
                GeometryReader { geo in
                    let cols = 5, rows = 2
                    let cellW = geo.size.width / CGFloat(cols)
                    let cellH = geo.size.height / CGFloat(rows)
                    ForEach(0..<(cols * rows), id: \.self) { i in
                        let url = images[i % images.count]
                        CachedAsyncImage(url: url) { image in
                            image.resizable().aspectRatio(contentMode: .fill)
                        } placeholder: { MoonlitTheme.surfaceElevated }
                        .frame(width: cellW - 4, height: cellH - 4)
                        .clipped()
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .opacity(0.82)
                        .position(x: cellW * (CGFloat(i % cols) + 0.5), y: cellH * (CGFloat(i / cols) + 0.5))
                    }
                }
                .mask(
                    LinearGradient(
                        stops: [.init(color: .clear, location: 0.06),
                                .init(color: .black, location: 0.62)],
                        startPoint: .leading, endPoint: .trailing
                    )
                )
            }

            // Tint + darkening washes.
            RadialGradient(colors: [tint.opacity(0.22), .clear], center: .init(x: 0.16, y: 0.3),
                           startRadius: 0, endRadius: 420)
            LinearGradient(colors: [MoonlitTheme.background, MoonlitTheme.background.opacity(0.7), .clear],
                           startPoint: .leading, endPoint: .trailing)
            LinearGradient(colors: [MoonlitTheme.background, .clear, MoonlitTheme.background.opacity(0.15)],
                           startPoint: .bottom, endPoint: .top)

            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 12) {
                    Text(award.shorthand.uppercased())
                        .font(.system(size: 11, weight: .bold))
                        .tracking(3.5)
                        .foregroundColor(.white.opacity(0.55))
                    Text(award.hubTitle)
                        .font(.system(size: 56, weight: .semibold, design: .serif))
                        .foregroundColor(.white)
                        .shadow(color: .black.opacity(0.45), radius: 18, y: 2)
                    if award.founded > 0 {
                        HStack(spacing: 10) {
                            Text("Founded \(String(award.founded))")
                                .foregroundColor(.white.opacity(0.7))
                            Text("·").foregroundColor(.white.opacity(0.3))
                            Text("\(currentYear - award.founded) years")
                                .foregroundColor(tint)
                        }
                        .font(.system(size: 13, weight: .medium))
                    }
                }
                Spacer()
                laurel
                    .padding(.trailing, 24)
            }
            .padding(.horizontal, 28)
            .padding(.bottom, 26)
        }
        .frame(height: 380)
        .clipped()
        // Short gradient bleeding past the hero's clip line: full background
        // color exactly at the boundary, dissolving in both directions, so the
        // mosaic can never end on a hard edge. Painted after .clipped() (so it
        // escapes the clip) and the hero is zIndex(1) so the bleed lays over
        // the top of the section below.
        .overlay(alignment: .bottom) {
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0.0),
                    .init(color: MoonlitTheme.background, location: 0.5),
                    .init(color: MoonlitTheme.background.opacity(0), location: 1.0),
                ],
                startPoint: .top, endPoint: .bottom
            )
            .frame(height: 120)
            .offset(y: 60)
            .allowsHitTesting(false)
        }
    }

    private var laurel: some View {
        HStack(spacing: -4) {
            Image(systemName: "laurel.leading")
                .font(.system(size: 96))
                .foregroundColor(tint)
            if let asset = award.assetName {
                Image(asset).resizable().scaledToFit().frame(height: 76)
            }
            Image(systemName: "laurel.trailing")
                .font(.system(size: 96))
                .foregroundColor(tint)
        }
        .shadow(color: .black.opacity(0.5), radius: 12, y: 4)
    }

    private var currentYear: Int { Calendar.current.component(.year, from: Date()) }

    private var description: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(award.about)
                .font(.system(size: 15))
                .foregroundColor(.white.opacity(0.72))
                .lineSpacing(4)
                .frame(maxWidth: 720, alignment: .leading)
            Text(award.tagline.uppercased())
                .font(.system(size: 11, weight: .semibold))
                .tracking(1.5)
                .foregroundColor(.white.opacity(0.4))
        }
        .padding(.horizontal, 28)
        .padding(.top, 20)
    }

    // MARK: - Mode toggle

    private var modeToggle: some View {
        HStack(spacing: 4) {
            toggleButton(.gallery, "Gallery", "square.grid.2x2")
            toggleButton(.list, "Full list", "list.bullet")
        }
        .padding(4)
        .background(Color.white.opacity(0.06), in: Capsule())
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
    }

    private func toggleButton(_ m: Mode, _ label: String, _ icon: String) -> some View {
        Button { withAnimation(.easeOut(duration: 0.2)) { mode = m } } label: {
            HStack(spacing: 6) {
                Image(systemName: icon).font(.system(size: 12, weight: .semibold))
                Text(label).font(.system(size: 13, weight: .semibold))
            }
            .foregroundColor(mode == m ? .black : .white.opacity(0.7))
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(mode == m ? AnyShapeStyle(tint) : AnyShapeStyle(Color.clear), in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private var listSearch: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundColor(.white.opacity(0.4))
            TextField("Search by title…", text: $searchText)
                .textFieldStyle(.plain)
                .foregroundColor(.white)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, 28)
        .padding(.top, 16)
    }

    // MARK: - Film grid

    private var gridRow: CatalogRow {
        CatalogRow(id: displayRow.id, title: displayRow.title, items: displayRow.items, tileShape: "poster")
    }

    private var filmGrid: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(mode == .gallery ? "Winning films & shows" : "All winners")
                    .font(.system(size: 20, weight: .bold, design: .serif))
                    .foregroundColor(.white)
                Spacer()
                Text("\(winners.count) titles")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white.opacity(0.4))
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 130), spacing: 16)], spacing: 20) {
                ForEach(gridWinners) { item in
                    awardTile(item)
                        .onTapGesture { onSelectMedia(item) }
                }
            }

            if mode == .gallery, !showAllWinners, winners.count > previewCount {
                Button { withAnimation { showAllWinners = true } } label: {
                    HStack(spacing: 6) {
                        Text("View all \(winners.count) winners")
                        Image(systemName: "chevron.down")
                    }
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 18).padding(.vertical, 10)
                    .background(Color.white.opacity(0.08), in: Capsule())
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity)
                .padding(.top, 6)
            }
        }
        .padding(.horizontal, 28)
        .padding(.top, 26)
    }

    // MARK: - Winner tile (fills its adaptive column — MediaCard's fixed
    // 154pt width overflows columns narrower than that, pushing labels and
    // hover states across the gutter; this tile can't).

    private func awardTile(_ item: MetaPreview) -> some View {
        AwardHubTile(item: item)
    }

    // MARK: - People rails

    @ViewBuilder private var peopleRails: some View {
        if isLoadingPeople {
            HStack { Spacer(); MacStrokeSpinner(size: 17); Spacer() }
                .padding(.top, 40)
        } else {
            VStack(alignment: .leading, spacing: 28) {
                if !people.actors.isEmpty { peopleRail("Celebrated actors", people.actors) }
                if !people.directors.isEmpty { peopleRail("Acclaimed directors", people.directors) }
                if !people.writers.isEmpty { peopleRail("Honored writers", people.writers) }
            }
            .padding(.top, 40)
        }
    }

    private func peopleRail(_ title: String, _ list: [AwardPerson]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(.white)
                .padding(.horizontal, 28)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 16) {
                    ForEach(list) { person in personCard(person) }
                }
                .padding(.horizontal, 28)
            }
        }
    }

    private func personCard(_ person: AwardPerson) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .topTrailing) {
                CachedAsyncImage(url: person.profileURL) { image in
                    image.resizable().aspectRatio(contentMode: .fill)
                } placeholder: {
                    ZStack {
                        MoonlitTheme.surfaceElevated
                        Image(systemName: "person.fill").foregroundColor(.white.opacity(0.2)).font(.system(size: 30))
                    }
                }
                .frame(width: 120, height: 150)
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: 12))

                if person.count > 1 {
                    Text("\(person.count)×")
                        .font(.system(size: 10, weight: .black))
                        .foregroundColor(.black)
                        .padding(.horizontal, 6).padding(.vertical, 3)
                        .background(tint, in: Capsule())
                        .padding(6)
                }
            }
            Text(person.name)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.white)
                .lineLimit(1)
            if let title = person.representativeTitle {
                Text(title)
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.45))
                    .lineLimit(1)
            }
        }
        .frame(width: 120)
    }

    // MARK: - Loading

    private func loadInitialIfNeeded() async {
        guard winners.isEmpty else { return }
        isLoadingInitial = true
        defer { isLoadingInitial = false }
        if collectionRepo.collections.isEmpty {
            await collectionRepo.refreshForCatalogRows()
        }
        if addonRepo.managedAddons.isEmpty, let profile = profileManager.currentProfile {
            let info = try? await SyncService.shared.pullSystemAddonInfo()
            await addonRepo.loadAddons(profileId: profile.id, systemAddonUrl: info?.url)
        }
        _ = await catalogRepo.loadFolderItems(
            folderId: CatalogRepository.normalizedFolderId(row.id),
            collectionRepo: collectionRepo,
            addons: addonRepo.enabledAddons
        )
    }

    private func loadPeople() async {
        isLoadingPeople = true
        // Wait briefly for winners to populate if needed.
        for _ in 0..<20 where winners.isEmpty {
            try? await Task.sleep(for: .milliseconds(150))
        }
        let result = await AwardPeopleService.shared.people(forWinners: winners, cacheKey: award.rawValue)
        await MainActor.run {
            people = result
            isLoadingPeople = false
        }
    }
}

/// Winner-grid tile that stays inside its adaptive column: the poster fills
/// whatever width the column resolves to (2:3 ratio), everything is clipped,
/// the label truncates at tile width, and the hover scale is subtle enough
/// (1.03) to never cross a 16pt gutter.
private struct AwardHubTile: View {
    let item: MetaPreview

    @State private var isHovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Group {
                if let url = item.artworkURL(preferring: .portrait) {
                    CachedAsyncImage(url: url) { image in
                        image.resizable().scaledToFill()
                    } placeholder: {
                        MoonlitTheme.surfaceElevated
                    }
                } else {
                    MoonlitTheme.surfaceElevated
                }
            }
            .aspectRatio(2 / 3, contentMode: .fill)
            .frame(maxWidth: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.white.opacity(isHovering ? 0.22 : 0.06), lineWidth: 1)
            )
            .macTileGlow(
                isHovering: isHovering,
                artworkURL: item.artworkURL(preferring: .portrait),
                fallbackColor: MoonlitTheme.ratingGold,
                cornerRadius: 12
            )
            .scaleEffect(isHovering ? 1.03 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isHovering)

            Text(item.name)
                .font(.system(size: 12.5, weight: .medium))
                .foregroundColor(.white)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)

            if let year = item.releaseInfo {
                Text(year)
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundColor(.white.opacity(0.4))
            }
        }
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
    }
}
