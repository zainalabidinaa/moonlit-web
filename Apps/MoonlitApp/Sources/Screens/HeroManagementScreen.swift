import SwiftUI
import MoonlitCore

struct HeroManagementScreen: View {
    @StateObject private var catalogRepo = CatalogRepository.shared
    @StateObject private var heroStore = HeroPreferenceStore.shared

    private let defaultHeroTitles: Set<String> = [
        "Popular Movies", "Popular TV Shows",
        "Trending Movies", "Trending TV Shows"
    ]

    // Rows that are candidates for the hero (have items)
    private var allRows: [CatalogRow] {
        catalogRepo.catalogRows.filter { !$0.items.isEmpty }
    }

    // The display order for the "Catalog Order" section:
    // stored order first, then any default titles not yet in order
    private var orderedEnabledRows: [CatalogRow] {
        let enabledTitles: [String]
        if heroStore.rowOrder.isEmpty {
            // No saved order — use default set in natural row order
            enabledTitles = allRows
                .filter { defaultHeroTitles.contains($0.title) }
                .map(\.title)
        } else {
            enabledTitles = heroStore.rowOrder.filter { heroStore.isEnabled(rowTitle: $0) }
        }
        return enabledTitles.compactMap { title in
            allRows.first { $0.title == title }
        }
    }

    private func isEnabled(_ row: CatalogRow) -> Bool {
        if heroStore.rowOrder.isEmpty {
            return defaultHeroTitles.contains(row.title)
        }
        return heroStore.isEnabled(rowTitle: row.title)
    }

    var body: some View {
        List {
            Section {
                Text("Pick a single catalog to feed the hero, or leave it on Default to use trending. The order/toggles below are a fallback used only when the selected catalog is unavailable.")
                    .font(.caption)
                    .foregroundColor(MoonlitTheme.textSecondary)
                    .listRowBackground(Color.clear)
            }

            // ── HERO SOURCE (single catalog that feeds the hero) ─────
            Section("Hero Source") {
                Picker("Source", selection: Binding(
                    get: { heroStore.heroCatalogId ?? "" },
                    set: { heroStore.setHeroCatalogId($0.isEmpty ? nil : $0) }
                )) {
                    Text("Default (Trending)").tag("")
                    ForEach(allRows) { row in
                        Text(row.title).tag(row.id)
                    }
                }
                .pickerStyle(.navigationLink)
                .tint(.white)
                .listRowBackground(MoonlitTheme.surfaceElevated.opacity(0.5))
            }

            // ── CATALOG ORDER (enabled rows, draggable) ──────────────
            if !orderedEnabledRows.isEmpty {
                Section("Catalog Order") {
                    ForEach(orderedEnabledRows) { row in
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(row.title)
                                    .foregroundColor(.white)
                                    .font(.body)
                                if let addonName = row.addonName {
                                    Text(addonName)
                                        .font(.caption2)
                                        .foregroundColor(MoonlitTheme.textTertiary)
                                }
                            }
                            Spacer()
                            Image(systemName: "line.3.horizontal")
                                .font(.body)
                                .foregroundColor(MoonlitTheme.textTertiary)
                        }
                        .listRowBackground(MoonlitTheme.surfaceElevated.opacity(0.5))
                    }
                    .onMove { source, destination in
                        // Build current order, apply move, save
                        var current = orderedEnabledRows.map(\.title)
                        current.move(fromOffsets: source, toOffset: destination)
                        // Merge: put moved enabled rows first, preserve disabled at end
                        let disabled = heroStore.rowOrder.filter { !heroStore.isEnabled(rowTitle: $0) }
                        heroStore.setOrder(current + disabled)
                    }
                }
            }

            // ── ENABLED FOR HERO (all available rows, with toggle) ───
            Section("Available Catalogs") {
                if allRows.isEmpty {
                    Text("No catalogs loaded yet. Return to Home to load content first.")
                        .font(.caption)
                        .foregroundColor(MoonlitTheme.textTertiary)
                        .listRowBackground(Color.clear)
                } else {
                    ForEach(allRows) { row in
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(row.title)
                                    .foregroundColor(.white)
                                if let addonName = row.addonName {
                                    Text(addonName)
                                        .font(.caption2)
                                        .foregroundColor(MoonlitTheme.textTertiary)
                                }
                            }
                            Spacer()
                            Toggle("", isOn: Binding(
                                get: { isEnabled(row) },
                                set: { enabled in
                                    if heroStore.rowOrder.isEmpty {
                                        // First interaction — initialize order from defaults
                                        let defaultOrder = allRows
                                            .filter { defaultHeroTitles.contains($0.title) }
                                            .map(\.title)
                                        heroStore.setOrder(defaultOrder)
                                    }
                                    heroStore.setEnabled(enabled, for: row.title)
                                }
                            ))
                            .labelsHidden()
                            .tint(MoonlitTheme.accent)
                        }
                        .listRowBackground(MoonlitTheme.surfaceElevated.opacity(0.5))
                    }
                }
            }
        }
#if os(iOS)
        .scrollContentBackground(.hidden)
#endif
        .background(MoonlitTheme.background)
        .navigationTitle("Hero Management")
#if os(iOS)
        .navigationBarTitleDisplayMode(.large)
#endif
        .environment(\.editMode, .constant(.active))
    }
}
