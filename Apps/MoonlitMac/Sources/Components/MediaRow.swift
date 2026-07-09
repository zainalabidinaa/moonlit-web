import SwiftUI
import MoonlitCore

struct MediaRow: View {
    let row: CatalogRow
    let onTap: (MetaPreview) -> Void
    var onHeaderTap: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            rowHeader(title: row.title, onHeaderTap: onHeaderTap)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 18) {
                    ForEach(row.items) { item in
                        MediaCard(item: item, row: row)
                            .equatable()
                            .onTapGesture { onTap(item) }
                    }
                }
                .padding(.horizontal, 32)
                .padding(.vertical, 10)
            }
        }
    }
}

struct MacCollectionRowContainer: View {
    let row: CatalogRow
    let style: RowDisplayStyle
    let onTap: (MetaPreview) -> Void
    var onHeaderTap: (() -> Void)?

    var body: some View {
        switch style {
        case .standard:
            MediaRow(row: row, onTap: onTap, onHeaderTap: onHeaderTap)
        case .heroBanner:
            MacHeroBannerRow(row: row, onTap: onTap, onHeaderTap: onHeaderTap)
        case .cardStack:
            MacCardStackRow(row: row, onTap: onTap, onHeaderTap: onHeaderTap)
        case .carouselCinematic:
            MacCarouselCinematicRow(row: row, onTap: onTap)
        case .topTen:
            MacTopTenRow(row: row, onTap: onTap, onHeaderTap: onHeaderTap)
        }
    }
}

private struct MacHeroBannerRow: View {
    let row: CatalogRow
    let onTap: (MetaPreview) -> Void
    var onHeaderTap: (() -> Void)?

    private var leadItem: MetaPreview? { row.items.first }
    private var secondaryItems: ArraySlice<MetaPreview> { row.items.dropFirst().prefix(4) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            rowHeader(title: row.title, onHeaderTap: onHeaderTap)

            if let leadItem {
                VStack(spacing: 0) {
                    Button { onTap(leadItem) } label: {
                        ZStack(alignment: .bottomLeading) {
                            landscapeArtwork(for: leadItem)
                                .frame(height: 300)
                                .frame(maxWidth: .infinity)
                                .clipped()

                            LinearGradient(
                                colors: [.black.opacity(0.72), .black.opacity(0.22), .clear],
                                startPoint: .bottomLeading,
                                endPoint: .topTrailing
                            )

                            VStack(alignment: .leading, spacing: 8) {
                                Text(leadItem.name)
                                    .font(.system(size: 30, weight: .black))
                                    .foregroundStyle(.white)
                                    .lineLimit(2)
                                if let release = leadItem.releaseInfo ?? leadItem.released {
                                    Text(release)
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundStyle(.white.opacity(0.72))
                                }
                            }
                            .padding(22)
                        }
                    }
                    .buttonStyle(.plain)

                    HStack(alignment: .top, spacing: 12) {
                        ForEach(Array(secondaryItems), id: \.id) { item in
                            Button { onTap(item) } label: {
                                VStack(alignment: .leading, spacing: 6) {
                                    landscapeArtwork(for: item)
                                        .frame(height: 100)
                                        .frame(maxWidth: .infinity)
                                        .clipShape(RoundedRectangle(cornerRadius: MoonlitTheme.radiusControl, style: .continuous))
                                    Text(item.name)
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundStyle(.white)
                                        .lineLimit(1)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(14)
                    .background(Color.white.opacity(0.05))
                }
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
                )
                .padding(.horizontal, 32)
            }
        }
    }
}

private struct MacCardStackRow: View {
    let row: CatalogRow
    let onTap: (MetaPreview) -> Void
    var onHeaderTap: (() -> Void)?

    @State private var frontOffset = -1

    private var stackItems: [MetaPreview] { Array(row.items.prefix(9)) }
    private var count: Int { stackItems.count }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            rowHeader(title: row.title, onHeaderTap: onHeaderTap)

            ZStack {
                ForEach(Array(stackItems.enumerated()), id: \.element.id) { index, item in
                    stackCard(item: item, index: index)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 330)
            .contentShape(Rectangle())
            .onAppear {
                if frontOffset < 0 { frontOffset = count / 2 }
            }
            .gesture(
                DragGesture(minimumDistance: 20)
                    .onEnded { value in
                        guard abs(value.translation.width) > abs(value.translation.height) else { return }
                        withAnimation(.spring(response: 0.42, dampingFraction: 0.82)) {
                            frontOffset += value.translation.width < -30 ? 1 : value.translation.width > 30 ? -1 : 0
                        }
                    }
            )
        }
    }

    private var frontIndex: Int {
        let offset = frontOffset < 0 ? count / 2 : frontOffset
        return wrappedIndex(offset)
    }

    private func stackCard(item: MetaPreview, index: Int) -> some View {
        let layout = stackLayout(index: index)
        let isFront = index == frontIndex

        return MediaCard(item: item, row: CatalogRow(id: row.id, title: row.title, items: row.items, tileShape: "poster"))
            .equatable()
            .scaleEffect(layout.scale)
            .rotationEffect(.degrees(layout.rotation))
            .offset(x: layout.x, y: layout.y)
            .opacity(layout.opacity)
            .zIndex(layout.zIndex)
            .onTapGesture {
                if isFront {
                    onTap(item)
                } else {
                    withAnimation(.spring(response: 0.42, dampingFraction: 0.82)) {
                        frontOffset += circularDistance(from: frontIndex, to: index, count: count)
                    }
                }
            }
    }

    private func wrappedIndex(_ raw: Int) -> Int {
        guard count > 0 else { return 0 }
        return ((raw % count) + count) % count
    }

    private func circularDistance(from: Int, to: Int, count: Int) -> Int {
        guard count > 0 else { return 0 }
        let raw = to - from
        let half = count / 2
        if raw > half { return raw - count }
        if raw < -half { return raw + count }
        return raw
    }

    private func stackLayout(index: Int) -> StackLayout {
        let distance = circularDistance(from: frontIndex, to: index, count: count)
        let clamped = max(-4, min(4, distance))
        let isFront = distance == 0
        return StackLayout(
            x: CGFloat(clamped) * 44,
            y: abs(CGFloat(clamped)) * 10,
            rotation: Double(clamped) * 5.5,
            scale: isFront ? 1.0 : max(0.72, 0.94 - CGFloat(abs(clamped)) * 0.055),
            opacity: max(0.46, 1.0 - Double(abs(clamped)) * 0.10),
            zIndex: Double(100 - abs(distance))
        )
    }
}

private struct MacCarouselCinematicRow: View {
    let row: CatalogRow
    let onTap: (MetaPreview) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            rowHeader(title: row.title, onHeaderTap: nil)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 18) {
                    ForEach(Array(row.items.enumerated()), id: \.element.id) { index, item in
                        CinematicTile(
                            item: item,
                            width: index == 0 ? 420 : 320,
                            height: 190
                        )
                        .onTapGesture { onTap(item) }
                    }
                }
                .padding(.horizontal, 32)
                .padding(.vertical, 10)
            }
        }
    }
}

