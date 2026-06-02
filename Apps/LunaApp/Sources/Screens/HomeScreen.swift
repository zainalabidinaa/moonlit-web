import SwiftUI
import LunaCore

struct HomeScreen: View {
    @EnvironmentObject var profileManager: ProfileManager
    @StateObject private var catalogRepo = CatalogRepository.shared
    @StateObject private var collectionRepo = CollectionRepository.shared
    @StateObject private var homeRepo = HomeRepository.shared
    @StateObject private var addonRepo = AddonRepository.shared
    @State private var selectedMedia: MetaPreview?
    @State private var showDetail = false

    private let mainRowNames: Set<String> = [
        "Popular Movies", "Popular TV Shows",
        "Trending Movies", "Trending TV Shows"
    ]

    private var featuredItems: [MetaPreview] {
        let mainRows = catalogRepo.catalogRows.filter { mainRowNames.contains($0.title) }
        var seen = Set<String>()
        var candidates: [MetaPreview] = []
        for row in mainRows {
            for item in row.items where !seen.contains(item.id) {
                seen.insert(item.id)
                candidates.append(item)
            }
        }
        return candidates
            .sorted { ($0.popularity ?? 0) > ($1.popularity ?? 0) }
            .prefix(5)
            .map { $0 }
    }

    @State private var heroIndex = 0
    @State private var heroTimer: Timer? = nil

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    // Hero Section
                    if !featuredItems.isEmpty {
                        let safeIndex = heroIndex % featuredItems.count
                        let rowTitle = catalogRepo.catalogRows
                            .first(where: { $0.items.contains(where: { $0.id == featuredItems[safeIndex].id }) })?
                            .title ?? "Featured"
                        HeroSection(
                            item: featuredItems[safeIndex],
                            rowTitle: rowTitle,
                            onTap: {
                                selectedMedia = featuredItems[safeIndex]
                                showDetail = true
                            },
                            dotCount: featuredItems.count,
                            activeIndex: safeIndex,
                            onDotTap: { i in
                                withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                                    heroIndex = i
                                }
                                startHeroTimer()
                            }
                        )
                        .ignoresSafeArea(edges: .top)
                    }

                    // Continue Watching
                    if !homeRepo.continueWatchingItems.isEmpty {
                        ContinueWatchingRow(
                            items: homeRepo.continueWatchingItems,
                            onTap: { item in
                                // ContinueWatchingItem -> navigate via mediaId lookup
                                if let match = catalogRepo.catalogRows
                                    .flatMap({ $0.items })
                                    .first(where: { $0.id == item.mediaId }) {
                                    selectedMedia = match
                                    showDetail = true
                                } else {
                                    // Fallback: build a minimal MetaPreview from the CW item
                                    selectedMedia = MetaPreview(
                                        id: item.mediaId,
                                        type: item.mediaType == "movie" ? .movie : .series,
                                        name: item.name,
                                        poster: item.poster
                                    )
                                    showDetail = true
                                }
                            }
                        )
                        .padding(.top, 16)
                    }

                    if !catalogRepo.catalogRows.isEmpty {
                        // Main rows
                        let mainRows = catalogRepo.catalogRows.filter { mainRowNames.contains($0.title) }
                        let folderRows = catalogRepo.catalogRows.filter { !mainRowNames.contains($0.title) }

                        LazyVStack(spacing: 24) {
                            ForEach(mainRows) { row in
                                CatalogRowView(row: row) { item in
                                    selectedMedia = item
                                    showDetail = true
                                }
                                .onAppear {
                                    if row.id == mainRows.last?.id {
                                        Task {
                                            await catalogRepo.loadMore(
                                                rowId: row.id,
                                                addons: addonRepo.enabledAddons
                                            )
                        }
                    } else {
                        VStack {
                            Spacer().frame(height: 100)
                            EmptyStateView(
                                icon: "antenna.radiowaves.left.and.right",
                                title: "No content available",
                                message: addonRepo.errorMessage ?? "Failed to load catalogs. Pull to retry or check your addons in Settings."
                            )
                            Spacer()
                        }
                    }
                                }
                            }
                        }
                        .padding(.top, 24)

                        // Folder grid
                        if !folderRows.isEmpty {
                            FolderGridSection(rows: folderRows) { item in
                                selectedMedia = item
                                showDetail = true
                            }
                            .padding(.top, 24)
                        }
                    } else if catalogRepo.isLoading {
                        VStack(spacing: 24) {
                            Spacer().frame(height: 20)
                            ShimmerCard(width: 375, height: 200, cornerRadius: 12)
                                .padding(.horizontal)
                            ShimmerCard(width: 120, height: 16, cornerRadius: 4)
                                .padding(.horizontal)
                            HStack(spacing: 12) {
                                ForEach(0..<3, id: \.self) { _ in
                                    ShimmerCard(width: 180, height: 100, cornerRadius: 8)
                                }
                            }
                            .padding(.horizontal)
                            HStack(spacing: 12) {
                                ForEach(0..<4, id: \.self) { _ in
                                    ShimmerCard(width: 105, height: 158, cornerRadius: 8)
                                }
                            }
                            .padding(.horizontal)
                            Spacer()
                        }
                    }

                    Spacer().frame(height: 32)
                }
            }
            .ignoresSafeArea(edges: .top)
            .refreshable {
                guard let profile = profileManager.currentProfile else { return }
                if collectionRepo.collections.isEmpty {
                    await catalogRepo.loadAllCatalogs(addons: addonRepo.enabledAddons)
                } else {
                    await catalogRepo.loadFromCollections(
                        collectionRepo: collectionRepo,
                        addons: addonRepo.enabledAddons
                    )
                }
                await homeRepo.loadContinueWatching(profileId: profile.id)
            }
            .background(LunaTheme.background)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    if let profile = profileManager.currentProfile {
                        Button {
                            profileManager.currentProfile = nil
                        } label: {
                            Circle()
                                .fill(profile.avatarColor.map { Color(hex: $0) } ?? LunaTheme.accent)
                                .frame(width: 32, height: 32)
                                .overlay(
                                    Text(String(profile.name.prefix(1)))
                                        .font(.caption)
                                        .foregroundColor(.white)
                                )
                        }
                    }
                }
            }
            .navigationDestination(isPresented: $showDetail) {
                if let media = selectedMedia {
                    DetailScreen(mediaId: media.id, type: media.type.rawValue, name: media.name)
                }
            }
            .task {
                guard let profile = profileManager.currentProfile else { return }
                await addonRepo.loadAddons(profileId: profile.id)
                await collectionRepo.load()
                if collectionRepo.collections.isEmpty {
                    await catalogRepo.loadAllCatalogs(addons: addonRepo.enabledAddons)
                } else {
                    await catalogRepo.loadFromCollections(
                        collectionRepo: collectionRepo,
                        addons: addonRepo.enabledAddons
                    )
                }
                await homeRepo.loadContinueWatching(profileId: profile.id)
                startHeroTimer()
            }
            .onDisappear {
                heroTimer?.invalidate()
                heroTimer = nil
            }
            .onChange(of: featuredItems.count) { _, newCount in
                heroIndex = 0
                startHeroTimer()
            }
        }
    }

    private func startHeroTimer() {
        heroTimer?.invalidate()
        guard featuredItems.count > 1 else { return }
        heroTimer = Timer.scheduledTimer(withTimeInterval: 6, repeats: true) { _ in
            withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                heroIndex = (heroIndex + 1) % featuredItems.count
            }
        }
    }
}

