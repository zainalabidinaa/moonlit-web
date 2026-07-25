import SwiftUI
import MoonlitCore

struct EpisodesPanel: View {
    @ObservedObject var engine: PlayerEngine
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                MoonlitTheme.background.ignoresSafeArea()

                VStack(spacing: 16) {
                    if let launch = engine.currentLaunch {
                        Text(launch.title)
                            .font(.title3.weight(.semibold))
                            .foregroundColor(.white)

                        if let season = launch.seasonNumber, let episode = launch.episodeNumber {
                            Text("Season \(season) • Episode \(episode)")
                                .font(.subheadline)
                                .foregroundColor(MoonlitTheme.textSecondary)
                        }
                    }
                    Spacer()
                }
                .padding()
            }
            .navigationTitle("Episodes")
#if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
#endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
