import SwiftUI
import MoonlitCore

struct SubtitlePickerPanel: View {
    @ObservedObject var engine: PlayerEngine
    @Binding var isShowing: Bool
    @State private var expandedLang: String? = nil
    /// Frozen snapshot captured when the panel first appears.
    /// Prevents live engine.availableSubtitles updates from
    /// rebuilding the list and resetting the scroll position.
    @State private var snapshot: [(lang: String, items: [SubtitleItem])] = []
    /// ID of the row to keep in view — updated on appear and selection.
    @State private var subtitleScrollAnchor: String? = nil

    private func displayName(for code: String) -> String {
        Locale.current.localizedString(forLanguageCode: code)?.capitalized ?? code.uppercased()
    }

    /// Capture the current subtitle list into a stable snapshot.
    private func captureSnapshot() {
        let dict = Dictionary(grouping: engine.availableSubtitles, by: { $0.lang })
        snapshot = dict.keys.sorted().map { lang in
            (lang: lang, items: dict[lang]!.sorted { ($0.name ?? $0.lang) < ($1.name ?? $1.lang) })
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            panelHeader(title: "Subtitles")

            Divider().background(Color.white.opacity(0.15))

            ScrollViewReader { proxy in
                ScrollView(showsIndicators: false) {
                    LazyVStack(spacing: 0) {
                        // Off row
                        pickerRow(label: "Off", rowID: "__off__", isSelected: engine.selectedSubtitle == nil, chevron: false) {
                            engine.setSubtitle(nil)
                            subtitleScrollAnchor = "__off__"
                            withAnimation(.easeInOut(duration: 0.2)) { isShowing = false }
                        }

                        Divider().background(Color.white.opacity(0.12))

                        // Language groups (from frozen snapshot)
                        ForEach(snapshot, id: \.lang) { group in
                            let isSingle = group.items.count == 1
                            let isExpanded = expandedLang == group.lang

                            pickerRow(
                                label: displayName(for: group.lang),
                                rowID: group.lang,
                                isSelected: group.items.contains { $0.id == engine.selectedSubtitle?.id },
                                chevron: !isSingle,
                                chevronDown: isExpanded
                            ) {
                                if isSingle {
                                    engine.setSubtitle(group.items.first)
                                    subtitleScrollAnchor = group.lang
                                    withAnimation(.easeInOut(duration: 0.2)) { isShowing = false }
                                } else {
                                    withAnimation(.easeInOut(duration: 0.2)) {
                                        expandedLang = isExpanded ? nil : group.lang
                                    }
                                }
                            }

                            if isExpanded {
                                ForEach(group.items) { item in
                                    let isItemSelected = engine.selectedSubtitle?.id == item.id
                                    pickerRow(
                                        label: item.name ?? item.lang,
                                        rowID: item.id,
                                        isSelected: isItemSelected,
                                        chevron: false,
                                        indent: true
                                    ) {
                                        engine.setSubtitle(item)
                                        subtitleScrollAnchor = item.id
                                        withAnimation(.easeInOut(duration: 0.2)) { isShowing = false }
                                    }
                                }
                            }

                            Divider().background(Color.white.opacity(0.08))
                        }
                    }
                }
                .frame(maxHeight: 260)
                .onAppear {
                    captureSnapshot()
                    // Scroll to the selected subtitle lang row, or "Off" if nothing selected.
                    subtitleScrollAnchor = engine.selectedSubtitle.map { $0.lang } ?? "__off__"
                    // Small delay so LazyVStack finishes layout before scrollTo fires.
                    if let anchor = subtitleScrollAnchor {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                proxy.scrollTo(anchor, anchor: .center)
                            }
                        }
                    }
                }
            }
        }
        .frame(width: 210)
        .playerGlassPanel(cornerRadius: MoonlitTheme.radiusCard)
    }

    @ViewBuilder
    private func panelHeader(title: String) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.white)
            Spacer()
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { isShowing = false }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white.opacity(0.7))
                    .frame(width: 26, height: 26)
                    .glassCircle(clear: true)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.top, 10)
        .padding(.bottom, 8)
    }

    @ViewBuilder
    private func pickerRow(
        label: String,
        rowID: String,
        isSelected: Bool,
        chevron: Bool,
        chevronDown: Bool = false,
        indent: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if indent {
                    Color.clear.frame(width: 14)
                }
                Text(label)
                    .font(.system(size: 13, weight: indent ? .regular : .medium))
                    .foregroundColor(indent ? .white.opacity(0.75) : .white)
                    .lineLimit(1)
                Spacer(minLength: 4)
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(MoonlitTheme.accent)
                } else if chevron {
                    Image(systemName: chevronDown ? "chevron.down" : "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.white.opacity(0.45))
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(isSelected ? Color.white.opacity(0.07) : Color.clear)
        }
        .buttonStyle(.plain)
        .id(rowID)
    }
}

