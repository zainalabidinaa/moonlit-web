import SwiftUI

/// Minimal control set shown over the floating PiP window — deliberately
/// smaller than the full transport bar, matching Harbor's `PipChrome`.
struct PipChrome: View {
    @ObservedObject var engine: MPVPlayerEngine
    let hasPrevEp: Bool
    let hasNextEp: Bool
    let onPrevEp: () -> Void
    let onNextEp: () -> Void
    let onExitPip: () -> Void

    var body: some View {
        VStack {
            HStack {
                Spacer()
                pipButton(system: "pip.exit", action: onExitPip)
            }
            Spacer()
            HStack(spacing: 6) {
                pipButton(system: "chevron.left.2", enabled: hasPrevEp, action: onPrevEp)
                pipButton(system: "gobackward.10") { engine.seekBy(-10) }
                pipButton(
                    system: engine.isPlaying ? "pause.fill" : "play.fill",
                    action: engine.togglePlayPause
                )
                pipButton(system: "goforward.10") { engine.seekBy(10) }
                pipButton(system: "chevron.right.2", enabled: hasNextEp, action: onNextEp)
                Spacer()
                pipButton(system: engine.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill") {
                    engine.toggleMute()
                }
            }
        }
        .padding(10)
        .background(
            LinearGradient(colors: [.black.opacity(0.5), .clear, .black.opacity(0.5)], startPoint: .top, endPoint: .bottom)
        )
    }

    @ViewBuilder
    private func pipButton(system: String, enabled: Bool = true, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: system)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white.opacity(enabled ? 0.9 : 0.3))
                .frame(width: 28, height: 28)
                .background(Circle().fill(Color.white.opacity(0.12)))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }
}
