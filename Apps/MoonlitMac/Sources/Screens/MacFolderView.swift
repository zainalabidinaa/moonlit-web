import SwiftUI
import MoonlitCore

struct MacFolderView: View {
    let row: CatalogRow
    let onBack: () -> Void
    let onSelectMedia: (MetaPreview) -> Void
    var onSelectFolder: ((CatalogRow) -> Void)?

    @StateObject private var catalogRepo = CatalogRepository.shared
    @StateObject private var collectionRepo = CollectionRepository.shared
    @StateObject private var addonRepo = AddonRepository.shared
    @StateObject private var profileManager = ProfileManager.shared
    @State private var isLoadingInitial = false
    @State private var isLoadingMore = false
    @State private var unavailableReason: FolderLoadUnavailableReason?

    private var displayRow: CatalogRow {
        catalogRepo.allFolderRows[CatalogRepository.normalizedFolderId(row.id)] ?? row
    }

    private var shouldUseLandscapeLayout: Bool {
        let sample = displayRow.items.prefix(12)
        let folders = sample.filter { $0.id.hasPrefix("folder_") }
        let media = sample.filter { !$0.id.hasPrefix("folder_") }
        guard !folders.isEmpty, media.isEmpty else { return false }
        let landscapeCount = folders.filter { $0.posterShape == .landscape || $0.banner != nil }.count
        return landscapeCount >= max(1, folders.count / 2)
    }

    private var shapeRow: CatalogRow {
        CatalogRow(
            id: displayRow.id,
            title: displayRow.title,
            items: displayRow.items,
            addonName: displayRow.addonName,
            addonId: displayRow.addonId,
            page: displayRow.page,
            hasMore: displayRow.hasMore,
            tileShape: shouldUseLandscapeLayout ? "landscape" : (displayRow.tileShape ?? "poster"),
            coverImage: displayRow.coverImage,
            focusGif: displayRow.focusGif,
            focusGifEnabled: displayRow.focusGifEnabled,
            titleLogo: displayRow.titleLogo,
            heroBackdrop: displayRow.heroBackdrop,
            heroVideoURL: displayRow.heroVideoURL,
            hideTitle: displayRow.hideTitle
        )
    }

    private var columns: [GridItem] {
        if shouldUseLandscapeLayout {
            // Landscape folder tiles are a fixed 240pt wide (MediaCard). The column
            // minimum must be >= that width, or an adaptive column can resolve
            // narrower than the tile and the tiles overlap. 248 leaves a hair of
            // breathing room over the 240 tile.
            [GridItem(.adaptive(minimum: 248), spacing: 16)]
        } else {
            [GridItem(.adaptive(minimum: 155), spacing: 16)]
        }
    }

