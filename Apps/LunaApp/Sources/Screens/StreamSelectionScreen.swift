import SwiftUI
import LunaCore

struct StreamSelectionScreen: View {
    let mediaType: MediaType
    let mediaId: String
    let mediaName: String
    let poster: String?
    let logo: String?

    @StateObject private var streamRepo = StreamRepository.shared
    @StateObject private var addonRepo = AddonRepository.shared
    @State private var selectedStream: StreamItem?
    @State private var showPlayer = false
    @State private var playerLaunch: PlayerLaunch?
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                LunaTheme.background.ignoresSafeArea()

                if streamRepo.isLoading {
                    ProgressView()
                        .tint(LunaTheme.accent)
                } else if streamRepo.streams.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "play.slash")
                            .font(.title)
                            .foregroundColor(LunaTheme.textTertiary)
                        Text("No streams available")
                            .foregroundColor(LunaTheme.textSecondary)
                    }
                } else {
                    List {
                        ForEach(groupedByAddon, id: \.key) { addonName, streams in
                            Section(addonName) {
                                ForEach(streams) { stream in
                                    Button {
                                        launchStream(stream)
                                    } label: {
                                        HStack {
                                            VStack(alignment: .leading) {
                                                Text(stream.displayName)
                                                    .foregroundColor(.white)
                                                if let desc = stream.description, !desc.isEmpty {
                                                    Text(desc)
                                                        .font(.caption)
                                                        .foregroundColor(LunaTheme.textSecondary)
                                                        .lineLimit(2)
                                                }
                                            }
                                            Spacer()
                                            Image(systemName: "play.circle.fill")
                                                .foregroundColor(LunaTheme.accent)
                                        }
                                    }
                                    .listRowBackground(LunaTheme.surface)
                                }
                            }
                        }
                    }
                    .scrollContentBackground(.hidden)
                }
            }
            .navigationTitle("Select Source")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .fullScreenCover(isPresented: $showPlayer) {
                if let launch = playerLaunch, let url = URL(string: launch.sourceUrl) {
                    PlayerScreen(
                        streamURL: url,
                        title: launch.title,
                        onDismiss: { showPlayer = false }
                    )
                }
            }
            .task {
                await streamRepo.fetchStreams(
                    type: mediaType.rawValue,
                    id: mediaId,
                    addons: addonRepo.enabledAddons
                )
            }
        }
    }

    private var groupedByAddon: [(key: String, value: [StreamItem])] {
        let grouped = Dictionary(grouping: streamRepo.streams) { $0.addonName ?? "Unknown" }
        return grouped.sorted { $0.key < $1.key }
    }

    private func launchStream(_ stream: StreamItem) {
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
            videoId: mediaId,
            initialPositionMs: nil
        )
        playerLaunch = launch
        showPlayer = true
    }
}