// MARK: - Hero Section

struct HeroSection: View {
    let item: MetaPreview
    let rowTitle: String
    let onTap: () -> Void
    let dotCount: Int
    let activeIndex: Int
    let onDotTap: (Int) -> Void

    @State private var imageFailed = false

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Group {
                if let banner = item.banner ?? item.poster, let url = URL(string: banner), !imageFailed {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let img):
                            img.resizable().aspectRatio(contentMode: .fill)
                        case .failure:
                            LunaTheme.background
                                .onAppear { imageFailed = true }
                        default:
                            LunaTheme.background
                        }
                    }
                } else {
                    LunaTheme.surface
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 420)
            .clipped()

            LinearGradient(
                colors: [.clear, LunaTheme.background.opacity(0.7), LunaTheme.background],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 420)

            LinearGradient(
                colors: [LunaTheme.background.opacity(0.7), .clear],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(height: 420)

            // Glass overlay card
            .appCardStyle(surfaceStyle: .darkGlass, cornerRadius: 22)
            .padding(.horizontal, 8)
            .padding(.vertical, 8)

            // Content
            VStack(alignment: .leading, spacing: 0) {
                Text(rowTitle)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(LunaTheme.accent)
                    .tracking(2)
                    .textCase(.uppercase)
                    .padding(.bottom, 8)

                Text(item.name)
                    .font(.system(size: 40, weight: .black))
                    .foregroundColor(.white)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
                    .padding(.bottom, 6)

                HStack(spacing: 8) {
                    if let rating = item.imdbRating {
                        Label(rating, systemImage: "star.fill")
                            .font(.caption)
                            .foregroundColor(.yellow)
                    }
                    if let release = item.releaseInfo {
                        Text(release).font(.caption).foregroundColor(.white.opacity(0.6))
                    }
                    if let genres = item.genres?.prefix(2) {
                        Text(genres.joined(separator: ", "))
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.6))
                    }
                }
                .padding(.bottom, 16)

                HStack(spacing: 12) {
                    Button(action: onTap) {
                        Label("Watch Now", systemImage: "play.fill")
                            .font(.subheadline.bold())
                            .foregroundColor(.black)
                            .padding(.horizontal, 20).padding(.vertical, 11)
                            .background(Color.white).clipShape(Capsule())
                    }

                    Button(action: onTap) {
                        Label("My List", systemImage: "plus")
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 16).padding(.vertical, 11)
                    }
                    .glassCapsule(interactive: true, clear: true)
                }
            }
            .padding(.horizontal, 24).padding(.bottom, 24)
            .frame(maxWidth: .infinity, alignment: .leading)

            if dotCount > 1 {
                HStack(spacing: 5) {
                    ForEach(0..<dotCount, id: \.self) { i in
                        Button { onDotTap(i) } label: {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(i == activeIndex ? Color.white : Color.white.opacity(0.3))
                                .frame(width: i == activeIndex ? 20 : 6, height: 3)
                        }
                        .animation(.easeInOut(duration: 0.25), value: activeIndex)
                    }
                }
                .padding(.trailing, 16).padding(.bottom, 16)
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .frame(height: 420).clipped()
    }
}

