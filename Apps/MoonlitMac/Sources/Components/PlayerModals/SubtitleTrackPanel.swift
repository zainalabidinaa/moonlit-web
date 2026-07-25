import SwiftUI
import MoonlitCore
import UniformTypeIdentifiers
#if os(macOS)
import AppKit
#endif

/// reference-style subtitle picker (`src/components/player/subtitle-menu`): a
/// solid-surface panel with filter chips, a language sidebar, circle-check
/// track rows with sky/amber badges, a search + local-file loader, and a
/// delay-sync footer.
struct SubtitleTrackPanel: View {
    @ObservedObject var engine: MPVPlayerEngine
    let externalSubtitles: [SubtitleItem]
    @Binding var selectedExternalSubtitle: SubtitleItem?
    let isLoadingExternal: Bool
    let error: String?
    let onSelectExternalSubtitle: (SubtitleItem) -> Void
    let onDisableExternalSubtitles: () -> Void
    let onClose: () -> Void

    private enum Category: String, CaseIterable {
        case all = "All", embedded = "Embedded", external = "External"
    }

    private enum Source { case embedded, external }

    private struct Row: Identifiable {
        let id: String
        let lang: String
        let name: String
        let source: Source
        let isHI: Bool
        let isForced: Bool
        let isSelected: Bool
        let select: () -> Void
    }

    @State private var selectedLanguage: String? = nil
    @State private var category: Category = .all
    @State private var showHIOnly = false
    @State private var showForcedOnly = false
    @State private var searchText = ""

    private func displayName(for lang: String) -> String {
        guard !lang.isEmpty, lang != "unknown", lang != "und" else { return "Unknown" }
        return Locale.current.localizedString(forLanguageCode: lang)?.capitalized ?? lang.uppercased()
    }

    private static func isHI(_ text: String) -> Bool {
        let lower = text.lowercased()
        return lower.contains("sdh") || lower.contains("hi") && lower.contains("hearing")
    }

    private static func isForced(_ text: String) -> Bool {
        text.lowercased().contains("forced")
    }

    private var allRows: [Row] {
        let embedded = engine.availableSubtitles.map { item -> Row in
            let name = item.name ?? displayName(for: item.lang)
            return Row(
                id: "embedded-\(item.id)", lang: item.lang, name: name, source: .embedded,
                isHI: Self.isHI(name), isForced: Self.isForced(name),
                isSelected: engine.selectedSubtitle?.id == item.id
            ) {
                onDisableExternalSubtitles()
                engine.setSubtitle(item)
            }
        }
        let external = externalSubtitles.map { item -> Row in
            Row(
                id: "external-\(item.id)", lang: item.lang, name: item.displayTitle, source: .external,
                isHI: Self.isHI(item.displayTitle), isForced: Self.isForced(item.displayTitle),
                isSelected: selectedExternalSubtitle?.url == item.url
            ) {
                engine.setSubtitle(nil)
                onSelectExternalSubtitle(item)
            }
        }
        return embedded + external
    }

    private var filteredRows: [Row] {
        allRows.filter { row in
            if category == .embedded, row.source != .embedded { return false }
            if category == .external, row.source != .external { return false }
            if showHIOnly, !row.isHI { return false }
            if showForcedOnly, !row.isForced { return false }
            if let selectedLanguage, row.lang.isEmpty ? "und" != selectedLanguage : row.lang != selectedLanguage { return false }
            if !searchText.isEmpty {
                let q = searchText.lowercased()
                if !row.name.lowercased().contains(q), !displayName(for: row.lang).lowercased().contains(q) { return false }
            }
            return true
        }
    }

    private var groups: [(lang: String, items: [Row])] {
        let dict = Dictionary(grouping: filteredRows, by: { $0.lang.isEmpty ? "und" : $0.lang })
        return dict.keys.sorted().map { lang in
            (lang: lang, items: (dict[lang] ?? []).sorted { $0.name < $1.name })
        }
    }

    private var languageCounts: [(code: String, count: Int)] {
        let dict = Dictionary(grouping: allRows, by: { $0.lang.isEmpty ? "und" : $0.lang })
        return dict.map { (code: $0.key, count: $0.value.count) }.sorted { $0.code < $1.code }
    }

