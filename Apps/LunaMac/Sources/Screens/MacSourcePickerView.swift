import SwiftUI
import LunaCore

struct MacSourcePickerView: View {
    let mediaType: MediaType
    let mediaId: String
    let mediaName: String
    let poster: String?
    let logo: String?
    let onLaunch: (PlayerLaunch) -> Void

    @StateObject private var streamRepo = StreamRepository.shared
    @StateObject private var addonRepo = AddonRepository.shared
    @Environment(\.dismiss) var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Select Source")
                    .font(.headline)
                    .foregroundColor(.white)
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .foregroundColor(LunaTheme.textSecondary)
                }
                .buttonStyle(.plain)
            }
            .padding()

            if streamRepo.isLoading {
                Spacer()
                ProgressView().tint(LunaTheme.accent)
                Spacer()
            } else if streamRepo.streams.isEmpty {
                Spacer()
                VStack(spacing: 8) {
                    Image(systemName: "play.slash")
                        .font(.title)
                        .foregroundColor(LunaTheme.textTertiary)
                    Text("No streams available")
                        .foregroundColor(LunaTheme.textSecondary)
                }
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(groupedByAddon, id: \.key) { addonName, streams in
                            VStack(alignment: .leading, spacing: 0) {
                                Text(addonName)
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(LunaTheme.textTertiary)
                                    .tracking(1)
                                    .textCase(.uppercase)
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 8)

                                ForEach(streams) { stream in
                                    Button {
                                        guard let url = stream.url else { return }
                                        let launch = PlayerLaunch(
                                            title: mediaName,
                                            sourceUrl: url,
                                            sourceHeaders: stream.behaviorHints?.proxyHeaders?.request,
                                            logo: logo,
                                            poster: poster,
                                            streamTitle: stream.displayName,
                                            providerName: stream.addonName,
                                            contentType: mediaType,
                                            videoId: mediaId
                                        )
                                        onLaunch(launch)
                                    } label: {
                                        StreamRowView(stream: stream)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.bottom, 8)
                        }
                    }
                    .padding(.vertical, 8)
                }
            }
        }
        .frame(minWidth: 500, minHeight: 400)
        .background(LunaTheme.background)
        .task {
            await streamRepo.fetchStreams(
                type: mediaType.rawValue,
                id: mediaId,
                addons: addonRepo.enabledAddons
            )
        }
    }

    private var groupedByAddon: [(key: String, value: [StreamItem])] {
        let grouped = Dictionary(grouping: streamRepo.streams) { $0.addonName ?? "Unknown" }
        return grouped.sorted { $0.key < $1.key }
    }
}

struct StreamRowView: View {
    let stream: StreamItem
    @State private var isHovering = false

    private var meta: StreamMetadata { stream.parseMetadata() }

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    if let res = meta.resolution {
                        Text(res)
                            .font(.system(size: 10, weight: .bold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(resolutionColor)
                            .foregroundColor(.black)
                            .cornerRadius(4)
                    }
                    if let codec = meta.videoCodec {
                        Text(codec)
                            .font(.system(size: 10))
                            .foregroundColor(LunaTheme.textTertiary)
                    }
                    if let audio = meta.audioCodec {
                        Text(audio)
                            .font(.system(size: 10))
                            .foregroundColor(LunaTheme.textTertiary)
                    }
                    if let hdr = meta.hdr {
                        Text(hdr)
                            .font(.system(size: 10, weight: .bold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.purple.opacity(0.3))
                            .foregroundColor(LunaTheme.accent)
                            .cornerRadius(4)
                    }
                }

                Text(stream.displayName)
                    .font(.subheadline)
                    .foregroundColor(.white)
                    .lineLimit(1)

                if let desc = stream.description, !desc.isEmpty {
                    Text(desc)
                        .font(.caption2)
                        .foregroundColor(LunaTheme.textTertiary)
                        .lineLimit(2)
                }
            }

            Spacer()

            Image(systemName: "play.circle.fill")
                .font(.title3)
                .foregroundColor(LunaTheme.accent)
                .opacity(isHovering ? 1 : 0.5)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(isHovering ? LunaTheme.surfaceElevated : LunaTheme.surface)
        .onHover { isHovering = $0 }
    }

    private var resolutionColor: Color {
        guard let res = meta.resolution?.uppercased() else { return .gray }
        if res.contains("4K") || res.contains("2160") { return .yellow }
        if res.contains("1080") { return .blue }
        return .green
    }
}