// MARK: - Folder Grid

struct FolderGridSection: View {
    let rows: [CatalogRow]
    let onTap: (MetaPreview) -> Void

    private let columns = [
        GridItem(.adaptive(minimum: 80), spacing: 8)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Browse")
                .font(.headline).foregroundColor(.white).padding(.horizontal)
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(rows) { row in
                    FolderCell(row: row, onTap: onTap)
                }
            }
            .padding(.horizontal)
        }
    }
}

struct FolderCell: View {
    let row: CatalogRow
    let onTap: (MetaPreview) -> Void

    private var isLandscape: Bool {
        row.tileShape == "landscape"
    }

    var body: some View {
        let coverURL: URL? = {
            if let ci = row.coverImage { return URL(string: ci) }
            if let p = row.items.first?.poster { return URL(string: p) }
            return nil
        }()

        Button {
            if let first = row.items.first { onTap(first) }
        } label: {
            ZStack(alignment: .bottom) {
                RoundedRectangle(cornerRadius: 8)
                    .fill(LunaTheme.surfaceElevated)
                    .aspectRatio(isLandscape ? 16/9 : 2/3, contentMode: .fit)

                if let url = coverURL {
                    AsyncImage(url: url) { phase in
                        if case .success(let img) = phase {
                            img.resizable().aspectRatio(contentMode: .fill)
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .aspectRatio(isLandscape ? 16/9 : 2/3, contentMode: .fit)
                }

                LinearGradient(
                    colors: [.black.opacity(0.75), .clear],
                    startPoint: .bottom,
                    endPoint: .top
                )
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .aspectRatio(isLandscape ? 16/9 : 2/3, contentMode: .fit)

                Text(row.title)
                    .font(.system(size: isLandscape ? 11 : 9, weight: .bold))
                    .foregroundColor(.white)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Catalog Row View

struct CatalogRowView: View {
    let row: CatalogRow
    let onTap: (MetaPreview) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                if let titleLogo = row.titleLogo, let url = URL(string: titleLogo) {
                    AsyncImage(url: url) { phase in
                        if case .success(let image) = phase {
                            image
                                .resizable()
                                .scaledToFit()
                                .frame(height: 24)
                        }
                    }
                } else if !(row.hideTitle ?? false) {
                    Text(row.title)
                        .font(.headline)
                        .foregroundColor(.white)
                }
                Spacer()
            }
            .padding(.horizontal)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 12) {
                    ForEach(Array(row.items.enumerated()), id: \.element.id) { index, item in
                        ContentCard(item: item, row: row, index: index)
                            .onTapGesture { onTap(item) }
                    }
                }
                .padding(.horizontal)
            }
        }
    }
}

// MARK: - Continue Watching

struct ContinueWatchingRow: View {
    let items: [ContinueWatchingItem]
    let onTap: (ContinueWatchingItem) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Continue Watching")
                .font(.headline)
                .foregroundColor(.white)
                .padding(.horizontal)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 12) {
                    ForEach(items) { item in
                        ContinueWatchingCard(item: item)
                            .onTapGesture { onTap(item) }
                    }
                }
                .padding(.horizontal)
            }
        }
        .padding(.top, 8)
    }
}

