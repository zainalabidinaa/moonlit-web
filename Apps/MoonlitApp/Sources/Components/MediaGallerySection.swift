import SwiftUI
import MoonlitCore

///  "Media" section: pill tabs for Videos / Backdrops / Posters /
/// Logos (each showing a count), with a horizontal-scroll gallery below for
/// whichever tab is selected.
struct MediaGallerySection: View {
    let detail: MetaDetail
    @State private var selectedTab: MediaTab = .videos
    @Environment(\.openURL) private var openURL

    private enum MediaTab: String, CaseIterable {
        case videos = "Videos", backdrops = "Backdrops", posters = "Posters", logos = "Logos"
    }

    private var counts: [MediaTab: Int] {
        [
            .videos: detail.videoClips?.count ?? 0,
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
            VStack(alignment: .leading, spacing: 12) {
                Text("Media")
                    .font(.headline)
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(availableTabs, id: \.self) { tab in
                            pill(tab)
                        }
                    }
                    .padding(.horizontal, 16)
                }

                gallery(for: effectiveTab)
            }
        }
    }

    private func pill(_ tab: MediaTab) -> some View {
        let isSelected = tab == effectiveTab
        return Button {
            withAnimation(.easeInOut(duration: 0.15)) { selectedTab = tab }
        } label: {
            Text("\(tab.rawValue) \(counts[tab] ?? 0)")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(isSelected ? .black : .white)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(Capsule().fill(isSelected ? Color.white : Color.clear))
                .overlay(Capsule().stroke(Color.white.opacity(isSelected ? 0 : 0.4), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func gallery(for tab: MediaTab) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                switch tab {
                case .videos:
                    ForEach(detail.videoClips ?? []) { clip in
                        videoCard(clip)
                    }
                case .backdrops:
                    ForEach(detail.backdropGallery ?? [], id: \.self) { url in
                        galleryImage(url, width: 240, height: 135)
                    }
                case .posters:
                    ForEach(detail.posterGallery ?? [], id: \.self) { url in
                        galleryImage(url, width: 120, height: 180)
                    }
                case .logos:
                    ForEach(detail.logoGallery ?? [], id: \.self) { url in
                        galleryImage(url, width: 180, height: 100, contentMode: .fit)
                    }
                }
            }
            .padding(.horizontal, 16)
        }
    }

    private func videoCard(_ clip: TMDBVideoClip) -> some View {
        Button {
            if let url = clip.youtubeWatchURL { openURL(url) }
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                ZStack {
                    if let url = clip.youtubeThumbnailURL {
                        CachedAsyncImage(url: url) { phase in
                            if case .success(let img) = phase {
                                img.resizable().aspectRatio(contentMode: .fill)
                            } else {
                                MoonlitTheme.surfaceElevated
                            }
                        }
                    } else {
                        MoonlitTheme.surfaceElevated
                    }
                    Image(systemName: "play.circle.fill")
                        .font(.system(size: 32))
                        .foregroundColor(.white)
                        .shadow(color: .black.opacity(0.5), radius: 4)
                }
                .frame(width: 240, height: 135)
                .clipShape(RoundedRectangle(cornerRadius: MoonlitTheme.radiusControl, style: .continuous))

                Text(clip.name)
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.white)
                    .lineLimit(2)
                    .frame(width: 240, alignment: .leading)
                Text(clip.type)
                    .font(.caption2)
                    .foregroundColor(MoonlitTheme.textTertiary)
            }
        }
        .buttonStyle(.plain)
    }

    private func galleryImage(_ urlString: String, width: CGFloat, height: CGFloat, contentMode: ContentMode = .fill) -> some View {
        Group {
            if let url = URL(string: urlString) {
                CachedAsyncImage(url: url) { phase in
                    if case .success(let img) = phase {
                        img.resizable().aspectRatio(contentMode: contentMode)
                    } else {
                        MoonlitTheme.surfaceElevated
                    }
                }
            } else {
                MoonlitTheme.surfaceElevated
            }
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: MoonlitTheme.radiusControl, style: .continuous))
    }
}