private struct CinematicTile: View {
    let item: MetaPreview
    let width: CGFloat
    let height: CGFloat

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            landscapeArtwork(for: item)

            LinearGradient(
                colors: [.clear, .black.opacity(0.72)],
                startPoint: .center,
                endPoint: .bottom
            )

            Text(item.name)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .padding(12)
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: MoonlitTheme.radiusCard, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: MoonlitTheme.radiusCard, style: .continuous)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
        )
    }
}

private struct StackLayout {
    let x: CGFloat
    let y: CGFloat
    let rotation: Double
    let scale: CGFloat
    let opacity: Double
    let zIndex: Double
}

@ViewBuilder
@MainActor
private func rowHeader(title: String, onHeaderTap: (() -> Void)?) -> some View {
    Button(action: { onHeaderTap?() }) {
        HStack(spacing: 10) {
            Text(title)
                .font(.system(size: 21, weight: .bold))
                .foregroundColor(.white)
            Spacer()
            if onHeaderTap != nil {
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.white.opacity(0.78))
                    .frame(width: 32, height: 32)
                    .background(Color.white.opacity(0.10), in: Circle())
            }
        }
        .padding(.horizontal, 32)
    }
    .buttonStyle(.plain)
    .disabled(onHeaderTap == nil)
}

@ViewBuilder
@MainActor
private func landscapeArtwork(for item: MetaPreview) -> some View {
    if let url = item.artworkURL(preferring: .landscape) {
        CachedAsyncImage(url: url) { image in
            image.resizable().aspectRatio(contentMode: .fill)
        } placeholder: {
            MoonlitTheme.surfaceElevated
        }
    } else {
        MoonlitTheme.surfaceElevated
    }
}