    var body: some View {
        ZStack(alignment: .top) {
            MacFusionAmbientBackground(
                ambientColor: .clear,
                ambientColor2: .clear,
                isEnabled: true
            )
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    hero

                    if isLoadingInitial && displayRow.items.isEmpty {
                        loadingState
                            .padding(.top, 72)
                    } else if displayRow.items.isEmpty || unavailableReason != nil {
                        emptyState
                            .padding(.top, 72)
                    } else {
                        LazyVGrid(columns: columns, spacing: 18) {
                            ForEach(displayRow.items) { item in
                                MediaCard(item: item, row: shapeRow)
                                    .onTapGesture { route(item) }
                                    .onAppear {
                                        if item.id == displayRow.items.last?.id {
                                            Task { await loadMoreIfNeeded() }
                                        }
                                    }
                            }
                        }
                        .padding(.horizontal, 28)
                        .padding(.top, 24)

                        if isLoadingMore {
                            HStack {
                                Spacer()
                                MacLottieLoadingView(size: 26)
                                Spacer()
                            }
                            .padding(.vertical, 28)
                        }
                    }

                    Spacer().frame(height: 48)
                }
            }
            .ignoresSafeArea(.container, edges: .top)

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
        .task(id: row.id) {
            if let logoURL = displayRow.titleLogo.flatMap(URL.init) {
                Task.detached(priority: .background) {
                    _ = await MoonlitImageCache.image(for: logoURL)
                }
            }
            await loadInitialIfNeeded()
        }
    }

    @ViewBuilder
    private var hero: some View {
        if let backdrop = displayRow.heroBackdrop ?? displayRow.backdropImage ?? displayRow.coverImage,
           let url = URL(string: backdrop) {
            ZStack(alignment: .bottomLeading) {
                CachedAsyncImage(url: url, maxDimension: 3000) { image in
                    image.resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(maxWidth: .infinity)
                        .frame(height: 400)
                        .clipped()
                } placeholder: {
                    MoonlitTheme.surfaceElevated.frame(height: 400)
                }

                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0.0),
                        .init(color: MoonlitTheme.background.opacity(0.35), location: 0.45),
                        .init(color: MoonlitTheme.background.opacity(0.85), location: 0.75),
                        .init(color: MoonlitTheme.background, location: 1.0),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )

                if let logo = displayRow.titleLogo, let logoURL = URL(string: logo) {
                    CachedAsyncImage(url: logoURL) { logoImage in
                        logoImage.resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(maxWidth: 360, maxHeight: 96)
                            .shadow(color: .black.opacity(0.5), radius: 8, y: 3)
                    } placeholder: { Color.clear }
                    .padding(.horizontal, 28)
                    .padding(.bottom, 24)
                } else {
                    Text(displayRow.title)
                        .font(.system(size: 36, weight: .black))
                        .foregroundColor(.white)
                        .padding(.horizontal, 28)
                        .padding(.bottom, 20)
                }
            }
        }
    }

    private var loadingState: some View {
        MacLoadingView(size: 40)
            .frame(maxWidth: .infinity)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: unavailableReason == .missingFolder ? "folder.badge.questionmark" : "folder")
                .font(.system(size: 38, weight: .semibold))
                .foregroundStyle(.white.opacity(0.22))
            Text(emptyStateTitle)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white.opacity(0.62))
            if let message = emptyStateMessage {
                Text(message)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.42))
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var emptyStateTitle: String {
        switch unavailableReason {
        case .missingFolder:
            return "This folder is no longer available"
        case .missingSources:
            return "This folder has no sources"
        case .missingAddonTransport:
            return "No enabled addon can load this folder"
        case .emptyResponse:
            return "Nothing here yet"
        case nil:
            return "Nothing here yet"
        }
    }

    private var emptyStateMessage: String? {
        switch unavailableReason {
        case .missingFolder:
            return "The current collection refresh removed or renamed it."
        case .missingSources:
            return "The collection exists, but it has no catalog source configured."
        case .missingAddonTransport:
            return "Enable or refresh addons, then try again."
        case .emptyResponse:
            return "The provider returned no items for this folder."
        case nil:
            return nil
        }
    }

    private func route(_ item: MetaPreview) {
        if item.id.hasPrefix("folder_") {
            let fallback = CatalogRow(
                id: item.id,
                title: item.name,
                items: [],
                tileShape: item.posterShape?.rawValue ?? "poster",
                coverImage: item.artworkString(preferring: .portrait),
                heroBackdrop: item.backdrop
            )
            onSelectFolder?(catalogRepo.allFolderRows[item.id] ?? fallback)
        } else {
            onSelectMedia(item)
        }
    }

    private func loadInitialIfNeeded() async {
        isLoadingInitial = displayRow.items.isEmpty
        unavailableReason = nil

        guard displayRow.items.isEmpty else {
            isLoadingInitial = false
            return
        }

        await ensureOrganizerAndAddonsLoaded()

        if let reason = CatalogRepository.folderLoadUnavailableReason(
            folderId: row.id,
            collections: collectionRepo.collections,
            folders: collectionRepo.folders,
            folderCatalogs: collectionRepo.folderCatalogs,
            folderSources: collectionRepo.folderSources,
            addons: addonRepo.enabledAddons
        ) {
            unavailableReason = reason
            isLoadingInitial = false
            return
        }

        let result = await catalogRepo.loadFolderItems(
            folderId: CatalogRepository.normalizedFolderId(row.id),
            collectionRepo: collectionRepo,
            addons: addonRepo.enabledAddons
        )
        if case .unavailable(let reason) = result {
            unavailableReason = reason
        }
        isLoadingInitial = false
    }

    private func loadMoreIfNeeded() async {
        guard !isLoadingMore, displayRow.hasMore else { return }
        isLoadingMore = true
        await ensureOrganizerAndAddonsLoaded()
        await catalogRepo.loadMoreFolderItems(
            folderId: CatalogRepository.normalizedFolderId(row.id),
            collectionRepo: collectionRepo,
            addons: addonRepo.enabledAddons
        )
        isLoadingMore = false
    }

    private func ensureOrganizerAndAddonsLoaded() async {
        if collectionRepo.collections.isEmpty {
            await collectionRepo.refreshForCatalogRows()
        }

        if addonRepo.managedAddons.isEmpty, let profile = profileManager.currentProfile {
            let info = try? await SyncService.shared.pullSystemAddonInfo()
            await addonRepo.loadAddons(profileId: profile.id, systemAddonUrl: info?.url)
        }
    }
}
