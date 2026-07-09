import SwiftUI
import MoonlitCore

struct PlayerControls: View {
    @ObservedObject var engine: PlayerEngine
    let launch: PlayerLaunch
    let onDismiss: () -> Void

    @State private var showSpeed = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button(action: onDismiss) {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                        Text("Back")
                    }
                    .font(.subheadline)
                    .foregroundColor(.white)
                }
                .buttonStyle(.plain)

                Spacer()

                Text(launch.title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                    .lineLimit(1)

                Spacer()

                if let streamTitle = launch.streamTitle {
                    Text(streamTitle)
                        .font(.caption)
                        .foregroundColor(MoonlitTheme.textSecondary)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 4)

            Spacer()

            HStack(spacing: 32) {
                Button { engine.skipBack15() } label: {
                    Image(systemName: "gobackward.15")
                        .font(.title2)
                        .foregroundColor(.white)
                }
                .buttonStyle(.plain)

                Button { engine.togglePlayPause() } label: {
                    Image(systemName: engine.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 44))
                        .foregroundColor(.white)
                }
                .buttonStyle(.plain)

                Button { engine.skipForward15() } label: {
                    Image(systemName: "goforward.15")
                        .font(.title2)
                        .foregroundColor(.white)
                }
                .buttonStyle(.plain)
            }
            .padding(.bottom, 20)

            VStack(spacing: 8) {
                Text(launch.title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Slider(
                    value: Binding(
                        get: { engine.currentPosition },
                        set: { engine.seek(to: $0) }
                    ),
                    in: 0...max(engine.duration, 1)
                )
                .tint(MoonlitTheme.accent)
                .frame(height: 20)

                HStack {
                    Text(formatTime(engine.currentPosition))
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(MoonlitTheme.textTertiary)

                    Spacer()

                    Button { engine.toggleMute() } label: {
                        Image(systemName: engine.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                            .font(.system(size: 16))
                            .foregroundColor(.white)
                    }
                    .buttonStyle(.plain)

                    Button { engine.cycleSubtitle() } label: {
                        Image(systemName: engine.selectedSubtitle != nil ? "captions.bubble.fill" : "captions.bubble")
                            .font(.system(size: 16))
                            .foregroundColor(engine.selectedSubtitle != nil ? MoonlitTheme.accent : .white)
                    }
                    .buttonStyle(.plain)

                    Button { showSpeed.toggle() } label: {
                        Text("\(engine.playbackSpeed, specifier: "%.1f")x")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(Color.white.opacity(0.1))
                            .cornerRadius(MoonlitTheme.radiusSmall)
                    }
                    .buttonStyle(.plain)
                    .popover(isPresented: $showSpeed, arrowEdge: .bottom) {
                        SpeedPicker(engine: engine)
                    }

                    Text(formatTime(engine.duration))
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(MoonlitTheme.textTertiary)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
        .background(
            LinearGradient(
                colors: [.black.opacity(0.7), .clear, .clear, .black.opacity(0.7)],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }

    private func formatTime(_ seconds: Double) -> String {
        let s = Int(seconds)
        let m = s / 60
        let sec = s % 60
        if m >= 60 {
            let h = m / 60
            let min = m % 60
            return String(format: "%d:%02d:%02d", h, min, sec)
        }
        return String(format: "%d:%02d", m, sec)
    }
}
