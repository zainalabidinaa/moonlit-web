import SwiftUI
import MoonlitCore

struct VideoPlayerSettingsScreen: View {
    @StateObject private var prefs = VideoPlayerPreferenceStore.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 6) {

                settingsSectionLabel("Playback")
                VStack(spacing: 0) {
                    toggleRow("Autoplay next episode", isOn: Binding(
                        get: { prefs.autoplayNextEpisode },
                        set: { prefs.autoplayNextEpisode = $0 }
                    ))
                    Divider().background(Color.white.opacity(0.08))
                    pickerRow("Show Next Episode when", value: "\(prefs.showNextEpisodeSecondsRemaining)s remaining") {
                        Picker("", selection: Binding(
                            get: { prefs.showNextEpisodeSecondsRemaining },
                            set: { prefs.showNextEpisodeSecondsRemaining = $0 }
                        )) {
                            ForEach([15, 20, 30, 45, 60], id: \.self) { s in
                                Text("\(s) seconds").tag(s)
                            }
                        }
                    }
                }
                .glassCard(cornerRadius: MoonlitTheme.radiusCard)
                .padding(.horizontal, 16)

                settingsSectionLabel("Skip Intro")
                VStack(spacing: 0) {
                    toggleRow("Show 'Skip Intro' when detected", isOn: Binding(
                        get: { prefs.showSkipIntroButton },
                        set: { prefs.showSkipIntroButton = $0 }
                    ))
                    Divider().background(Color.white.opacity(0.08))
                    toggleRow("Auto-skip intros when detected", isOn: Binding(
                        get: { prefs.autoSkipIntros },
                        set: { prefs.autoSkipIntros = $0 }
                    ))
                    Divider().background(Color.white.opacity(0.08))
                    toggleRow("Use IntroDB for TV episodes", isOn: Binding(
                        get: { prefs.useIntroDB },
                        set: { prefs.useIntroDB = $0 }
                    ))
                    Divider().background(Color.white.opacity(0.08))
                    toggleRow("Show highlights on timeline", isOn: Binding(
                        get: { prefs.showHighlightsOnTimeline },
                        set: { prefs.showHighlightsOnTimeline = $0 }
                    ))
                    Divider().background(Color.white.opacity(0.08))
                    toggleRow("Fallback skip when no intro data", isOn: Binding(
                        get: { prefs.fallbackSkipEnabled },
                        set: { prefs.fallbackSkipEnabled = $0 }
                    ))
                    if prefs.fallbackSkipEnabled {
                        Divider().background(Color.white.opacity(0.08))
                        pickerRow("Fallback skip duration", value: "\(prefs.fallbackSkipSeconds)s") {
                            Picker("", selection: Binding(
                                get: { prefs.fallbackSkipSeconds },
                                set: { prefs.fallbackSkipSeconds = $0 }
                            )) {
                                ForEach([30, 60, 85, 90, 120], id: \.self) { s in
                                    Text("\(s) seconds").tag(s)
                                }
                            }
                        }
                    }
                }
                .animation(.easeInOut(duration: 0.2), value: prefs.fallbackSkipEnabled)
                .glassCard(cornerRadius: MoonlitTheme.radiusCard)
                .padding(.horizontal, 16)

                Text("Skip timestamps sourced from PublicMetaDB. IntroDB provides additional crowdsourced intro data for TV shows.")
                    .font(.caption)
                    .foregroundColor(MoonlitTheme.textTertiary)
                    .padding(.horizontal, 20)

                settingsSectionLabel("Format Compatibility")
                VStack(spacing: 0) {
                    toggleRow("Show only compatible formats", isOn: Binding(
                        get: { prefs.showOnlyCompatibleFormats },
                        set: { prefs.showOnlyCompatibleFormats = $0 }
                    ))
                }
                .glassCard(cornerRadius: MoonlitTheme.radiusCard)
                .padding(.horizontal, 16)

                settingsSectionLabel("Media Type Players")
                VStack(spacing: 0) {
                    toggleRow("Use different players per media type", isOn: Binding(
                        get: { prefs.usePerTypePlayers },
                        set: { prefs.usePerTypePlayers = $0 }
                    ))
                    if prefs.usePerTypePlayers {
                        Divider().background(Color.white.opacity(0.08))
                        enginePickerRow("Movies", engine: Binding(
                            get: { prefs.moviePlayer },
                            set: { prefs.moviePlayer = $0 }
                        ))
                        Divider().background(Color.white.opacity(0.08))
                        enginePickerRow("Series", engine: Binding(
                            get: { prefs.seriesPlayer },
                            set: { prefs.seriesPlayer = $0 }
                        ))
                        Divider().background(Color.white.opacity(0.08))
                        enginePickerRow("Live", engine: Binding(
                            get: { prefs.livePlayer },
                            set: { prefs.livePlayer = $0 }
                        ))
                    }
                }
                .glassCard(cornerRadius: MoonlitTheme.radiusCard)
                .padding(.horizontal, 16)
                .animation(.easeInOut(duration: 0.2), value: prefs.usePerTypePlayers)

                Text("Auto-Detect: .m3u8/HLS uses AVPlayer; .mkv/.avi and complex formats use the built-in player.")
                    .font(.caption)
                    .foregroundColor(MoonlitTheme.textTertiary)
                    .padding(.horizontal, 20)

                settingsSectionLabel("Cache Mode")
                VStack(spacing: 0) {
                    pickerRow("Cache mode", value: prefs.cacheMode.displayName) {
                        Picker("", selection: Binding(
                            get: { prefs.cacheMode },
                            set: { prefs.cacheMode = $0 }
                        )) {
                            ForEach(CacheMode.allCases, id: \.self) { mode in
                                Text(mode.displayName).tag(mode)
                            }
                        }
                    }
                }
                .glassCard(cornerRadius: MoonlitTheme.radiusCard)
                .padding(.horizontal, 16)

                Text("Memory buffers in RAM for smooth playback. Disk caches segments for resume. Off streams live.")
                    .font(.caption)
                    .foregroundColor(MoonlitTheme.textTertiary)
                    .padding(.horizontal, 20)

                settingsSectionLabel("Previews")
                VStack(spacing: 0) {
                    toggleRow("Autoplay previews in Home", isOn: Binding(
                        get: { prefs.autoplayPreviews },
                        set: { prefs.autoplayPreviews = $0 }
                    ))
                    Divider().background(Color.white.opacity(0.08))
                    toggleRow("Play preview sound", isOn: Binding(
                        get: { prefs.playPreviewSound },
                        set: { prefs.playPreviewSound = $0 }
                    ))
                }
                .glassCard(cornerRadius: MoonlitTheme.radiusCard)
                .padding(.horizontal, 16)

                Spacer().frame(height: 32)
            }
            .padding(.top, 16)
        }
        .background(MoonlitTheme.background)
        .navigationTitle("Video Player")
#if os(iOS)
        .navigationBarTitleDisplayMode(.large)
#endif
    }

    private func toggleRow(_ title: String, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            Text(title)
                .font(.subheadline)
                .foregroundColor(.white)
        }
        .toggleStyle(.switch)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private func pickerRow<Content: View>(_ title: String, value: String, @ViewBuilder picker: () -> Content) -> some View {
        HStack {
            Text(title)
                .font(.subheadline)
                .foregroundColor(.white)
            Spacer()
            picker()
                .labelsHidden()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
    }

    private func enginePickerRow(_ label: String, engine: Binding<VideoPlayerEngineOption>) -> some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundColor(.white)
            Spacer()
            Picker("", selection: engine) {
                ForEach(VideoPlayerEngineOption.allCases, id: \.self) { e in
                    Text(e.displayName).tag(e)
                }
            }
            .labelsHidden()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
    }
}

@MainActor
private func settingsSectionLabel(_ text: String) -> some View {
    Text(text.uppercased())
        .font(.caption.weight(.semibold))
        .foregroundColor(MoonlitTheme.textTertiary)
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 2)
}
