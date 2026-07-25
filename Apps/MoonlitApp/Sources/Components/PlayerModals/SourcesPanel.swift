import SwiftUI
import MoonlitCore

struct SourcesPanel: View {
    @ObservedObject var engine: PlayerEngine
    @Binding var isShowing: Bool
    let onSelect: (StreamItem) -> Void

    @StateObject private var streamRepo = StreamRepository.shared
    @State private var playableStreams: [StreamItem] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            panelHeader

            Divider().background(Color.white.opacity(0.14))

            if playableStreams.isEmpty {
                Text(streamRepo.isLoading ? "Finding sources..." : "No sources loaded")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.white.opacity(0.55))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
            } else {
                ScrollView(showsIndicators: false) {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(playableStreams) { stream in
                            Button {
                                onSelect(stream)
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    isShowing = false
                                }
                            } label: {
                                HStack(spacing: 10) {
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(stream.displayName)
                                            .font(.system(size: 13, weight: .semibold))
                                            .foregroundColor(.white)
                                            .lineLimit(1)
                                        if let desc = stream.description {
                                            Text(desc)
                                                .font(.system(size: 11, weight: .medium))
                                                .foregroundColor(.white.opacity(0.52))
                                                .lineLimit(1)
                                        }
                                    }

                                    Spacer(minLength: 6)

                                    if stream.url == engine.currentLaunch?.sourceUrl {
                                        Image(systemName: "checkmark")
                                            .font(.system(size: 11, weight: .bold))
                                            .foregroundColor(MoonlitTheme.accent)
                                    }
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 9)
                                .background(stream.url == engine.currentLaunch?.sourceUrl ? Color.white.opacity(0.07) : .clear)
                            }
                            .buttonStyle(.plain)

                            Divider().background(Color.white.opacity(0.08))
                        }
                    }
                }
                .frame(maxHeight: 280)
            }
        }
        .frame(width: 250)
        .playerGlassPanel(cornerRadius: MoonlitTheme.radiusLarge)
        .onAppear {
            playableStreams = StreamSourceSelector.rankedCandidates(from: streamRepo.streams)
        }
        .onChange(of: streamRepo.streams) { _, streams in
            playableStreams = StreamSourceSelector.rankedCandidates(from: streams)
        }
    }

    private var panelHeader: some View {
        HStack {
            Text("Sources")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.white)
            Spacer()
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isShowing = false
                }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white.opacity(0.75))
                    .frame(width: 26, height: 26)
                    .glassCircle(clear: true)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.top, 10)
        .padding(.bottom, 8)
    }
}