enum PlayerTrackPanelDestination: String {
    case subtitles = "Subtitles"
    case audio = "Audio"
}

private enum PlayerSubtitlePanelTab: String, CaseIterable {
    case languages = "Languages"
    case appearance = "Appearance"
}

struct PlayerTrackPanel: View {
    let destination: PlayerTrackPanelDestination
    let audioTracks: [PlayerAudioTrack]
    let subtitles: [SubtitleItem]
    let selectedAudioID: Int64?
    let selectedSubtitleID: String?
    let onSelectAudio: (Int64) -> Void
    let onSelectSubtitle: (SubtitleItem?) -> Void
    let onAdvancedAppearance: () -> Void
    let onClose: () -> Void

    @ObservedObject private var appearance = SubtitleAppearanceStore.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var subtitleTab: PlayerSubtitlePanelTab = .languages
    @State private var expandedLanguage: String?

    private var audioGroups: [PlayerTrackLanguageGroup<PlayerAudioTrack>] {
        PlayerTrackGrouping.audioGroups(audioTracks)
    }

    private var subtitleGroups: [PlayerTrackLanguageGroup<SubtitleItem>] {
        PlayerTrackGrouping.subtitleGroups(subtitles)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            Divider()
                .overlay(Color.white.opacity(0.12))

            if destination == .subtitles {
                subtitleTabs
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)

                if subtitleTab == .languages {
                    subtitleLanguageList
                } else {
                    subtitleAppearance
                }
            } else {
                audioLanguageList
            }
        }
        .frame(width: 360)
        .frame(maxHeight: 410)
        .playerGlassPanel(cornerRadius: 26)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(destination.rawValue) options")
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: destination == .subtitles ? "captions.bubble.fill" : "waveform")
                .font(.system(size: 17, weight: .semibold))

            Text(destination.rawValue)
                .font(.system(size: 17, weight: .semibold))

            Spacer()

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .bold))
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close \(destination.rawValue)")
        }
        .foregroundStyle(.white)
        .padding(.leading, 18)
        .padding(.trailing, 8)
        .padding(.vertical, 4)
    }

    private var subtitleTabs: some View {
        HStack(spacing: 6) {
            ForEach(PlayerSubtitlePanelTab.allCases, id: \.self) { tab in
                Button {
                    withAnimation(reduceMotion ? nil : .smooth(duration: 0.2)) {
                        subtitleTab = tab
                    }
                } label: {
                    Text(tab.rawValue)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(subtitleTab == tab ? .black : .white)
                        .frame(maxWidth: .infinity, minHeight: 38)
                        .background(
                            subtitleTab == tab ? Color.white : Color.white.opacity(0.08),
                            in: Capsule()
                        )
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(subtitleTab == tab ? .isSelected : [])
            }
        }
    }

    private var subtitleLanguageList: some View {
        ScrollView(showsIndicators: false) {
            LazyVStack(spacing: 2) {
                selectionRow(
                    title: "Off",
                    subtitle: "Hide subtitles",
                    selected: selectedSubtitleID == nil
                ) {
                    onSelectSubtitle(nil)
                }

                ForEach(subtitleGroups) { group in
                    languageGroup(
                        languageCode: group.languageCode,
                        languageName: group.localizedName,
                        itemCount: group.items.count,
                        containsSelection: group.items.contains { $0.id == selectedSubtitleID }
                    ) {
                        if group.items.count == 1 {
                            onSelectSubtitle(group.items[0])
                        } else {
                            toggleExpanded(group.languageCode)
                        }
                    }

                    if expandedLanguage == group.languageCode, group.items.count > 1 {
                        ForEach(Array(group.items.enumerated()), id: \.element.id) { index, item in
                            selectionRow(
                                title: subtitleVariantLabel(item, index: index),
                                subtitle: nil,
                                selected: selectedSubtitleID == item.id,
                                indented: true
                            ) {
                                onSelectSubtitle(item)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 12)
        }
    }

    private var audioLanguageList: some View {
        Group {
            if audioGroups.isEmpty {
                ContentUnavailableView(
                    "No Audio Tracks",
                    systemImage: "waveform.slash",
                    description: Text("This stream exposes only its default audio.")
                )
                .foregroundStyle(.white.opacity(0.7))
                .frame(maxWidth: .infinity, minHeight: 220)
            } else {
                ScrollView(showsIndicators: false) {
                    LazyVStack(spacing: 2) {
                        ForEach(audioGroups) { group in
                            languageGroup(
                                languageCode: group.languageCode,
                                languageName: group.localizedName,
                                itemCount: group.items.count,
                                containsSelection: group.items.contains { $0.id == selectedAudioID }
                            ) {
                                if group.items.count == 1 {
                                    onSelectAudio(group.items[0].id)
                                } else {
                                    toggleExpanded(group.languageCode)
                                }
                            }

                            if expandedLanguage == group.languageCode, group.items.count > 1 {
                                ForEach(Array(group.items.enumerated()), id: \.element.id) { index, item in
                                    selectionRow(
                                        title: audioVariantLabel(item, index: index),
                                        subtitle: nil,
                                        selected: selectedAudioID == item.id,
                                        indented: true
                                    ) {
                                        onSelectAudio(item.id)
                                    }
                                }
                            }
                        }
                    }
                    .padding(10)
                }
            }
        }
    }

    private var subtitleAppearance: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 14) {
                Text("QUICK STYLES")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.5))

                LazyVGrid(columns: [
                    GridItem(.flexible(), spacing: 8),
                    GridItem(.flexible(), spacing: 8)
                ], spacing: 8) {
                    ForEach(SubtitlePreset.allCases, id: \.self) { preset in
                        Button {
                            applyPreset(preset)
                        } label: {
                            HStack {
                                Text(preset.displayName)
                                    .font(.system(size: 12, weight: .semibold))
                                Spacer()
                                if appearance.preset == preset {
                                    Image(systemName: "checkmark")
                                        .font(.caption.bold())
                                }
                            }
                            .foregroundStyle(.white)
                            .padding(.horizontal, 12)
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .background(
                                appearance.preset == preset
                                    ? Color.white.opacity(0.18)
                                    : Color.white.opacity(0.07),
                                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }

                appearanceSlider(
                    title: "Text Size",
                    value: Binding(
                        get: { appearance.fontSize },
                        set: { appearance.fontSize = $0 }
                    ),
                    range: 12...72,
                    valueLabel: "\(Int(appearance.fontSize))"
                )

                appearanceSlider(
                    title: "Vertical Position",
                    value: Binding(
                        get: {
                            SubtitleRenderingMetrics.bottomMargin(
                                appearance.verticalPosition
                            )
                        },
                        set: {
                            appearance.verticalPosition =
                                SubtitleRenderingMetrics.bottomMargin($0)
                        }
                    ),
                    range: SubtitleRenderingMetrics.bottomMarginRange,
                    valueLabel: "\(Int(SubtitleRenderingMetrics.bottomMargin(appearance.verticalPosition)))"
                )

                Button(action: onAdvancedAppearance) {
                    HStack {
                        Label("Advanced", systemImage: "slider.horizontal.3")
                        Spacer()
                        Image(systemName: "chevron.right")
                    }
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .frame(minHeight: 46)
                    .background(Color.white.opacity(0.08), in: Capsule())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
        }
    }

    private func languageGroup(
        languageCode: String,
        languageName: String,
        itemCount: Int,
        containsSelection: Bool,
        action: @escaping () -> Void
    ) -> some View {
        selectionRow(
            title: languageName,
            subtitle: itemCount > 1 ? "\(itemCount) options" : nil,
            selected: containsSelection,
            trailingSymbol: itemCount > 1
                ? (expandedLanguage == languageCode ? "chevron.down" : "chevron.right")
                : nil,
            action: action
        )
    }

    private func selectionRow(
        title: String,
        subtitle: String?,
        selected: Bool,
        indented: Bool = false,
        trailingSymbol: String? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                if indented {
                    Color.clear.frame(width: 18)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 13, weight: indented ? .regular : .medium))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    if let subtitle {
                        Text(subtitle)
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.45))
                    }
                }

                Spacer()

                if selected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.white)
                } else if let trailingSymbol {
                    Image(systemName: trailingSymbol)
                        .font(.caption.bold())
                        .foregroundStyle(.white.opacity(0.5))
                }
            }
            .padding(.horizontal, 12)
            .frame(minHeight: 46)
            .background(selected ? Color.white.opacity(0.12) : Color.clear, in: .rect(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }

    private func appearanceSlider(
        title: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        valueLabel: String
    ) -> some View {
        VStack(spacing: 5) {
            HStack {
                Text(title)
                Spacer()
                Text(valueLabel)
                    .monospacedDigit()
                    .foregroundStyle(.white.opacity(0.6))
            }
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(.white)

            Slider(value: value, in: range)
                .tint(.white)
                .frame(minHeight: 44)
        }
    }

    private func toggleExpanded(_ languageCode: String) {
        withAnimation(reduceMotion ? nil : .smooth(duration: 0.2)) {
            expandedLanguage = expandedLanguage == languageCode ? nil : languageCode
        }
    }

    private func audioVariantLabel(_ track: PlayerAudioTrack, index: Int) -> String {
        track.variantLabel == "Audio Track" ? "Track \(index + 1)" : track.variantLabel
    }

    private func subtitleVariantLabel(_ subtitle: SubtitleItem, index: Int) -> String {
        let name = subtitle.name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return name.isEmpty ? "Subtitle \(index + 1)" : name
    }

    private func applyPreset(_ preset: SubtitlePreset) {
        appearance.preset = preset
        appearance.textColorHex = preset == .classic ? "#FFFF00" : "#FFFFFF"
        appearance.outlineColorHex = "#000000"
        appearance.backgroundColorHex = "#000000"
        appearance.backgroundOpacity = preset == .boxed ? 0.75 : 0
        appearance.isBold = false
    }
}

