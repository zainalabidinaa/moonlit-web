import SwiftUI
import MoonlitCore

struct PlayerBottomBar: View {
    @ObservedObject var engine: PlayerEngine

    let hasMultipleSources: Bool
    let onTryAnotherSource: () -> Void

    // Kept for call-site compatibility — unused in this simplified bar
    @Binding var showSubtitles: Bool
    @Binding var showAudio: Bool
    @Binding var showSources: Bool
    let has4KSource: Bool
    let onChoose4K: () -> Void
    let hasEpisodes: Bool
    let hasExternalUrl: Bool

    var body: some View {
        HStack(spacing: 0) {
            // Speed cycle
            Button {
                let speeds: [Float] = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0]
                let current = engine.playbackSpeed
                if let idx = speeds.firstIndex(of: current) {
                    engine.setPlaybackSpeed(speeds[(idx + 1) % speeds.count])
                } else {
                    engine.setPlaybackSpeed(1.0)
                }
            } label: {
                let speed = engine.playbackSpeed
                let label = speed == 1.0 ? "1× Speed" : String(format: speed.truncatingRemainder(dividingBy: 1) == 0 ? "%.0f× Speed" : "%.2g× Speed", speed)
                Text(label)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 14)
                    .frame(height: 36)
            }

            if hasMultipleSources {
                Spacer()

                // Retry: next ranked source
                Button(action: onTryAnotherSource) {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.system(size: 13, weight: .semibold))
                        Text("Retry")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 14)
                    .frame(height: 36)
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .glassCard(cornerRadius: 999)
        .padding(.horizontal, 8)
    }
}

private struct PlayerGlassPanelModifier: ViewModifier {
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        #if os(iOS)
        if #available(iOS 26, *) {
            content
                .glassEffect(
                    .clear.interactive(),
                    in: .rect(cornerRadius: cornerRadius, style: .continuous)
                )
        } else {
            content
                .background(.ultraThinMaterial)
                .background(Color.black.opacity(0.58))
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .stroke(Color.white.opacity(0.12), lineWidth: 0.5)
                }
        }
        #else
        content
            .background(.ultraThinMaterial)
            .background(Color.black.opacity(0.58))
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Color.white.opacity(0.12), lineWidth: 0.5)
            }
        #endif
    }
}

extension View {
    func playerGlassPanel(cornerRadius: CGFloat = 14) -> some View {
        modifier(PlayerGlassPanelModifier(cornerRadius: cornerRadius))
    }
}