struct ContinueWatchingCard: View {
    let item: ContinueWatchingItem

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ZStack(alignment: .bottom) {
                Group {
                    if let poster = item.poster, let url = URL(string: poster) {
                        AsyncImage(url: url) { phase in
                            if case .success(let img) = phase {
                                img.resizable().aspectRatio(contentMode: .fill)
                            } else {
                                RoundedRectangle(cornerRadius: 8).fill(LunaTheme.surfaceElevated)
                            }
                        }
                    } else {
                        RoundedRectangle(cornerRadius: 8).fill(LunaTheme.surfaceElevated)
                    }
                }
                .frame(width: 192, height: 108).clipped()
                .glassCard(cornerRadius: 8)

                // Play overlay circle
                Circle().fill(Color.black.opacity(0.5)).frame(width: 36, height: 36)
                    .overlay(
                        Image(systemName: "play.fill")
                            .font(.system(size: 14))
                            .foregroundColor(.white)
                            .offset(x: 1)
                    )
                    .padding(.bottom, 16)

                // Progress bar
                VStack(spacing: 0) {
                    Spacer()
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Rectangle().fill(Color.white.opacity(0.2)).frame(height: 3)
                            Rectangle()
                                .fill(LunaTheme.accent)
                                .frame(width: geo.size.width * item.progressFraction, height: 3)
                        }
                    }.frame(height: 3)
                }.cornerRadius(8)
            }
            .frame(width: 192, height: 108)

            Text(item.name)
                .font(.caption).foregroundColor(.white).lineLimit(1).frame(width: 192, alignment: .leading)
            Text("\(Int(item.progressFraction * 100))% watched")
                .font(.caption2).foregroundColor(LunaTheme.textSecondary)
        }
    }
}
