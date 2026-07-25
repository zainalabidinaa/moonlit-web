import SwiftUI
import MoonlitCore

struct FolderScreen: View {
    let row: CatalogRow

    @State private var selectedMedia: MetaPreview?
    @State private var showDetail = false
    @State private var selectedFolder: CatalogRow?
    @State private var showFolder = false
    @State private var isLoadingItems = false
    @State private var isLoadingMoreItems = false

    // Observe CatalogRepository so the grid updates when on-demand items arrive.
    @ObservedObject private var catalogRepo = CatalogRepository.shared

    // The live row — either the originally-passed row (already populated) or the
    // updated version in allFolderRows once on-demand loading completes.
    private var displayRow: CatalogRow {
        catalogRepo.allFolderRows[row.id] ?? row
    }

    // Landscape layout only applies when the folder contains nested sub-groups (folder items)
    // with landscape art — never for regular movies/TV shows.
    private var useLandscapeLayout: Bool {
        let sample = displayRow.items.prefix(6)
        guard !sample.isEmpty else { return false }
        let hasMediaItems = sample.contains { !$0.id.hasPrefix("folder_") }
        if hasMediaItems { return false }
        let landscapeCount = sample.filter { $0.posterShape == .landscape }.count
        return landscapeCount > sample.count / 2
    }

    private var columns: [GridItem] {
        if useLandscapeLayout {
            return [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]
        }
        return [
            GridItem(.flexible(), spacing: 10),
            GridItem(.flexible(), spacing: 10),
            GridItem(.flexible(), spacing: 10)
        ]
    }

    // Width available to each landscape cell: screen minus two 14pt paddings and one 10pt gap.
    private var landscapeCellWidth: CGFloat {
        (UIScreen.main.bounds.width - 38) / 2
    }
    private var landscapeCellHeight: CGFloat { landscapeCellWidth * 9 / 16 }

    /// Folder grids always use poster cards. The home collection row can use
    /// landscape group art, but opened folders should keep the original poster grid.
    private var shapeRow: CatalogRow {
        return CatalogRow(
            id: displayRow.id,
            title: displayRow.title,
            items: displayRow.items,
            addonName: displayRow.addonName,
            addonId: displayRow.addonId,
            page: displayRow.page,
            hasMore: displayRow.hasMore,
            tileShape: useLandscapeLayout ? "landscape" : "poster",
            coverImage: displayRow.coverImage,
            focusGif: displayRow.focusGif,
            focusGifEnabled: displayRow.focusGifEnabled,
            titleLogo: displayRow.titleLogo,
            heroBackdrop: displayRow.heroBackdrop,
            heroVideoURL: displayRow.heroVideoURL,
            hideTitle: displayRow.hideTitle,
            focusGlowEnabled: displayRow.focusGlowEnabled,
            viewMode: displayRow.viewMode,
            showAllTab: displayRow.showAllTab,
            pinToTop: displayRow.pinToTop,
            backdropImage: displayRow.backdropImage
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // Hero backdrop
                if let backdrop = displayRow.heroBackdrop ?? displayRow.backdropImage ?? displayRow.coverImage,
                   let url = URL(string: backdrop) {
                    GeometryReader { geo in
                        AsyncImage(url: url) { phase in
                            if case .success(let img) = phase {
                                img.resizable()
                                    .aspectRatio(contentMode: .fill)
                                    .frame(width: geo.size.width, height: 220)
                                    .clipped()
                                    .overlay(
                                        LinearGradient(
                                            colors: [.black.opacity(0.15), MoonlitTheme.background],
                                            startPoint: .top,
                                            endPoint: .bottom
                                        )
                                    )
                            }
                        }
                    }
                    .frame(height: 220)
                    .ignoresSafeArea(edges: .top)
                }

                if isLoadingItems {
                    // Shimmer placeholder while loading on-demand
                    LazyVGrid(columns: columns, spacing: 10) {
                        ForEach(0..<12, id: \.self) { _ in
                            ShimmerCard(width: 100, height: 150, cornerRadius: MoonlitTheme.radiusControl)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.top, 16)
                } else {
                    LazyVGrid(columns: columns, spacing: 10) {
                        ForEach(Array(displayRow.items.enumerated()), id: \.element.id) { index, item in
                            ContentCard(
                                item: item,
                                row: shapeRow,
                                index: index,
                                width: useLandscapeLayout ? landscapeCellWidth : nil,
                                height: useLandscapeLayout ? landscapeCellHeight : nil
                            )
                                .onTapGesture {
                                    if item.id.hasPrefix("folder_") {
                                        selectedFolder = catalogRepo.allFolderRows[item.id] ?? CatalogRow(
                                            id: item.id,
                                            title: item.name,
                                            items: [],
                                            tileShape: item.posterShape?.rawValue ?? "poster",
                                            coverImage: item.artworkString(preferring: .portrait)
                                        )
                                        showFolder = true
                                    } else {
                                        selectedMedia = item
                                        showDetail = true
                                    }
                                }
                                .onAppear {
                                    guard index == displayRow.items.count - 1 else { return }
                                    guard displayRow.hasMore, !isLoadingMoreItems else { return }
                                    Task { await loadMoreItems() }
                                }
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.top, 16)
                    .padding(.bottom, isLoadingMoreItems ? 0 : 24)

                    if isLoadingMoreItems {
                        LottieLoadingView(size: 36)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 18)
                    }
                }
            }
        }
        .background(MoonlitTheme.background)
        .navigationTitle(displayRow.title)
#if os(iOS)
        .navigationBarTitleDisplayMode(.large)
#endif
        .navigationDestination(isPresented: $showDetail) {
            if let media = selectedMedia {
                DetailScreen(mediaId: media.id, type: media.type.rawValue, name: media.name)
            }
        }
        .navigationDestination(isPresented: $showFolder) {
            if let folder = selectedFolder {
                FolderScreen(row: folder)
            }
        }
        .task {
            // Skeleton row (from group collection) — load items on demand.
            guard displayRow.items.isEmpty, !isLoadingItems else { return }
            isLoadingItems = true
            await catalogRepo.loadFolderItems(
                folderId: row.id,
                collectionRepo: CollectionRepository.shared,
                addons: AddonRepository.shared.enabledAddons
            )
            isLoadingItems = false
        }
    }

    private func loadMoreItems() async {
        isLoadingMoreItems = true
        defer { isLoadingMoreItems = false }
        await catalogRepo.loadMoreFolderItems(
            folderId: row.id,
            collectionRepo: CollectionRepository.shared,
            addons: AddonRepository.shared.enabledAddons
        )
    }

    private var gridHeight: CGFloat {
        guard !displayRow.items.isEmpty else { return 0 }
        let estimatedColumns = max(1, Int(UIScreen.main.bounds.width / 120))
        let rows = Int(ceil(Double(displayRow.items.count) / Double(estimatedColumns)))
        let estimatedCardHeight: CGFloat = 184
        let spacing = CGFloat(max(0, rows - 1)) * 10
        return CGFloat(rows) * estimatedCardHeight + spacing + 40
    }
}
