import SwiftUI
import MoonlitCore

struct MacVideoPlayerSettingsView: View {
    @StateObject private var prefs = VideoPlayerPreferenceStore.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack(alignment: .top) {
            MacFusionAmbientBackground(
                ambientColor: .clear,
                ambientColor2: .clear,
                isEnabled: true
            )
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {

                    sectionLabel("Playback")
                    settingsCard {
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

                    sectionLabel("Language")
                    settingsCard {
                        languagePickerRow("Preferred audio", selection: Binding(
                            get: { prefs.preferredAudioLanguage },
                            set: { prefs.preferredAudioLanguage = $0 }
                        ))
                        Divider().background(Color.white.opacity(0.08))
                        languagePickerRow("Preferred subtitles", selection: Binding(
                            get: { prefs.preferredSubtitleLanguage },
                            set: { prefs.preferredSubtitleLanguage = $0 }
                        ))
                    }
                    Text("Prefers streams that offer the selected audio language and preselects matching embedded audio and subtitle tracks. Subtitles aren't scanned or downloaded automatically.")
                        .font(.caption)
                        .foregroundColor(MoonlitTheme.textTertiary)
                        .padding(.horizontal, 20)

                    sectionLabel("Skip Intro")
                    settingsCard {
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

                    Text("Skip timestamps sourced from PublicMetaDB. IntroDB provides crowdsourced intro data for TV shows.")
                        .font(.caption)
                        .foregroundColor(MoonlitTheme.textTertiary)
                        .padding(.horizontal, 20)

                    sectionLabel("Video Enhancement")
                    settingsCard {
                        toggleRow("Anime4K upscaling", isOn: Binding(
                            get: { prefs.anime4KEnabled },
                            set: { prefs.anime4KEnabled = $0 }
                        ))
                    }
                    Text("Real-time upscaling and line restoration for animated content. Uses GPU compute shaders (may affect performance on integrated graphics).")
                        .font(.caption)
                        .foregroundColor(MoonlitTheme.textTertiary)
                        .padding(.horizontal, 20)

                    sectionLabel("Format Compatibility")
                    settingsCard {
                        toggleRow("Show only compatible formats", isOn: Binding(
                            get: { prefs.showOnlyCompatibleFormats },
                            set: { prefs.showOnlyCompatibleFormats = $0 }
                        ))
                    }

                    sectionLabel("Media Type Players")
                    settingsCard {
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
                    .animation(.easeInOut(duration: 0.2), value: prefs.usePerTypePlayers)

                    Text("Auto-Detect: .m3u8/HLS uses AVPlayer; .mkv/.avi and complex formats use KSPlayer.")
                        .font(.caption)
                        .foregroundColor(MoonlitTheme.textTertiary)
                        .padding(.horizontal, 20)

                    sectionLabel("Cache Mode")
                    settingsCard {
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
                    Text("Memory buffers in RAM for smooth playback. Disk caches segments for resume. Off streams live.")
                        .font(.caption)
                        .foregroundColor(MoonlitTheme.textTertiary)
                        .padding(.horizontal, 20)

                    sectionLabel("Previews")
                    settingsCard {
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

                    Spacer().frame(height: 32)
                }
                .padding(.top, 16)
            }
            .frame(minWidth: 460, minHeight: 500)
            .navigationTitle("Video Player")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .background(MoonlitTheme.background)
    }

    @ViewBuilder
    private func settingsCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 0) { content() }
            .background(MoonlitTheme.surface)
            .cornerRadius(MoonlitTheme.radiusControl)
            .padding(.horizontal, 16)
    }

    private func toggleRow(_ title: String, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            Text(title).font(.subheadline).foregroundColor(.white)
        }
        .toggleStyle(.switch)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private func pickerRow<Content: View>(_ title: String, value: String, @ViewBuilder picker: () -> Content) -> some View {
        HStack {
            Text(title).font(.subheadline).foregroundColor(.white)
            Spacer()
            picker().labelsHidden()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
    }

    private func enginePickerRow(_ label: String, engine: Binding<VideoPlayerEngineOption>) -> some View {
        HStack {
            Text(label).font(.subheadline).foregroundColor(.white)
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

    private func languagePickerRow(_ title: String, selection: Binding<String?>) -> some View {
        HStack {
            Text(title).font(.subheadline).foregroundColor(.white)
            Spacer()
            Picker("", selection: selection) {
                Text("System default").tag(String?.none)
                ForEach(PlaybackLanguage.all) { language in
                    Text("\(LanguageFlag.emoji(for: language.code))  \(language.name)")
                        .tag(String?.some(language.code))
                }
            }
            .labelsHidden()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
    }
}

@MainActor
private func sectionLabel(_ text: String) -> some View {
    Text(text.uppercased())
        .font(.caption.weight(.semibold))
        .foregroundColor(MoonlitTheme.textTertiary)
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 2)
}