    private var isOff: Bool {
        engine.selectedSubtitle == nil && selectedExternalSubtitle == nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().background(PlayerPalette.edgeSoft)
            categoryChips
            Divider().background(PlayerPalette.edgeSoft)

            HStack(alignment: .top, spacing: 0) {
                sidebar
                Divider().background(PlayerPalette.edgeSoft)
                list
            }

            Divider().background(PlayerPalette.edgeSoft)
            searchAndLoadRow

            DelayRow(title: "Subtitle Sync", delay: engine.subDelaySec, disabled: isOff, onDelay: engine.setSubtitleDelay)
        }
        .frame(width: 500)
        .playerChromePanel(cornerRadius: 16)
        .animation(.easeInOut(duration: 0.12), value: category)
        .animation(.easeInOut(duration: 0.12), value: selectedLanguage)
        .animation(.easeInOut(duration: 0.12), value: showHIOnly)
        .animation(.easeInOut(duration: 0.12), value: showForcedOnly)
    }

    private var header: some View {
        HStack {
            HStack(spacing: 6) {
                Text("Subtitles").font(.system(size: 14, weight: .semibold)).foregroundColor(PlayerPalette.ink)
                if !allRows.isEmpty {
                    Text("\(allRows.count)").font(.system(size: 11.5)).foregroundColor(PlayerPalette.inkSubtle)
                }
            }
            Spacer()
            closeButton
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 10)
    }

    private var closeButton: some View {
        Button(action: onClose) {
            Image(systemName: "xmark")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(PlayerPalette.inkMuted)
                .frame(width: 24, height: 24)
                .background(Circle().fill(PlayerPalette.raised))
        }
        .buttonStyle(.plain)
    }

    private var categoryChips: some View {
        HStack(spacing: 6) {
            ForEach(Category.allCases, id: \.self) { c in
                let count = c == .all ? allRows.count : allRows.filter { $0.source == (c == .embedded ? .embedded : .external) }.count
                segmentChip("\(c.rawValue) \(count)", isOn: category == c) { category = c }
            }
            Spacer()
            toggleChip("HI", isOn: showHIOnly) { showHIOnly.toggle() }
            toggleChip("Forced", isOn: showForcedOnly) { showForcedOnly.toggle() }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    private func segmentChip(_ label: String, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 11.5, weight: .semibold))
                .padding(.horizontal, 10).frame(height: 28)
                .background(isOn ? PlayerPalette.elevated : Color.clear, in: Capsule())
                .overlay(Capsule().strokeBorder(isOn ? PlayerPalette.edge : .clear, lineWidth: 1))
                .foregroundColor(isOn ? PlayerPalette.ink : PlayerPalette.inkMuted)
        }
        .buttonStyle(.plain)
    }

    private func toggleChip(_ label: String, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 11, weight: .semibold))
                .padding(.horizontal, 9).frame(height: 24)
                .background(isOn ? AnyShapeStyle(MoonlitTheme.accent) : AnyShapeStyle(PlayerPalette.raised), in: Capsule())
                .foregroundColor(isOn ? .black : PlayerPalette.inkMuted)
        }
        .buttonStyle(.plain)
    }

    private var sidebar: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 2) {
                row(label: "Off", isSelected: isOff, badges: []) {
                    engine.setSubtitle(nil); onDisableExternalSubtitles(); onClose()
                }
                .padding(.bottom, 6)

                Text("LANGUAGES")
                    .font(.system(size: 10, weight: .bold)).tracking(1.4)
                    .foregroundColor(PlayerPalette.inkSubtle)
                    .padding(.horizontal, 8).padding(.bottom, 2)

                sidebarRow(flag: "🌐", label: "All languages", count: allRows.count, isSelected: selectedLanguage == nil) {
                    selectedLanguage = nil
                }
                ForEach(languageCounts, id: \.code) { entry in
                    sidebarRow(flag: LanguageFlag.emoji(for: entry.code), label: displayName(for: entry.code),
                               count: entry.count, isSelected: selectedLanguage == entry.code) {
                        selectedLanguage = entry.code
                    }
                }
            }
            .padding(6)
        }
        .frame(width: 128, height: 300)
        .background(PlayerPalette.canvas.opacity(0.3))
    }

    private func sidebarRow(flag: String, label: String, count: Int, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text(flag).font(.system(size: 12))
                Text(label).font(.system(size: 12, weight: .medium)).foregroundColor(PlayerPalette.inkMuted).lineLimit(1)
                Spacer(minLength: 4)
                Text("\(count)").font(.system(size: 10.5, design: .monospaced)).foregroundColor(PlayerPalette.inkSubtle)
            }
            .padding(.horizontal, 8).padding(.vertical, 6)
            .background(isSelected ? PlayerPalette.elevated : Color.clear, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(isSelected ? PlayerPalette.edge : .clear, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private var list: some View {
        ScrollView(showsIndicators: false) {
            LazyVStack(alignment: .leading, spacing: 2) {
                ForEach(groups, id: \.lang) { group in
                    ForEach(group.items) { item in
                        row(label: item.name, isSelected: item.isSelected, badges: badges(for: item)) {
                            item.select(); onClose()
                        }
                    }
                }
                if filteredRows.isEmpty {
                    Text("No subtitles match").font(.system(size: 11.5)).foregroundColor(PlayerPalette.inkSubtle).padding(10)
                }
                if isLoadingExternal {
                    Text("Loading subtitles…").font(.system(size: 11.5)).foregroundColor(PlayerPalette.inkSubtle)
                        .padding(.horizontal, 10).padding(.vertical, 6)
                }
                if let error {
                    Text(error).font(.system(size: 11.5)).foregroundColor(.orange.opacity(0.85))
                        .padding(.horizontal, 10).padding(.vertical, 6)
                }
            }
            .padding(6)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 300)
    }

    private enum BadgeKind { case neutral, info, warn }
    private func badges(for row: Row) -> [(String, BadgeKind)] {
        var result: [(String, BadgeKind)] = [(row.source == .embedded ? "Embedded" : "External", .neutral)]
        if row.isForced { result.append(("Forced", .info)) }
        if row.isHI { result.append(("HI/SDH", .warn)) }
        return result
    }

    @ViewBuilder
    private func row(label: String, isSelected: Bool, badges: [(String, BadgeKind)], action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                ZStack {
                    Circle().fill(isSelected ? AnyShapeStyle(MoonlitTheme.accent) : AnyShapeStyle(PlayerPalette.raised))
                        .frame(width: 16, height: 16)
                    if isSelected {
                        Image(systemName: "checkmark").font(.system(size: 9, weight: .bold)).foregroundColor(.black)
                    }
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(label).font(.system(size: 12.5, weight: .medium)).foregroundColor(PlayerPalette.ink).lineLimit(1)
                    if !badges.isEmpty {
                        HStack(spacing: 4) {
                            ForEach(badges, id: \.0) { badge in badgeView(badge.0, kind: badge.1) }
                        }
                    }
                }
                Spacer(minLength: 4)
            }
            .padding(.horizontal, 8).padding(.vertical, 7)
            .background(isSelected ? PlayerPalette.elevated : Color.clear, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(isSelected ? PlayerPalette.edge : .clear, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func badgeView(_ text: String, kind: BadgeKind) -> some View {
        let (bg, fg, ring): (Color, Color, Color) = {
            switch kind {
            case .neutral: return (PlayerPalette.raised, PlayerPalette.inkMuted, PlayerPalette.edgeSoft)
            case .info: return (PlayerPalette.infoTintBg, PlayerPalette.infoTintText, PlayerPalette.infoTintRing)
            case .warn: return (PlayerPalette.warnTintBg, PlayerPalette.warnTintText, PlayerPalette.warnTintRing)
            }
        }()
        Text(text)
            .font(.system(size: 9, weight: .bold)).tracking(0.6)
            .foregroundColor(fg)
            .padding(.horizontal, 5).padding(.vertical, 1)
            .background(bg, in: RoundedRectangle(cornerRadius: 4))
            .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(ring, lineWidth: 0.8))
    }

    private var searchAndLoadRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").font(.system(size: 11)).foregroundColor(PlayerPalette.inkSubtle)
            TextField("Find more subtitles", text: $searchText)
                .textFieldStyle(.plain).font(.system(size: 12)).foregroundColor(PlayerPalette.ink)
            Divider().frame(height: 14).background(PlayerPalette.edgeSoft)
            Button(action: loadLocalFile) {
                HStack(spacing: 4) {
                    Image(systemName: "folder")
                    Text("Load file")
                }
                .font(.system(size: 11.5, weight: .semibold)).foregroundColor(PlayerPalette.inkMuted)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
    }

    private func loadLocalFile() {
        #if os(macOS)
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [
            UTType(filenameExtension: "srt"),
            UTType(filenameExtension: "vtt"),
            UTType(filenameExtension: "ass"),
        ].compactMap { $0 }
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let item = SubtitleItem(
            id: "local-\(url.lastPathComponent)",
            url: url.absoluteString,
            lang: "und",
            name: url.deletingPathExtension().lastPathComponent
        )
        engine.setSubtitle(nil)
        onSelectExternalSubtitle(item)
        onClose()
        #endif
    }
}

private extension SubtitleItem {
    var displayTitle: String {
        if let name, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return name
        }
        return lang.isEmpty ? id : lang.uppercased()
    }
}