/// Native system menus isolated from the playback timeline. Equatable inputs keep
/// SwiftUI from rebuilding an open menu for every quarter-second progress update.
struct PlayerNativeTrackMenus: View, Equatable {
    let audioTracks: [PlayerAudioTrack]
    let subtitles: [SubtitleItem]
    let selectedAudioID: Int64?
    let selectedSubtitleID: String?
    let onSelectAudio: (Int64) -> Void
    let onSelectSubtitle: (SubtitleItem?) -> Void
    let onCustomizeSubtitles: () -> Void
    let onMenuPresented: () -> Void
    let onMenuDismissed: () -> Void

    init(
        audioTracks: [PlayerAudioTrack],
        subtitles: [SubtitleItem],
        selectedAudioID: Int64?,
        selectedSubtitleID: String?,
        onSelectAudio: @escaping (Int64) -> Void,
        onSelectSubtitle: @escaping (SubtitleItem?) -> Void,
        onCustomizeSubtitles: @escaping () -> Void,
        onMenuPresented: @escaping () -> Void = {},
        onMenuDismissed: @escaping () -> Void = {}
    ) {
        self.audioTracks = audioTracks
        self.subtitles = subtitles
        self.selectedAudioID = selectedAudioID
        self.selectedSubtitleID = selectedSubtitleID
        self.onSelectAudio = onSelectAudio
        self.onSelectSubtitle = onSelectSubtitle
        self.onCustomizeSubtitles = onCustomizeSubtitles
        self.onMenuPresented = onMenuPresented
        self.onMenuDismissed = onMenuDismissed
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.audioTracks == rhs.audioTracks
            && lhs.subtitles == rhs.subtitles
            && lhs.selectedAudioID == rhs.selectedAudioID
            && lhs.selectedSubtitleID == rhs.selectedSubtitleID
    }

