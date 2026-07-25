import SwiftUI
import MoonlitCore

struct CardStackRow: View {
    let row: CatalogRow
    let onTap: (MetaPreview) -> Void
    var onHeaderTap: (() -> Void)? = nil
    var metrics: ResponsiveMetrics? = nil
#if os(tvOS)
    @Environment(\.isFocused) var isFocused
#endif

    // Start in the middle of the array so cards fan on both sides
    @State private var frontOffset: Int = -1  // -1 = uninitialized, set on appear

    private var stackItems: [MetaPreview] { Array(row.items.prefix(9)) }

    private var count: Int { stackItems.count }

    // Wraps index circularly
    private func wrappedIndex(_ raw: Int) -> Int {
        guard count > 0 else { return 0 }
        return ((raw % count) + count) % count
    }

    // frontOffset can grow unbounded; the actual front card index is wrapped
    // If uninitialized, default to the middle of the stack
    private var frontIndex: Int {
        let offset = frontOffset < 0 ? count / 2 : frontOffset
        return wrappedIndex(offset)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            rowHeader

            ZStack {
                ForEach(Array(stackItems.enumerated()), id: \.element.id) { index, item in
                    stackCard(item: item, index: index)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: stackAreaHeight)
            .padding(.horizontal, 16)
            .contentShape(Rectangle())
            .onAppear {
                if frontOffset < 0 { frontOffset = count / 2 }
            }
#if os(iOS)
            .gesture(
                DragGesture(minimumDistance: 20)
                    .onEnded { value in
                        guard abs(value.translation.width) > abs(value.translation.height) else { return }
                        withAnimation(.spring(response: 0.42, dampingFraction: 0.82)) {
                            if value.translation.width < -30 {
                                frontOffset += 1
                            } else if value.translation.width > 30 {
                                frontOffset -= 1
                            }
                        }
                    }
            )
#endif
        }
    }

    private var rowHeader: some View {
        Button(action: { onHeaderTap?() }) {
            HStack {
                Text(row.title)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(.white)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundColor(.white.opacity(0.78))
                    .frame(width: 34, height: 34)
                    .background(Color.white.opacity(0.10), in: Circle())
            }
            .padding(.horizontal, 16)
        }
        .buttonStyle(.plain)
        .disabled(onHeaderTap == nil)
    }

    @ViewBuilder
    private func stackCard(item: MetaPreview, index: Int) -> some View {
        let layout = stackLayout(index: index)
        let isFront = index == frontIndex

        StackPosterArtwork(item: item)
            .frame(width: posterWidth, height: posterHeight)
            .clipShape(RoundedRectangle(cornerRadius: MoonlitTheme.radiusLarge, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: MoonlitTheme.radiusLarge, style: .continuous)
                    .stroke(Color.white.opacity(isFront ? 0.20 : 0.10), lineWidth: 1)
            )
            .shadow(color: .black.opacity(isFront ? 0.46 : 0.28), radius: isFront ? 22 : 12, x: 0, y: 12)
            .scaleEffect(layout.scale)
            .rotationEffect(.degrees(layout.rotation))
            .offset(x: layout.x, y: layout.y)
            .opacity(layout.opacity)
            .zIndex(layout.zIndex)
            .onTapGesture {
                if isFront {
                    onTap(item)
                } else {
                    // Tapping a non-front card brings it to front
                    withAnimation(.spring(response: 0.42, dampingFraction: 0.82)) {
                        let delta = circularDistance(from: frontIndex, to: index, count: count)
                        frontOffset += delta
                    }
                }
            }
#if os(tvOS)
            .scaleEffect(isFocused ? 1.05 : 1.0)
            .animation(.easeOut(duration: 0.15), value: isFocused)
            .shadow(color: isFocused ? Color.white.opacity(0.3) : .clear, radius: isFocused ? 10 : 0)
#endif
    }

    // Signed shortest circular distance from `from` to `to`
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
            x: CGFloat(clamped) * 34,
            y: abs(CGFloat(clamped)) * 8,
            rotation: Double(clamped) * 5.5,
            scale: isFront ? 1.0 : max(0.72, 0.94 - CGFloat(abs(clamped)) * 0.055),
            opacity: max(0.46, 1.0 - Double(abs(clamped)) * 0.10),
            zIndex: Double(100 - abs(distance))
        )
    }

    private var posterWidth: CGFloat {
        min(170, max(138, UIScreen.main.bounds.width * 0.39))
    }

    private var posterHeight: CGFloat {
        posterWidth * 1.48
    }

    private var stackAreaHeight: CGFloat {
        posterHeight + 52
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

private struct StackPosterArtwork: View {
    let item: MetaPreview

    var body: some View {
        // Prefer the live-configured btttr badge poster (imdb id); fall back to the
        // item's own portrait art for non-imdb ids.
        let url = PosterService.posterURL(forImdbId: item.id).flatMap(URL.init)
            ?? item.artworkURL(preferring: .portrait)
        if let url {
            CachedAsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().aspectRatio(contentMode: .fill)
                default:
                    MoonlitTheme.surfaceElevated
                }
            }
        } else {
            MoonlitTheme.surfaceElevated
        }
    }
}
