import SwiftUI
import MoonlitCore

///  "Media" section: pill tabs for Videos / Backdrops / Posters /
/// Logos (each showing a count), with a horizontal-scroll gallery below for
/// whichever tab is selected.
struct MacMediaGallerySection: View {
    let detail: MetaDetail
    var trailers: [MacMediaTrailer] = []
    @State private var selectedTab: MediaTab = .videos
    @Environment(\.openURL) private var openURL

    private enum MediaTab: String, CaseIterable {
        case videos = "Videos", backdrops = "Backdrops", posters = "Posters", logos = "Logos"
    }

    private var counts: [MediaTab: Int] {
        [
            .videos: trailers.count + (detail.videoClips?.count ?? 0),
            .backdrops: detail.backdropGallery?.count ?? 0,
            .posters: detail.posterGallery?.count ?? 0,
            .logos: detail.logoGallery?.count ?? 0,
        ]
    }

    private var availableTabs: [MediaTab] {
        MediaTab.allCases.filter { (counts[$0] ?? 0) > 0 }
    }

    private var effectiveTab: MediaTab {
        availableTabs.contains(selectedTab) ? selectedTab : (availableTabs.first ?? .videos)
    }

    var body: some View {
        if !availableTabs.isEmpty {
            VStack(alignment: .leading, spacing: 14) {
                Text("Media")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(.white)

                HStack(spacing: 22) {
                    ForEach(availableTabs, id: \.self) { tab in
                        pill(tab)
                    }
                    Spacer()
                }
                .overlay(Rectangle().fill(Color.white.opacity(0.1)).frame(height: 1), alignment: .bottom)

                gallery(for: effectiveTab)
            }
        }
    }

    private func pill(_ tab: MediaTab) -> some View {
        MacPillButton(
            title: "\(tab.rawValue) \(counts[tab] ?? 0)",
            isSelected: tab == effectiveTab
        ) {
            withAnimation(.easeInOut(duration: 0.15)) { selectedTab = tab }
        }
    }

    @ViewBuilder
    private func gallery(for tab: MediaTab) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 14) {
                switch tab {
                case .videos:
                    ForEach(trailers) { trailer in
                        trailerCard(trailer)
                    }
                    ForEach(detail.videoClips ?? []) { clip in
                        videoCard(clip)
                    }
                case .backdrops:
                    ForEach(detail.backdropGallery ?? [], id: \.self) { url in
                        galleryImage(url, width: 300, height: 169)
                    }
                case .posters:
                    ForEach(detail.posterGallery ?? [], id: \.self) { url in
                        galleryImage(url, width: 140, height: 210)
                    }
                case .logos:
                    ForEach(detail.logoGallery ?? [], id: \.self) { url in
                        galleryImage(url, width: 220, height: 124, contentMode: .fit)
                    }
                }
            }
        }
    }

    private func trailerCard(_ trailer: MacMediaTrailer) -> some View {
        Button {
            if let url = trailer.url.flatMap(URL.init) { openURL(url) }
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                ZStack {
                    if let url = trailer.thumbnailURL {
                        CachedAsyncImage(url: url) { img in
                            img.resizable().aspectRatio(contentMode: .fill)
                        } placeholder: {
                            MoonlitTheme.surfaceElevated
                        }
                    } else {
                        MoonlitTheme.surfaceElevated
                    }
                    Image(systemName: "play.circle.fill")
                        .font(.system(size: 40))
                        .foregroundColor(.white)
                        .shadow(color: .black.opacity(0.5), radius: 4)
                }
                .frame(width: 300, height: 169)
                .clipShape(RoundedRectangle(cornerRadius: MoonlitTheme.radiusControl, style: .continuous))

                Text(trailer.displayTitle)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.white)
                    .lineLimit(2)
                    .frame(width: 300, alignment: .leading)
            }
        }
        .buttonStyle(.plain)
    }

    private func videoCard(_ clip: TMDBVideoClip) -> some View {
        Button {
            if let url = clip.youtubeWatchURL { openURL(url) }
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                ZStack {
                    if let url = clip.youtubeThumbnailURL {
                        CachedAsyncImage(url: url) { img in
                            img.resizable().aspectRatio(contentMode: .fill)
                        } placeholder: {
                            MoonlitTheme.surfaceElevated
                        }
                    } else {
                        MoonlitTheme.surfaceElevated
                    }
                    Image(systemName: "play.circle.fill")
                        .font(.system(size: 40))
                        .foregroundColor(.white)
                        .shadow(color: .black.opacity(0.5), radius: 4)
                }
                .frame(width: 300, height: 169)
                .clipShape(RoundedRectangle(cornerRadius: MoonlitTheme.radiusControl, style: .continuous))

                Text(clip.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.white)
                    .lineLimit(2)
                    .frame(width: 300, alignment: .leading)
                Text(clip.type)
                    .font(.caption)
                    .foregroundColor(MoonlitTheme.textTertiary)
            }
        }
        .buttonStyle(.plain)
    }

    private func galleryImage(_ urlString: String, width: CGFloat, height: CGFloat, contentMode: ContentMode = .fill) -> some View {
        Group {
            if let url = URL(string: urlString) {
                CachedAsyncImage(url: url) { img in
                    img.resizable().aspectRatio(contentMode: contentMode)
                } placeholder: {
                    MoonlitTheme.surfaceElevated
                }
            } else {
                MoonlitTheme.surfaceElevated
            }
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: MoonlitTheme.radiusControl, style: .continuous))
    }
}

struct MacMediaTrailer: Identifiable, Sendable {
    let id = UUID()
    let name: String
    let url: String?
    var seasonLabel: String? = nil
    var ytId: String? = nil

    /// The title shown on the card — the season label when known (e.g. "Season
    /// 2 Trailer"), otherwise whatever the source addon called it.
    var displayTitle: String { seasonLabel ?? name }

    var thumbnailURL: URL? {
        guard let ytId else { return nil }
        return URL(string: "https://img.youtube.com/vi/\(ytId)/hqdefault.jpg")
    }
}
