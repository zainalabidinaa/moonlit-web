import SwiftUI
import MoonlitCore

/// Lets the user choose which btttr "BetterPosters" badges appear on grid/library/
/// search posters, with a live preview using *Silo*. Toggles persist to the same
/// `moonlit.poster.*` UserDefaults keys `PosterService` reads, so the preview here
/// matches real posters exactly. Pushed via `NavigationLink` (no own NavigationStack).
struct PosterBadgesScreen: View {
    // Defaults mirror PosterService.registerDefaults (Genre + Rating + Trend on).
    @AppStorage(PosterService.Key.trend)   private var trend   = true
    @AppStorage(PosterService.Key.quality) private var quality = false
    @AppStorage(PosterService.Key.genre)   private var genre   = true
    @AppStorage(PosterService.Key.rating)  private var rating  = true
    @AppStorage(PosterService.Key.age)     private var age     = false

    /// Sample title for the live preview: Silo.
    private let previewImdbId = "tt14688458"

    private var previewURL: URL? {
        PosterService.posterURL(forImdbId: previewImdbId).flatMap(URL.init)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 6) {
                previewPanel

                sectionLabel("Badges")
                VStack(spacing: 0) {
                    toggleRow("Trend tag", subtitle: "e.g. \u{201C}#4 Today\u{201D}", isOn: $trend)
                    rowDivider
                    toggleRow("Quality", subtitle: "Dolby, 4K, HDR", isOn: $quality)
                    rowDivider
                    toggleRow("Genre", isOn: $genre)
                    rowDivider
                    toggleRow("Rating", subtitle: "IMDb score", isOn: $rating)
                    rowDivider
                    toggleRow("Age rating", subtitle: "e.g. TV-MA", isOn: $age)
                }
                .glassCard(cornerRadius: MoonlitTheme.radiusCard)
                .padding(.horizontal, 16)

                Text("Badges appear on posters across Home, Library and Search. Changes take full effect on already-loaded rows after a refresh.")
                    .font(.caption)
                    .foregroundColor(MoonlitTheme.textTertiary)
                    .padding(.horizontal, 22)
                    .padding(.top, 8)

                Spacer().frame(height: 32)
            }
            .padding(.top, 8)
        }
        .background(MoonlitTheme.background)
        .navigationTitle("Poster Badges")
#if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
#endif
    }

    private var previewPanel: some View {
        VStack(spacing: 10) {
            ZStack {
                if let url = previewURL {
                    LadderedCachedImage(urls: [url]) { phase in
                        if case .success(let image) = phase {
                            image
                                .resizable()
                                .scaledToFit()
                                .transition(.opacity)
                        } else {
                            ProgressView().tint(.white)
                        }
                    }
                } else {
                    Color.clear
                }
            }
            .frame(width: 200, height: 300)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
            )
            .frame(maxWidth: .infinity)

            Text("Live preview \u{00B7} Silo")
                .font(.caption)
                .foregroundColor(MoonlitTheme.textTertiary)
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    private var rowDivider: some View {
        Divider().background(Color.white.opacity(0.08))
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.caption.weight(.semibold))
            .foregroundColor(MoonlitTheme.textTertiary)
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 2)
    }

    private func toggleRow(_ title: String, subtitle: String? = nil, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                    .foregroundColor(.white)
                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(MoonlitTheme.textSecondary)
                }
            }
        }
        .toggleStyle(.switch)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}
