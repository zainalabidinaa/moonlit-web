import SwiftUI
import MoonlitCore

struct CollectionDesignScreen: View {
    @StateObject private var collectionRepo = CollectionRepository.shared
    @StateObject private var collectionPreferences = CollectionDisplayPreferenceStore.shared
    @StateObject private var styleStore = CollectionRowDisplayStyleStore.shared

    var body: some View {
        ZStack {
            MoonlitTheme.background.ignoresSafeArea()

            if rowTitles.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "rectangle.stack.badge.questionmark")
                        .font(.system(size: 42))
                        .foregroundColor(MoonlitTheme.textTertiary)
                    Text("No collection rows yet")
                        .font(.headline)
                        .foregroundColor(.white)
                    Text("Rows appear here after your home collections load.")
                        .font(.subheadline)
                        .foregroundColor(MoonlitTheme.textSecondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 32)
            } else {
                List {
                    Section {
                        Text("Choose how each collection row appears on Home.")
                            .font(.caption)
                            .foregroundColor(MoonlitTheme.textSecondary)
                    }

                    ForEach(rowTitles, id: \.self) { title in
                        Section(title) {
                            ForEach(RowDisplayStyle.allCases) { style in
                                Button {
                                    styleStore.setStyle(style, forRowTitle: title)
                                } label: {
                                    HStack(spacing: 12) {
                                        CollectionStylePreview(style: style)
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(style.displayName)
                                                .foregroundColor(.white)
                                            Text(styleDescription(style))
                                                .font(.caption)
                                                .foregroundColor(MoonlitTheme.textTertiary)
                                        }
                                        Spacer()
                                        if styleStore.style(forRowTitle: title) == style {
                                            Image(systemName: "checkmark.circle.fill")
                                                .foregroundColor(MoonlitTheme.accent)
                                        }
                                    }
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
#if os(iOS)
                .scrollContentBackground(.hidden)
#endif
            }
        }
        .navigationTitle("Collection Design")
#if os(iOS)
        .navigationBarTitleDisplayMode(.large)
#endif
    }

    private var rowTitles: [String] {
        collectionRepo.collections.flatMap { collection -> [String] in
            guard collectionPreferences.isCollectionEnabled(collection) else { return [] }
            let folders = collectionRepo.folders(for: collection)
            if collectionPreferences.isCollectionExpanded(collection) {
                return folders
                    .filter { !collectionPreferences.isFolderHidden($0) }
                    .map(\.name)
            }
            return [collection.name]
        }
    }

    private func styleDescription(_ style: RowDisplayStyle) -> String {
        switch style {
        case .standard: return "Classic horizontal cards"
        case .heroBanner: return "Wide lead image with smaller picks"
        case .cardStack: return "Featured stacked card plus scroll"
        case .carouselCinematic: return "Wide 16:9 cinematic carousel"
        case .topTen: return "Numbered ranking, 1 through 10"
        }
    }
}

private struct CollectionStylePreview: View {
    let style: RowDisplayStyle

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: MoonlitTheme.radiusControl)
                .fill(Color.white.opacity(0.08))
            preview
                .padding(6)
        }
        .frame(width: 58, height: 42)
    }

    @ViewBuilder private var preview: some View {
        switch style {
        case .standard:
            HStack(spacing: 4) {
                previewCard(width: 12)
                previewCard(width: 12)
                previewCard(width: 12)
            }
        case .heroBanner:
            VStack(spacing: 4) {
                previewCard(width: 42, height: 14)
                HStack(spacing: 3) {
                    previewCard(width: 12, height: 10)
                    previewCard(width: 12, height: 10)
                    previewCard(width: 12, height: 10)
                }
            }
        case .cardStack:
            ZStack {
                previewCard(width: 22, height: 28).rotationEffect(.degrees(-8)).offset(x: -4)
                previewCard(width: 22, height: 28).rotationEffect(.degrees(7)).offset(x: 4)
                previewCard(width: 22, height: 28)
            }
        case .carouselCinematic:
            HStack(spacing: 4) {
                previewCard(width: 26, height: 18)
                previewCard(width: 18, height: 18)
            }
        case .topTen:
            HStack(spacing: -6) {
                Text("1")
                    .font(.system(size: 22, weight: .black, design: .rounded))
                    .foregroundColor(.white.opacity(0.4))
                previewCard(width: 16, height: 22)
            }
        }
    }

    private func previewCard(width: CGFloat, height: CGFloat = 24) -> some View {
        RoundedRectangle(cornerRadius: MoonlitTheme.radiusSmall)
            .fill(Color.white.opacity(0.55))
            .frame(width: width, height: height)
    }
}
