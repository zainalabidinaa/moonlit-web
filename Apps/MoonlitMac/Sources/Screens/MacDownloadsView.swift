import SwiftUI
import MoonlitCore

struct MacDownloadsView: View {
    var onSelectMedia: (MetaPreview) -> Void = { _ in }

    @ObservedObject private var manager = DownloadManager.shared
    @Environment(\.openWindow) private var openWindow

    private var items: [DownloadItem] {
        manager.downloads.sorted { $0.createdAt > $1.createdAt }
    }

    var body: some View {
        Group {
            if items.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(items) { item in
                            downloadRow(item)
                        }
                    }
                    .padding(20)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(MoonlitTheme.background)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "arrow.down.circle")
                .font(.system(size: 44, weight: .light))
                .foregroundColor(MoonlitTheme.textTertiary)
            Text("No downloads yet")
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(MoonlitTheme.textSecondary)
            Text("Downloaded titles play offline and appear here.")
                .font(.system(size: 13))
                .foregroundColor(MoonlitTheme.textTertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func downloadRow(_ item: DownloadItem) -> some View {
        HStack(spacing: 14) {
            CachedAsyncImage(url: item.poster.flatMap { URL(string: $0) }) { img in
                img.resizable().aspectRatio(2/3, contentMode: .fill)
            } placeholder: {
                Rectangle()
                    .fill(MoonlitTheme.surfaceElevated)
                    .overlay(
                        Image(systemName: item.type == "series" ? "tv" : "film")
                            .foregroundColor(MoonlitTheme.textTertiary)
                    )
            }
            .frame(width: 60, height: 90)
            .clipped()
            .cornerRadius(MoonlitTheme.radiusControl)

            VStack(alignment: .leading, spacing: 6) {
                Text(item.name)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(MoonlitTheme.textPrimary)
                    .lineLimit(1)

                Text(statusLine(item))
                    .font(.system(size: 12))
                    .foregroundColor(MoonlitTheme.textTertiary)

                if item.state == .downloading || item.state == .queued {
                    ProgressView(value: max(0, min(item.progress, 1)))
                        .progressViewStyle(.linear)
                        .tint(MoonlitTheme.accent)
                        .frame(maxWidth: 260)
                }
            }

            Spacer()

            controls(item)
        }
        .padding(12)
        .background(MoonlitTheme.surface)
        .cornerRadius(MoonlitTheme.radiusControl)
    }

    @ViewBuilder
    private func controls(_ item: DownloadItem) -> some View {
        HStack(spacing: 10) {
            if item.state == .completed {
                Button {
                    play(item)
                } label: {
                    Image(systemName: "play.fill")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(MoonlitTheme.textPrimary)
                        .frame(width: 34, height: 34)
                        .background(MoonlitTheme.surfaceElevated)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .help("Play offline")
            }

            Button {
                manager.delete(item)
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(MoonlitTheme.textSecondary)
                    .frame(width: 34, height: 34)
                    .background(MoonlitTheme.surfaceElevated)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .help("Delete download")
        }
    }

    private func statusLine(_ item: DownloadItem) -> String {
        switch item.state {
        case .queued: return "Queued"
        case .downloading:
            let pct = Int((item.progress * 100).rounded())
            return "Downloading \(pct)% · \(byteString(item.receivedBytes)) / \(byteString(item.totalBytes))"
        case .paused: return "Paused"
        case .completed:
            let parts = [item.quality, byteString(item.totalBytes)].compactMap { $0 }
            return parts.joined(separator: " · ")
        case .failed: return "Failed"
        }
    }

    private func byteString(_ bytes: Int64) -> String {
        guard bytes > 0 else { return "—" }
        return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    private func play(_ item: DownloadItem) {
        let localURL = manager.localURL(for: item)
        let launch = PlayerLaunch(
            title: item.name,
            sourceUrl: localURL.absoluteString,
            poster: item.poster,
            streamTitle: item.quality,
            providerName: "Downloads",
            contentType: MediaType(rawValue: item.type) ?? .movie,
            videoId: item.mediaId,
            parentMetaId: item.mediaId,
            parentMetaType: item.type
        )
        openWindow(id: "player", value: launch)
    }
}