    private var audioGroups: [PlayerTrackLanguageGroup<PlayerAudioTrack>] {
        PlayerTrackGrouping.audioGroups(audioTracks)
    }

    private var subtitleGroups: [PlayerTrackLanguageGroup<SubtitleItem>] {
        PlayerTrackGrouping.subtitleGroups(subtitles)
    }

    // No per-icon glass here — the whole group (this HStack plus `moreMenu` in
    // PlayerScreen) shares ONE glass surface applied by the caller, matching
    // the Apple TV player's single unified control pill instead of three
    // separate floating circles.
    var body: some View {
        HStack(spacing: 0) {
            subtitleMenu
            trackMenuDivider
            audioMenu
        }
    }

    private var subtitleMenu: some View {
        Menu {
            Button("Customize Subtitles…", systemImage: "textformat") {
                onCustomizeSubtitles()
            }

            Divider()

            if subtitleGroups.isEmpty {
                Button("No subtitle tracks") {}
                    .disabled(true)
            }

            ForEach(subtitleGroups) { group in
                if group.items.count == 1, let subtitle = group.items.first {
                    Button {
                        onSelectSubtitle(subtitle)
                    } label: {
                        nativeSelectionLabel(
                            group.localizedName,
                            selected: selectedSubtitleID == subtitle.id
                        )
                    }
                } else {
                    Menu(group.localizedName) {
                        ForEach(Array(group.items.enumerated()), id: \.element.id) { index, subtitle in
                            Button {
                                onSelectSubtitle(subtitle)
                            } label: {
                                nativeSelectionLabel(
                                    subtitleVariantLabel(subtitle, index: index),
                                    selected: selectedSubtitleID == subtitle.id
                                )
                            }
                        }
                    }
                }
            }

            Divider()

            Button {
                onSelectSubtitle(nil)
            } label: {
                nativeSelectionLabel("Off", selected: selectedSubtitleID == nil)
            }

            menuLifecycleObserver
        } label: {
            nativeMenuIcon("captions.bubble")
        }
        .buttonStyle(.plain)
        .tint(.white)
        .accessibilityLabel("Subtitles")
    }

