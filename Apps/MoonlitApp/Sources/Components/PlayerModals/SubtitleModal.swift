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