    private var audioMenu: some View {
        Menu {
            if audioGroups.isEmpty {
                Button("No audio tracks") {}
                    .disabled(true)
            } else {
                ForEach(audioGroups) { group in
                    if group.items.count == 1, let track = group.items.first {
                        Button {
                            onSelectAudio(track.id)
                        } label: {
                            nativeSelectionLabel(
                                group.localizedName,
                                selected: selectedAudioID == track.id
                            )
                        }
                    } else {
                        Menu(group.localizedName) {
                            ForEach(Array(group.items.enumerated()), id: \.element.id) { index, track in
                                Button {
                                    onSelectAudio(track.id)
                                } label: {
                                    nativeSelectionLabel(
                                        audioVariantLabel(track, index: index),
                                        selected: selectedAudioID == track.id
                                    )
                                }
                            }
                        }
                    }
                }
            }
            menuLifecycleObserver
        } label: {
            nativeMenuIcon("waveform")
        }
        .buttonStyle(.plain)
        .tint(.white)
        .accessibilityLabel("Audio")
    }

    /// Hairline separator between icons sharing one glass pill — Apple TV's
    /// unified control group uses the same thin division instead of gaps.
    var trackMenuDivider: some View {
        Divider()
            .frame(width: 0.75, height: 22)
            .overlay(Color.white.opacity(0.18))
    }

    private var menuLifecycleObserver: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .onAppear(perform: onMenuPresented)
            .onDisappear(perform: onMenuDismissed)
    }

    @ViewBuilder
    private func nativeSelectionLabel(_ title: String, selected: Bool) -> some View {
        if selected {
            Label(title, systemImage: "checkmark")
        } else {
            Text(title)
        }
    }

    // No `isActive` background plate. It was meant to flag a non-default selection,
    // but audio always has a selected track during normal playback — the circle was
    // permanently on, reading as an unexplained grey background rather than a state
    // indicator. Icon-only controls here share ONE glass surface with the rest of the
    // group (see the comment on `body` above); a per-icon fill undermines that.
    private func nativeMenuIcon(_ systemName: String) -> some View {
        Image(systemName: systemName)
            .renderingMode(.template)
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(.white.opacity(0.92))
            .frame(width: 44, height: 44)
    }

    private func audioVariantLabel(_ track: PlayerAudioTrack, index: Int) -> String {
        track.variantLabel == "Audio Track" ? "Track \(index + 1)" : track.variantLabel
    }

    private func subtitleVariantLabel(_ subtitle: SubtitleItem, index: Int) -> String {
        let name = subtitle.name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return name.isEmpty ? "Subtitle \(index + 1)" : name
    }
}
